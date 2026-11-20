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
  /// Sub-agents are little actors of their own (0.55x) that roam near this one.
  var subs: [String: Actor] = [:]
  /// Set on a sub-agent's actor.
  weak var parent: Actor?
  var sizeFactor: CGFloat = 1
  var held: ItemNode?
  var thinking = false
  var wandering = false
  var projectName = ""
  var nextRoam = Date.distantPast
  /// Set while she is collecting items for the trash can.
  var cleaning: CleanupRun?
  /// Her session ended and she is tidying up before she goes; a resume of the same session id keeps her.
  var leaving = false
  /// The project folder name without privacy applied (the displayed `projectName` may be dots).
  var rawProjectName = ""
  /// What she carries to the can (up to three, stacked in front of her).
  var armful: [ItemNode] = []
  /// The project name under her feet while the pointer is over her. It lives in the scene, not in
  /// her puppet: the hover fade lowers her alpha and a child would fade with her.
  var nameTag: SKSpriteNode?
  /// The window she is sitting on and the spot on its top edge.
  var perch: (window: WindowFrame, spot: CGPoint)?
  /// What she is heading to or working on (lets a dragged item re-target her).
  var task: (item: ItemID, move: Move)?
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
      Date().timeIntervalSince(lastActivity) < 3 || dragging != nil || draggingOther != nil
      || actors.values.contains {
        $0.puppet.action(forKey: "brain") != nil
          || $0.lastPhase != .idle
            && $0.lastPhase != .sleeping
      }
    let fps = busy ? Stage.activeFPS : Stage.idleFPS
    guard fps != currentFPS else { return }
    currentFPS = fps
    overlay.setFrameRate(fps)
  }

  let overlay: OverlayController
  let settings: SettingsStore
  private(set) var actors: [String: Actor] = [:]
  private var nextOrder = 0
  private var lastPointer = CGPoint.zero
  private var badges: [CGDirectDisplayID: SKShapeNode] = [:]

  /// Extra hover/drag targets (moon, items). Avatars win when both are under the pointer.
  var draggables: [Draggable] = []
  private var hoveredDraggable: Draggable?
  private var draggingOther: Draggable?

  // Dragging
  private var dragging: Actor?
  func isBeingDragged(_ a: Actor) -> Bool { dragging === a }
  private var dragOffset = CGPoint.zero
  private var physics = DragPhysics()
  private var lastDragTime = Date()
  private var lastDragPoint = CGPoint.zero

  private var timer: Timer?
  /// With `ignoresSiblingOrder` SpriteKit sorts every part by its global z, so two Claudettes would
  /// interleave their parts. Each gets a band of its own, wider than a puppet's internal z range
  /// (about -50...30); sub-agents sit 100 above their parent.
  private var topZ: CGFloat = 200
  private var tickCount = 0
  /// Overlay things that must always be above every Claudette (a dragged item, tooltips, confetti).
  static let overlayZ: CGFloat = 100_000
  private(set) lazy var world = World(stage: self)

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

  var scale: CGFloat { CGFloat(settings.settings.scale) }
  private var spriteSize: CGSize {
    CGSize(width: PuppetNode.hitBounds.width * scale, height: PuppetNode.hitBounds.height * scale)
  }

  func screen(_ display: CGDirectDisplayID) -> NSScreen? {
    NSScreen.screens.first { OverlayController.displayID(of: $0) == display }
  }

  /// Where she and items may go: each screen minus the menu bar and the Dock, with room for a
  /// magnified Dock. (Hit-testing which display a point is on still uses the full frames.)
  var screenFrames: [CGRect] { NSScreen.screens.map { walkFrame(for: $0) } }

  func walkFrame(for screen: NSScreen) -> CGRect {
    WalkArea.frame(
      screen: screen.frame, visible: screen.visibleFrame, magnifiedExtra: DockInfo.magnifiedExtra)
  }

  /// Her clickable size: sub-agents are smaller.
  func size(of a: Actor) -> CGSize {
    CGSize(width: spriteSize.width * a.sizeFactor, height: spriteSize.height * a.sizeFactor)
  }

  private func rect(_ a: Actor) -> CGRect { CGRect(origin: a.origin, size: size(of: a)) }

  func display(at point: CGPoint) -> CGDirectDisplayID? {
    for s in NSScreen.screens where s.frame.contains(point) {
      return OverlayController.displayID(of: s)
    }
    return nil
  }

  /// Puppet position (feet centre) in its display's scene coordinates.
  func scenePosition(_ a: Actor) -> CGPoint {
    let f = screen(a.display)?.frame ?? .zero
    let k = scale * a.sizeFactor
    return CGPoint(
      x: a.origin.x - f.minX - PuppetNode.hitBounds.minX * k,
      y: a.origin.y - f.minY - PuppetNode.hitBounds.minY * k)
  }

  // MARK: - Sessions

  func apply(_ changes: [SessionChange], sessions: [String: SessionState] = [:]) {
    if !changes.isEmpty { noteActivity() }
    for change in changes {
      switch change {
      case .started(let id): addActor(id)
      case .ended(let id): endSession(id)
      case .phaseChanged(let id, let phase): phaseChanged(id, phase)
      case .subagentStarted(let id, let agent): addSub(id, agent)
      case .subagentStopped(let id, let agent): removeSub(id, agent)
      case .thinkingChanged(let id, let on): world.thinkingChanged(session: id, on: on)
      case .toolStarted(let id, let tool):
        world.toolStarted(session: id, tool: tool, cwd: sessions[id]?.cwd)
      case .toolFinished(let id, _, let ok): if !ok { shake(id) }
      case .toolResult(let id, let toolID, let result):
        world.toolResult(toolUseID: toolID, result: result)
        if result.interrupted { interrupted(id) }
      case .longShell(_, let toolID): world.longShell(toolUseID: toolID)
      case .skillLoaded(let id, let name):
        actors[id]?.puppet.rune(settings.settings.privacyMode ? "•••" : name)
      case .compacted(let id): actors[id]?.puppet.compact()
      default: break
      }
    }
    for (id, state) in sessions {
      guard let actor = actors[id] else { continue }
      actor.puppet.setContext(state.contextUsedPercentage, privacy: settings.settings.privacyMode)
      dress(actor.puppet, state: state)
      for sub in actor.subs.values { dress(sub.puppet, state: state) }
      actor.rawProjectName = state.cwd.map { ($0 as NSString).lastPathComponent } ?? ""
      actor.projectName =
        settings.settings.privacyMode && !actor.rawProjectName.isEmpty
        ? "•••" : actor.rawProjectName
      for sub in actor.subs.values { sub.projectName = actor.projectName }
    }
    updatePause()
  }

  /// Model outfit and project scarf colour, the same for a session's puppet and its sub-agents.
  private func dress(_ puppet: PuppetNode, state: SessionState) {
    puppet.setOutfit(ModelFamily.from(displayName: state.model))
    puppet.setAccent(hue: Accent.hue(forProject: state.cwd ?? ""))
  }

  /// Rendering stops only when nothing is on screen, including characters still leaving.
  private func updatePause() {
    let leaving = overlay.overlays.values.contains { overlay in
      overlay.scene.children.contains { $0.name?.hasPrefix("puppet-") == true }
    }
    overlay.setPaused(actors.isEmpty && !leaving)
  }

  private func addActor(_ id: String) {
    if let leaving = actors[id], leaving.leaving {
      // The session came back while she was still tidying up before leaving: keep her.
      leaving.leaving = false
      if ProcessInfo.processInfo.environment["CLAUDETTE_DEBUG_CLEANUP"] != nil {
        fputs("cleanup: leaving: session \(id) came back, kept\n", stderr)
      }
      world.cancelCleanup(leaving)
      for sub in leaving.subs.values { world.cancelCleanup(sub) }
      leaving.puppet.idle()
      return
    }
    guard actors[id] == nil, let display = cursorDisplay() ?? overlay.mainDisplayID else { return }
    let a = Actor(sessionID: id, order: nextOrder, display: display)
    nextOrder += 1
    actors[id] = a
    a.puppet.setScale(scale)
    a.puppet.name = "puppet-\(id)"
    a.puppet.reduceMotion = reduceMotion
    bringToFront(a)
    relayout()
    a.puppet.wake()
  }

  /// She tidies up what only her session used, then leaves.
  private func endSession(_ id: String) {
    guard let a = actors[id] else { return }
    a.leaving = true
    world.collectForLeaving(session: id, actor: a) { [weak self, weak a] in
      // Resumed in the meantime (same session id): she stays.
      guard let a, a.leaving else { return }
      if ProcessInfo.processInfo.environment["CLAUDETTE_DEBUG_CLEANUP"] != nil {
        fputs("cleanup: leaving: removed \(id)\n", stderr)
      }
      self?.removeActor(id)
    }
  }

  private func removeActor(_ id: String) {
    guard let a = actors.removeValue(forKey: id) else { return }
    if dragging === a { dragging = nil }
    a.nameTag?.removeFromParent()
    world.release(a)
    for sub in a.subs.values {
      world.release(sub)
      sub.puppet.run(.sequence([.fadeOut(withDuration: 0.3), .removeFromParent()]))
    }
    a.subs.removeAll()
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
    if a.lastPhase == .working, phase == .idle { a.puppet.perform(.celebrate) }  // turn finished
    a.lastPhase = phase
    a.puppet.setStatus(phase)
    world.phaseChanged(session: id, phase: phase)
  }

  private func isError(_ phase: SessionPhase) -> Bool {
    if case .error = phase { return true }
    return false
  }

  /// Esc: startled, then a shrug.
  private func interrupted(_ id: String) {
    guard let p = actors[id]?.puppet else { return }
    p.perform(.startled)
    p.run(
      .sequence([.wait(forDuration: 0.9), .run { [weak p] in p?.perform(.shrug) }]),
      withKey: "interrupted")
  }

  /// A failed tool call makes her flinch sideways.
  private func shake(_ id: String) {
    actors[id]?.puppet.run(
      .sequence([
        .moveBy(x: 4, y: 0, duration: 0.05), .moveBy(x: -8, y: 0, duration: 0.1),
        .moveBy(x: 4, y: 0, duration: 0.05),
      ]), withKey: "shake")
  }

  // MARK: Position in the world

  /// Where her feet are, in global screen coordinates (what the brain plans in).
  func feet(of a: Actor) -> CGPoint {
    let k = scale * a.sizeFactor
    return CGPoint(
      x: a.origin.x - PuppetNode.hitBounds.minX * k, y: a.origin.y - PuppetNode.hitBounds.minY * k)
  }

  /// Puts her feet at `p` right now (the walk calls this every frame).
  func setFeet(_ a: Actor, _ p: CGPoint) {
    guard p.x.isFinite, p.y.isFinite else { return }
    let k = scale * a.sizeFactor
    a.origin = CGPoint(
      x: p.x + PuppetNode.hitBounds.minX * k, y: p.y + PuppetNode.hitBounds.minY * k)
    if let d = display(at: p), d != a.display {
      a.display = d
      applyDisplayParent(a)
    }
    a.puppet.position = scenePosition(a)
    placeNameTag(a)
  }

  /// A sub-agent is a small actor in the same scene, free to roam near its parent.
  private func addSub(_ id: String, _ agent: String) {
    guard let parent = actors[id], parent.subs[agent] == nil,
      let scene = overlay.overlays[parent.display]?.scene
    else { return }
    let sub = Actor(sessionID: id, order: parent.order, display: parent.display)
    sub.sizeFactor = 0.55
    sub.parent = parent
    sub.puppet.setScale(scale * sub.sizeFactor)
    sub.puppet.name = "puppet-\(id)/\(agent)"
    sub.puppet.reduceMotion = reduceMotion
    // Beside her, on the roomier side of the screen, and always fully on screen.
    let feet = feet(of: parent)
    let frame = screen(parent.display)?.frame ?? .zero
    let side: CGFloat = feet.x > frame.midX ? -1 : 1
    let gap = (170 + 70 * CGFloat(parent.subs.count)) * scale
    scene.addChild(sub.puppet)
    parent.subs[agent] = sub
    let k = scale * sub.sizeFactor
    let size = CGSize(
      width: PuppetNode.hitBounds.width * k, height: PuppetNode.hitBounds.height * k)
    let wanted = CGPoint(
      x: feet.x + side * gap + PuppetNode.hitBounds.minX * k,
      y: feet.y + PuppetNode.hitBounds.minY * k)
    let fitted = ScreenFit.clamp(wanted, size: size, to: screenFrames)
    setFeet(
      sub,
      CGPoint(
        x: fitted.x - PuppetNode.hitBounds.minX * k, y: fitted.y - PuppetNode.hitBounds.minY * k))
    sub.puppet.zPosition = parent.puppet.zPosition + 100
    sub.puppet.wake()
    noteActivity()
  }

  private func removeSub(_ id: String, _ agent: String) {
    guard let sub = actors[id]?.subs.removeValue(forKey: agent) else { return }
    world.release(sub)
    sub.puppet.run(.sequence([.fadeOut(withDuration: 0.3), .removeFromParent()]))
  }

  /// Puts her (and her sub-agents) in front of everyone else.
  func bringToFront(_ a: Actor) {
    topZ += 200
    a.puppet.zPosition = topZ
    for sub in a.subs.values { sub.puppet.zPosition = topZ + 100 }
  }

  /// Shows (or hides, with nil) the project name under her feet, fully opaque however faded she is.
  func setNameTag(_ a: Actor, _ text: String?) {
    guard let text, let entry = LabelTexture.entry(text, size: 12),
      let scene = overlay.overlays[a.display]?.scene
    else {
      if let tag = a.nameTag {
        a.nameTag = nil
        tag.run(.sequence([.fadeOut(withDuration: 0.12), .removeFromParent()]))
      }
      return
    }
    if let tag = a.nameTag, tag.userData?["text"] as? String == text, tag.parent === scene {
      placeNameTag(a)
      return
    }
    a.nameTag?.removeFromParent()
    let tag = SKSpriteNode(texture: entry.texture, size: entry.size)
    tag.userData = ["text": text]
    tag.anchorPoint = CGPoint(x: 0.5, y: 1)
    tag.zPosition = Stage.overlayZ - 50  // above every Claudette
    tag.alpha = 0
    scene.addChild(tag)
    tag.run(.fadeIn(withDuration: 0.12))
    a.nameTag = tag
    placeNameTag(a)
  }

  /// Keeps the tag centred under her feet as she moves.
  func placeNameTag(_ a: Actor) {
    guard let tag = a.nameTag else { return }
    let p = scenePosition(a)
    tag.position = CGPoint(x: p.x, y: p.y + LabelTexture.padding - 4)
  }

  /// Keeps her feet at `p` inside a screen (a walk target near the edge must stay reachable).
  func clampFeet(_ p: CGPoint, of a: Actor) -> CGPoint {
    let k = scale * a.sizeFactor
    let size = CGSize(
      width: PuppetNode.hitBounds.width * k, height: PuppetNode.hitBounds.height * k)
    let origin = CGPoint(
      x: p.x + PuppetNode.hitBounds.minX * k, y: p.y + PuppetNode.hitBounds.minY * k)
    let fitted = ScreenFit.clamp(origin, size: size, to: screenFrames)
    return CGPoint(
      x: fitted.x - PuppetNode.hitBounds.minX * k, y: fitted.y - PuppetNode.hitBounds.minY * k)
  }

  /// Every on-screen actor, sub-agents included.
  var allActors: [Actor] { actors.values.flatMap { [$0] + Array($0.subs.values) } }

  private func cursorDisplay() -> CGDirectDisplayID? { display(at: NSEvent.mouseLocation) }

  // MARK: - Layout

  func settingsChanged() {
    for a in allActors {
      a.puppet.setScale(scale * a.sizeFactor)
      a.puppet.reduceMotion = reduceMotion
    }
    world.applyScale()
    world.applyPrivacy()
    for a in actors.values {
      a.projectName =
        settings.settings.privacyMode && !a.rawProjectName.isEmpty ? "•••" : a.rawProjectName
    }
    overlay.focusHidden = settings.settings.focusMode
    relayout()
  }

  /// The app's own setting or the system-wide Reduce Motion preference.
  var reduceMotion: Bool {
    settings.settings.reduceMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
  }

  private func screensChanged() {
    DockInfo.invalidate()  // the Dock may have been resized or moved
    defer { world.relocateItems() }
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
        count: free.count, screen: walkFrame(for: screen), spriteSize: spriteSize)
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
        p.zPosition = Stage.overlayZ - 1
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
    if allActors.contains(where: { rect($0).insetBy(dx: -300, dy: -300).contains(p) }) {
      noteActivity()
    }
    updateDraggableHover(p)
    updateMouseTransparency(p)
    guard dragging == nil else { return }
    let s = settings.settings
    if s.dodgeEnabled && !reduceMotion && !modifiers.contains(.option) {
      world.dodgeItems(from: p)
    }
    for a in allActors where a.visible {
      let r = rect(a)
      let inside = r.contains(p)
      var cornered = false
      if s.dodgeEnabled && a.cleaning == nil && !reduceMotion && !modifiers.contains(.option)
        && !a.isDodging
        && Date().timeIntervalSince(a.lastDodge) > 0.35
      {
        let others = allActors.filter { $0 !== a && $0.visible }.map(rect)
        if let next = DodgePlanner.nextPosition(
          sprite: r, pointer: p, screens: screenFrames, shyness: s.shyness,
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
      setNameTag(a, inside && s.showProjectName && !a.projectName.isEmpty ? a.projectName : nil)
      trackPetting(a, inside: inside, at: p)
    }
  }

  private func updateMouseTransparency(_ p: CGPoint) {
    let over = allActors.contains { $0.visible && rect($0).insetBy(dx: -4, dy: -4).contains(p) }
    let overOther = draggables.contains { $0.hitRect.insetBy(dx: -4, dy: -4).contains(p) }
    let capture = dragging != nil || draggingOther != nil || over || overOther
    overlay.overlays.values.forEach { $0.panel.ignoresMouseEvents = !capture }
  }

  private func draggable(at p: CGPoint) -> Draggable? {
    draggables.last { $0.hitRect.contains(p) }
  }

  private func updateDraggableHover(_ p: CGPoint) {
    let over = draggingOther ?? draggable(at: p)
    guard over !== hoveredDraggable else { return }
    hoveredDraggable?.pointerExited()
    hoveredDraggable = over
    over?.pointerEntered()
  }

  private func dodge(_ a: Actor, to origin: CGPoint) {
    world.interrupt(a)
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
      .sequence([
        move,
        .run { [weak self, weak a] in
          a?.isDodging = false
          if let self, let a {
            self.world.putDownHeld(a)
            self.world.brainEnded(a)  // back to pacing if Claude is still thinking
          }
        },
      ]), withKey: "move")
  }

  func applyDisplayParent(_ a: Actor) {
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
    world.tickSubs()
    for a in allActors { placeNameTag(a) }
    tickCount += 1
    if tickCount % 2 == 0 { world.tickPerch() }  // about 2 Hz
    let now = Date()
    var needsLayout = false
    for a in allActors {
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
      let a = allActors.filter({ $0.visible && rect($0).contains(p) }).max(by: {
        $0.puppet.zPosition < $1.puppet.zPosition
      })
    else {
      if let d = draggable(at: p) {
        draggingOther = d
        d.dragBegan(at: p)
      }
      return
    }
    dragging = a
    world.interrupt(a)  // the walk would otherwise keep overwriting her position
    bringToFront(a)
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
    if let d = draggingOther {
      noteActivity()
      d.dragMoved(to: p)
      return
    }
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
    placeNameTag(a)
  }

  func mouseUp(_ p: CGPoint) {
    if let d = draggingOther {
      draggingOther = nil
      d.dragEnded(at: p)
      updateDraggableHover(p)
      updateMouseTransparency(p)
      return
    }
    guard let a = dragging else { return }
    dragging = nil
    let v = physics.release()
    a.userPlaced = true
    a.dodgedAt = nil
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self, weak a] in
      if let self, let a { self.world.brainEnded(a) }
    }
    let frame = screen(a.display)?.frame ?? screenFrames.first ?? .zero
    if hypot(v.dx, v.dy) > 200 {
      let path = DragPhysics.glide(
        from: a.origin, velocity: v, screen: frame, spriteSize: size(of: a))
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
      a.origin = ScreenFit.clamp(a.origin, size: size(of: a), to: screenFrames)
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
    debugDrag(from: CGPoint(x: a.origin.x + 100, y: a.origin.y + 60), to: target)
  }

  /// CLAUDETTE_DEBUG_MOONDRAG: drags the first visible draggable (the moon) to `target`.
  func debugDragFirstDraggable(to target: CGPoint) {
    guard let d = draggables.first(where: { !$0.hitRect.isNull }) else { return }
    debugDrag(from: CGPoint(x: d.hitRect.midX, y: d.hitRect.midY), to: target)
  }

  private func debugDrag(from start: CGPoint, to target: CGPoint) {
    pointerMoved(start)
    mouseDown(start)
    for i in 1...30 {
      let t = CGFloat(i) / 30
      DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.02) { [self] in
        let p = CGPoint(
          x: start.x + (target.x - start.x) * t, y: start.y + (target.y - start.y) * t)
        pointerMoved(p)
        mouseDragged(p)
      }
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [self] in mouseUp(target) }
  }
}
