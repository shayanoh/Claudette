import AppKit
import ClaudetteCore
import SpriteKit

/// One Claudette on screen (one per Claude Code session).
final class Actor {
  let sessionID: String
  let order: Int
  let puppet = PuppetNode()
  var display: CGDirectDisplayID
  /// Lower-left of her clickable rectangle, in global screen coordinates.
  var origin: CGPoint = .zero
  var userPlaced = false
  var visible = true
  var placedOnce = false
  var minis: [String: PuppetNode] = [:]
  var props: [(id: String, node: PropNode)] = []
  var lastPhase: SessionPhase = .idle
  var isDodging = false
  var lastDodge = Date.distantPast
  var dodgedAt: Date?
  var fadeTarget: CGFloat = 1
  var hoverSince: Date?
  var hoverPoint = CGPoint.zero
  var petted = false

  init(sessionID: String, order: Int, display: CGDirectDisplayID) {
    self.sessionID = sessionID
    self.order = order
    self.display = display
  }
}

/// Owns every on-screen Claudette: layout, session reactions, hover fade, dodging, dragging.
final class Stage {
  static let activeFPS = 30
  static let idleFPS = 8
  private var lastActivity = Date.distantPast
  private var currentFPS = Stage.activeFPS

  /// Call whenever something lively happens so the scene renders at full speed for a few seconds.
  func noteActivity() { lastActivity = Date() }

  private func updateFrameRate() {
    let busy =
      Date().timeIntervalSince(lastActivity) < 3 || dragging != nil
      || actors.values.contains {
        !$0.props.isEmpty || $0.lastPhase != .idle && $0.lastPhase != .sleeping
      }
    let fps = busy ? Stage.activeFPS : Stage.idleFPS
    guard fps != currentFPS else { return }
    currentFPS = fps
    overlay.setFrameRate(fps)
  }

  private let overlay: OverlayController
  private let settings: SettingsStore
  private(set) var actors: [String: Actor] = [:]
  private var nextOrder = 0
  private var lastPointer = CGPoint.zero
  private var badges: [CGDirectDisplayID: SKShapeNode] = [:]

  // Dragging
  private var dragging: Actor?
  private var dragOffset = CGPoint.zero
  private var physics = DragPhysics()
  private var lastDragTime = Date()
  private var lastDragPoint = CGPoint.zero

  private var timer: Timer?

  init(overlay: OverlayController, settings: SettingsStore) {
    self.overlay = overlay
    self.settings = settings
    overlay.mouseHandler = { [weak self] phase, point in
      switch phase {
      case .down: self?.mouseDown(point)
      case .dragged: self?.mouseDragged(point)
      case .up: self?.mouseUp(point)
      }
    }
    overlay.onScreensChanged = { [weak self] in self?.screensChanged() }
    timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
      self?.tick()
    }
  }

  deinit { timer?.invalidate() }

  // MARK: - Geometry helpers

  private var scale: CGFloat { CGFloat(settings.settings.scale) }
  private var spriteSize: CGSize {
    CGSize(width: PuppetNode.hitBounds.width * scale, height: PuppetNode.hitBounds.height * scale)
  }

  private func screen(_ display: CGDirectDisplayID) -> NSScreen? {
    NSScreen.screens.first { OverlayController.displayID(of: $0) == display }
  }

  private var screenFrames: [CGRect] { NSScreen.screens.map(\.frame) }

  private func rect(_ a: Actor) -> CGRect { CGRect(origin: a.origin, size: spriteSize) }

  private func display(at point: CGPoint) -> CGDirectDisplayID? {
    for s in NSScreen.screens where s.frame.contains(point) {
      return OverlayController.displayID(of: s)
    }
    return nil
  }

  /// Puppet position (feet centre) in its display's scene coordinates.
  private func scenePosition(_ a: Actor) -> CGPoint {
    let f = screen(a.display)?.frame ?? .zero
    return CGPoint(
      x: a.origin.x - f.minX - PuppetNode.hitBounds.minX * scale,
      y: a.origin.y - f.minY - PuppetNode.hitBounds.minY * scale)
  }

  // MARK: - Sessions

  func apply(_ changes: [SessionChange], sessions: [String: SessionState] = [:]) {
    if !changes.isEmpty { noteActivity() }
    for change in changes {
      switch change {
      case .started(let id): addActor(id)
      case .ended(let id): removeActor(id)
      case .phaseChanged(let id, let phase): phaseChanged(id, phase)
      case .subagentStarted(let id, let agent): addMini(id, agent)
      case .subagentStopped(let id, let agent): removeMini(id, agent)
      case .toolStarted(let id, let tool): addProp(id, tool)
      case .toolFinished(let id, let toolID, let ok): removeProp(id, toolID, success: ok)
      case .longShell(let id, let toolID): upgradeShell(id, toolID)
      case .skillLoaded(let id, let name):
        actors[id]?.puppet.rune(settings.settings.privacyMode ? "•••" : name)
      case .compacted(let id): actors[id]?.puppet.compact()
      default: break
      }
    }
    for (id, state) in sessions {
      actors[id]?.puppet.setContext(
        state.contextUsedPercentage, privacy: settings.settings.privacyMode)
    }
    updatePause()
  }

  /// Rendering stops only when nothing is on screen, including characters still leaving.
  private func updatePause() {
    let leaving = overlay.overlays.values.contains { overlay in
      overlay.scene.children.contains { $0.name?.hasPrefix("puppet-") == true }
    }
    overlay.setPaused(actors.isEmpty && !leaving)
  }

  private func addActor(_ id: String) {
    guard actors[id] == nil, let display = cursorDisplay() ?? overlay.mainDisplayID else { return }
    let a = Actor(sessionID: id, order: nextOrder, display: display)
    nextOrder += 1
    actors[id] = a
    a.puppet.setScale(scale)
    a.puppet.name = "puppet-\(id)"
    relayout()
    a.puppet.wake()
  }

  private func removeActor(_ id: String) {
    guard let a = actors.removeValue(forKey: id) else { return }
    if dragging === a { dragging = nil }
    a.puppet.sleep()
    a.puppet.run(
      .sequence([.wait(forDuration: 1.4), .fadeOut(withDuration: 0.5), .removeFromParent()]))
    relayout()
    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in self?.updatePause() }
  }

  private func phaseChanged(_ id: String, _ phase: SessionPhase) {
    guard let a = actors[id] else { return }
    if phase == .sleeping {
      a.puppet.sleep()
    } else if a.puppet.isAsleep {
      a.puppet.idle()
    }
    if case .error = a.lastPhase, !isError(phase) { a.puppet.relief() }
    a.lastPhase = phase
    a.puppet.setStatus(phase)
  }

  private func isError(_ phase: SessionPhase) -> Bool {
    if case .error = phase { return true }
    return false
  }

  // MARK: Props

  private static let propSlots: [CGPoint] = [
    CGPoint(x: -150, y: 70), CGPoint(x: -168, y: 12), CGPoint(x: -150, y: 128),
    CGPoint(x: -214, y: 50),
  ]

  private func addProp(_ id: String, _ tool: ToolActivity) {
    guard let a = actors[id], !a.props.contains(where: { $0.id == tool.toolUseID }) else { return }
    let scene = SceneMapper.scene(for: tool, now: Date())
    if scene == .subagent { return }
    let node = PropNode(scene: scene, privacy: settings.settings.privacyMode)
    node.setScale(0.01)
    a.puppet.addChild(node)
    a.props.append((tool.toolUseID, node))
    layoutProps(a)
    node.run(.scale(to: 1, duration: 0.25))
  }

  private func removeProp(_ id: String, _ toolID: String, success: Bool) {
    guard let a = actors[id], let i = a.props.firstIndex(where: { $0.id == toolID }) else { return }
    let node = a.props.remove(at: i).node
    node.run(.sequence([.scale(to: 0.01, duration: 0.2), .removeFromParent()]))
    if !success {
      a.puppet.run(
        .sequence([
          .moveBy(x: 4, y: 0, duration: 0.05), .moveBy(x: -8, y: 0, duration: 0.1),
          .moveBy(x: 4, y: 0, duration: 0.05),
        ]))
    }
    layoutProps(a)
  }

  private func upgradeShell(_ id: String, _ toolID: String) {
    guard let a = actors[id], let i = a.props.firstIndex(where: { $0.id == toolID }) else { return }
    let old = a.props[i].node
    let node = PropNode(
      scene: .shell(long: true, background: false), privacy: settings.settings.privacyMode)
    node.position = old.position
    a.puppet.addChild(node)
    old.removeFromParent()
    a.props[i] = (toolID, node)
    layoutProps(a)
  }

  /// Props stand beside her, newest nearest; more activity means a busier, more cluttered Claudette.
  private func layoutProps(_ a: Actor) {
    for (i, entry) in a.props.suffix(Self.propSlots.count).reversed().enumerated() {
      let target = Self.propSlots[i]
      entry.node.run(.move(to: target, duration: 0.25))
      entry.node.setCableEnd(CGPoint(x: 80 - target.x, y: 50 - target.y))
    }
  }

  private func addMini(_ id: String, _ agent: String) {
    guard let a = actors[id], a.minis[agent] == nil else { return }
    let mini = PuppetNode()
    mini.setScale(0.55)
    mini.position = CGPoint(x: 70 + CGFloat(a.minis.count) * 85, y: -12)
    mini.zPosition = 5
    a.puppet.addChild(mini)
    a.minis[agent] = mini
    mini.wake()
  }

  private func removeMini(_ id: String, _ agent: String) {
    guard let mini = actors[id]?.minis.removeValue(forKey: agent) else { return }
    mini.run(.sequence([.fadeOut(withDuration: 0.3), .removeFromParent()]))
  }

  private func cursorDisplay() -> CGDirectDisplayID? { display(at: NSEvent.mouseLocation) }

  // MARK: - Layout

  func settingsChanged() {
    actors.values.forEach { $0.puppet.setScale(scale) }
    overlay.focusHidden = settings.settings.focusMode
    relayout()
  }

  /// The app's own setting or the system-wide Reduce Motion preference.
  var reduceMotion: Bool {
    settings.settings.reduceMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
  }

  private func screensChanged() {
    for a in actors.values {
      if screen(a.display) == nil, let main = overlay.mainDisplayID { a.display = main }
      // The clamp may move her onto another screen: her display (and scene) must follow.
      if let i = ScreenFit.nearestScreenIndex(
        for: a.origin, size: spriteSize, screens: screenFrames),
        let id = OverlayController.displayID(of: NSScreen.screens[i])
      {
        a.display = id
      }
      a.origin = ScreenFit.clamp(a.origin, size: spriteSize, to: screenFrames)
      applyDisplayParent(a)
    }
    relayout()
  }

  func relayout() {
    let displays = Set(actors.values.map(\.display))
    for display in displays {
      guard let screen = screen(display) else { continue }
      let free = actors.values.filter { $0.display == display && !$0.userPlaced }.sorted {
        $0.order < $1.order
      }
      let result = Placement.layout(
        count: free.count, screen: screen.visibleFrame, spriteSize: spriteSize)
      for (i, a) in free.enumerated() {
        a.visible = i < result.full.count
        if a.visible { a.origin = result.full[i] }
      }
      updateBadge(display, overflow: result.overflow, at: result.full.last, screen: screen)
    }
    for a in actors.values { applyPosition(a) }
  }

  private func updateBadge(
    _ display: CGDirectDisplayID, overflow: Int, at slot: CGPoint?, screen: NSScreen
  ) {
    if overflow <= 0 || slot == nil {
      badges[display]?.removeFromParent()
      badges[display] = nil
      return
    }
    let pill =
      badges[display]
      ?? {
        let p = SKShapeNode(
          rect: CGRect(x: -26, y: -16, width: 52, height: 32), cornerRadius: 16)
        p.fillColor = Palette.ink.withAlphaComponent(0.9)
        p.strokeColor = Palette.highlight
        p.lineWidth = 2
        p.zPosition = 50
        let l = SKLabelNode()
        l.name = "text"
        l.fontName = "AvenirNext-Bold"
        l.fontSize = 18
        l.fontColor = Palette.highlight
        l.verticalAlignmentMode = .center
        p.addChild(l)
        overlay.overlays[display]?.scene.addChild(p)
        badges[display] = p
        return p
      }()
    (pill.childNode(withName: "text") as? SKLabelNode)?.text = "+\(overflow)"
    pill.position = CGPoint(
      x: slot!.x - screen.frame.minX - 36, y: slot!.y - screen.frame.minY + spriteSize.height / 2)
  }

  private func applyPosition(_ a: Actor) {
    guard let scene = overlay.overlays[a.display]?.scene else { return }
    a.puppet.isHidden = !a.visible
    if a.puppet.scene !== scene {
      a.puppet.removeFromParent()
      scene.addChild(a.puppet)
    }
    let target = scenePosition(a)
    if !a.placedOnce {
      a.placedOnce = true
      a.puppet.position = target
    } else if dragging !== a && !a.isDodging {
      a.puppet.run(
        {
          let m = SKAction.move(to: target, duration: 0.35)
          m.timingMode = .easeInEaseOut
          return m
        }(), withKey: "move")
    }
  }

  // MARK: - Pointer behaviour

  /// Holding Option keeps her still so she can be grabbed and dragged.
  func pointerMoved(_ p: CGPoint, modifiers: NSEvent.ModifierFlags = []) {
    lastPointer = p
    if actors.values.contains(where: { rect($0).insetBy(dx: -300, dy: -300).contains(p) }) {
      noteActivity()
    }
    updateMouseTransparency(p)
    guard dragging == nil else { return }
    let s = settings.settings
    for a in actors.values where a.visible {
      let r = rect(a)
      let inside = r.contains(p)
      var cornered = false
      if s.dodgeEnabled && !reduceMotion && !modifiers.contains(.option) && !a.isDodging
        && Date().timeIntervalSince(a.lastDodge) > 0.35
      {
        let others = actors.values.filter { $0 !== a && $0.visible }.map(rect)
        if let next = DodgePlanner.nextPosition(
          sprite: r, pointer: p, screens: NSScreen.screens.map(\.visibleFrame), shyness: s.shyness,
          otherSprites: others)
        {
          if next != r.origin { dodge(a, to: next) }
        } else {
          cornered = true
        }
      }
      setFade(
        a,
        on: inside && s.hoverFadeEnabled
          && (!s.dodgeEnabled || reduceMotion || cornered || modifiers.contains(.option)))
      trackPetting(a, inside: inside, at: p)
    }
  }

  private func updateMouseTransparency(_ p: CGPoint) {
    let over = actors.values.contains { $0.visible && rect($0).insetBy(dx: -4, dy: -4).contains(p) }
    let capture = dragging != nil || over
    overlay.overlays.values.forEach { $0.panel.ignoresMouseEvents = !capture }
  }

  private func dodge(_ a: Actor, to origin: CGPoint) {
    let now = Date()
    a.origin = origin
    a.userPlaced = true
    a.dodgedAt = now
    a.lastDodge = now
    a.isDodging = true
    if let d = display(at: CGPoint(x: rect(a).midX, y: rect(a).midY)) { a.display = d }
    applyDisplayParent(a)
    a.puppet.hop()
    let move = SKAction.move(to: scenePosition(a), duration: 0.3)
    move.timingMode = .easeOut
    a.puppet.run(
      .sequence([move, .run { [weak a] in a?.isDodging = false }]), withKey: "move")
  }

  private func applyDisplayParent(_ a: Actor) {
    guard let scene = overlay.overlays[a.display]?.scene, a.puppet.scene !== scene else { return }
    a.puppet.removeFromParent()
    a.puppet.position = scenePosition(a)
    scene.addChild(a.puppet)
  }

  private func setFade(_ a: Actor, on: Bool) {
    let target = HoverFade.opacity(pointerInside: on, settings: settings.settings)
    guard abs(a.fadeTarget - target) > 0.001 else { return }
    a.fadeTarget = target
    a.puppet.run(.fadeAlpha(to: target, duration: 0.15), withKey: "fade")
  }

  private func trackPetting(_ a: Actor, inside: Bool, at p: CGPoint) {
    guard inside else {
      a.hoverSince = nil
      a.petted = false
      return
    }
    if a.hoverSince == nil || hypot(p.x - a.hoverPoint.x, p.y - a.hoverPoint.y) > 4 {
      a.hoverSince = Date()
      a.hoverPoint = p
    }
  }

  /// 4 Hz: petting after a still hover, and dodged Claudettes wandering back home.
  private func tick() {
    updateFrameRate()
    let now = Date()
    var needsLayout = false
    for a in actors.values {
      if let since = a.hoverSince, !a.petted, now.timeIntervalSince(since) >= 2 {
        a.petted = true
        a.puppet.happy()
      }
      if let at = a.dodgedAt, now.timeIntervalSince(at) > 20, dragging !== a,
        !rect(a).insetBy(dx: -150, dy: -150).contains(lastPointer)
      {
        a.userPlaced = false
        a.dodgedAt = nil
        needsLayout = true
      }
    }
    if needsLayout { relayout() }
  }

  // MARK: - Dragging

  func mouseDown(_ p: CGPoint) {
    noteActivity()
    guard
      let a = actors.values.filter({ $0.visible && rect($0).contains(p) }).max(by: {
        $0.order < $1.order
      })
    else { return }
    dragging = a
    dragOffset = CGPoint(x: p.x - a.origin.x, y: p.y - a.origin.y)
    physics = DragPhysics()
    physics.begin(at: p)
    lastDragTime = Date()
    lastDragPoint = p
    a.puppet.removeAction(forKey: "move")
    a.puppet.removeAction(forKey: "fade")
    a.puppet.alpha = 1
    a.fadeTarget = 1
    a.isDodging = false
    a.puppet.grab()
  }

  func mouseDragged(_ p: CGPoint) {
    guard let a = dragging else { return }
    let now = Date()
    let dt = now.timeIntervalSince(lastDragTime)
    physics.move(to: p, dt: dt)
    if dt > 0 { a.puppet.carry(velocityX: (p.x - lastDragPoint.x) / CGFloat(dt)) }
    lastDragTime = now
    lastDragPoint = p
    a.origin = CGPoint(x: p.x - dragOffset.x, y: p.y - dragOffset.y)
    if let d = display(at: p), d != a.display {
      a.display = d
      applyDisplayParent(a)
    }
    a.puppet.position = scenePosition(a)
  }

  func mouseUp(_ p: CGPoint) {
    guard let a = dragging else { return }
    dragging = nil
    let v = physics.release()
    a.userPlaced = true
    a.dodgedAt = nil
    let frame = screen(a.display)?.frame ?? screenFrames.first ?? .zero
    if hypot(v.dx, v.dy) > 200 {
      let path = DragPhysics.glide(
        from: a.origin, velocity: v, screen: frame, spriteSize: spriteSize)
      a.origin = path.last ?? a.origin
      let steps = path.map { point -> SKAction in
        let saved = a.origin
        a.origin = point
        let target = scenePosition(a)
        a.origin = saved
        return .move(to: target, duration: 1.0 / 60)
      }
      a.puppet.run(.sequence(steps), withKey: "move")
    } else {
      a.origin = ScreenFit.clamp(a.origin, size: spriteSize, to: screenFrames)
      a.puppet.run(.move(to: scenePosition(a), duration: 0.1), withKey: "move")
    }
    a.puppet.drop()
    updateMouseTransparency(p)
  }
}

extension Stage {
  /// Self-test used by CLAUDETTE_DEBUG_DRAGTEST: drags the first Claudette to `target` through the
  /// same code path real mouse events use, in 30 steps, then lets go.
  func debugDragFirst(to target: CGPoint) {
    guard let a = actors.values.min(by: { $0.order < $1.order }) else { return }
    let start = CGPoint(x: a.origin.x + 100, y: a.origin.y + 60)
    mouseDown(start)
    for i in 1...30 {
      let t = CGFloat(i) / 30
      DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.02) { [self] in
        mouseDragged(
          CGPoint(x: start.x + (target.x - start.x) * t, y: start.y + (target.y - start.y) * t))
      }
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [self] in mouseUp(target) }
  }
}
