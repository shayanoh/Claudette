import AppKit
import ClaudetteCore
import SpriteKit

/// Everything lying around on the screen, shared by all Claudettes: owns the `WorldModel`, the item
/// nodes and the execution of what the `Brain` plans (walking to items, working, tossing).
final class World {
  private unowned let stage: Stage
  private(set) var model = WorldModel()
  private var nodes: [ItemID: ItemNode] = [:]
  private let brain = Brain()
  private var rng = SystemRandomNumberGenerator()

  init(stage: Stage) { self.stage = stage }

  private var privacy: Bool { stage.settings.settings.privacyMode }
  var itemCount: Int { model.all.count }

  // MARK: Tool events

  func toolStarted(session: String, tool: ToolActivity, cwd: String?) {
    guard let parent = stage.actors[session] else { return }
    // A tool call inside a sub-agent is that little actor's work, not the parent's.
    let actor = tool.agentID.flatMap { parent.subs[$0] } ?? parent
    let scene = SceneMapper.scene(for: tool, now: Date())
    guard
      let touched = model.touch(for: session, tool: tool, scene: scene, cwd: cwd, now: Date())
    else { return }
    touched.evicted.forEach { remove($0) }
    var item = touched.item
    if item.position == nil || nodes[item.id] == nil {
      let feet = stage.feet(of: actor)
      let side: CGFloat = Bool.random(using: &rng) ? 1 : -1
      let spot = Scatter.spot(
        near: CGPoint(x: feet.x + side * 150 * stage.scale, y: feet.y + 30),
        existing: model.all.filter { $0.id != item.id }.compactMap(\.position),
        itemSize: ItemNode.footprint, screens: stage.screenFrames, seed: rng.next())
      let display = stage.display(at: spot) ?? actor.display
      model.move(item.id, to: spot, display: display)
      item = model.item(item.id) ?? item
      makeNode(item, scene: scene, at: spot, display: display)
    } else {
      nodes[item.id]?.pop()
    }
    let move = Brain.move(for: scene)
    let intents = brain.plan(
      event: .toolStarted(item, isNew: touched.isNew, move: move), actor: brainActor(actor),
      world: model.all, screens: stage.screenFrames, rng: &rng)
    actor.task = (item.id, move)
    run(intents, for: actor)
  }

  // MARK: Thinking, sub-agents

  func thinkingChanged(session: String, on: Bool) {
    guard let a = stage.actors[session] else { return }
    a.thinking = on
    a.puppet.think(on)
    if on {
      startWander(a)
    } else if a.wandering {
      a.wandering = false
      a.puppet.removeAction(forKey: "brain")
      a.puppet.setWalking(false)
    }
  }

  /// She paces about while Claude thinks: one batch of legs, then another while it lasts.
  private func startWander(_ a: Actor) {
    guard a.thinking, a.perch == nil, !stage.reduceMotion, !stage.isBeingDragged(a), !a.isDodging,
      a.puppet.action(forKey: "brain") == nil
    else { return }
    let intents = brain.plan(
      event: .thinkingChanged(true), actor: brainActor(a), world: model.all,
      screens: stage.screenFrames, rng: &rng)
    run(intents, for: a, wandering: true) { [weak self, weak a] in
      guard let self, let a else { return }
      a.wandering = false
      self.startWander(a)
    }
  }

  /// About 4 Hz: sub-agents without a job drift around their parent, or come back inside the leash.
  func tickSubs() {
    let now = Date()
    for parent in stage.actors.values {
      for sub in parent.subs.values where sub.puppet.action(forKey: "brain") == nil {
        guard now >= sub.nextRoam else { continue }
        sub.nextRoam = now.addingTimeInterval(.random(in: 2.5...6, using: &rng))
        let outside =
          hypot(
            stage.feet(of: sub).x - stage.feet(of: parent).x,
            stage.feet(of: sub).y - stage.feet(of: parent).y) > leash
        let event: BrainEvent = outside || Bool.random(using: &rng) ? .idle : .thinkingChanged(true)
        var intents = brain.plan(
          event: event, actor: brainActor(sub), world: model.all, screens: stage.screenFrames,
          rng: &rng)
        intents.removeAll { if case .play(.think) = $0 { return true } else { return false } }
        run(intents, for: sub)
      }
    }
  }

  /// How far a sub-agent strays from its parent.
  private var leash: CGFloat { 260 * stage.scale }

  // MARK: Perching

  private var windows: [WindowFrame] = []

  /// About 2 Hz, only while somebody is wandering or sitting: a wandering Claudette may hop onto a
  /// window's top edge; one that is sitting there gets the shock of her life if the window moves.
  func tickPerch() {
    guard stage.settings.settings.perchEnabled, !stage.reduceMotion else { return }
    let candidates = stage.actors.values.filter { $0.perch != nil || $0.wandering }
    guard !candidates.isEmpty else { return }
    windows = WindowTracker.poll()
    for a in candidates {
      if let perch = a.perch {
        if PerchPlanner.moved(perched: perch.window, spot: perch.spot, now: windows, tolerance: 6) {
          run([.fall], for: a)
        }
      } else if !a.isDodging, !stage.isBeingDragged(a), Int.random(in: 0..<4, using: &rng) == 0,
        let c = PerchPlanner.candidate(
          near: stage.feet(of: a), windows: windows, screens: stage.screenFrames,
          ownPID: ProcessInfo.processInfo.processIdentifier,
          minSize: CGSize(width: 200, height: 120), reach: 220 * stage.scale)
      {
        run([.walk(to: c.spot), .sit(onWindow: c.window)], for: a)
      }
    }
  }

  private func sit(_ a: Actor, onWindow number: Int) {
    guard let w = windows.first(where: { $0.number == number }) else { return }
    a.perch = (w, stage.feet(of: a))
    a.puppet.setPose(.sit)
  }

  /// Startled, then straight down to the floor row.
  private func fall(_ a: Actor) -> SKAction {
    let start = stage.feet(of: a)
    let k = stage.scale * a.sizeFactor
    let vf = stage.screen(a.display)?.visibleFrame ?? stage.screenFrames.first ?? .zero
    let groundY = vf.minY + 24 + 6 * k  // the row the layout stands her on
    let drop = max(0, start.y - groundY)
    let duration = max(0.15, sqrt(Double(drop) / 1800))  // free fall
    let fall = SKAction.customAction(withDuration: duration) { [weak self, weak a] _, t in
      guard let self, let a else { return }
      let u = CGFloat(t) / CGFloat(duration)
      self.stage.setFeet(a, CGPoint(x: start.x, y: start.y - drop * u * u))
    }
    return .sequence([
      .run { [weak a] in
        a?.puppet.setPose(.stand)
        a?.puppet.perform(.startled)
      },
      .wait(forDuration: 0.22), fall,
      .run { [weak a] in a?.puppet.drop() },
    ])
  }

  // MARK: Carrying

  /// She takes the item into her hands (it rides along if she dodges) until she tosses or sets it down.
  private func pickUp(_ a: Actor, _ id: ItemID) {
    guard a.held == nil, let node = nodes[id] else { return }
    node.removeAllActions()
    node.pointerExited()
    stage.draggables.removeAll { $0 === node }
    node.removeFromParent()
    node.setHeld(true)
    node.position = CGPoint(x: -88, y: 112)
    node.zPosition = 6
    a.puppet.addChild(node)
    a.held = node
  }

  /// Puts what she holds on the screen at `point` (global), or beside her feet.
  func putDownHeld(_ a: Actor, at point: CGPoint? = nil) {
    guard let node = a.held else { return }
    a.held = nil
    let feet = stage.feet(of: a)
    let spot = point ?? CGPoint(x: feet.x - 130 * stage.scale, y: feet.y + 20)
    node.removeFromParent()
    node.setHeld(false)
    node.zPosition = 0
    let settled = settle(node, at: spot)
    node.position = settled.scenePosition
    stage.overlay.overlays[node.display]?.scene.addChild(node)
    stage.draggables.append(node)
    model.move(node.itemID, to: settled.center, display: node.display)
    node.pop()
  }

  /// A leaving actor sets down what she holds (nothing may be orphaned inside a removed puppet).
  func release(_ a: Actor) {
    putDownHeld(a)
    a.puppet.removeAction(forKey: "brain")
  }

  /// Keeps `center` fully on a screen and works out the display and scene position.
  private func settle(_ node: ItemNode, at center: CGPoint) -> (
    center: CGPoint, scenePosition: CGPoint
  ) {
    let size = ItemNode.footprint
    let fitted = ScreenFit.clamp(
      CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2), size: size,
      to: stage.screenFrames)
    let c = CGPoint(x: fitted.x + size.width / 2, y: fitted.y + size.height / 2)
    node.moveToDisplay(stage.display(at: c) ?? node.display)
    let o = node.originOfDisplay(node.display)
    return (c, CGPoint(x: c.x - o.x, y: c.y - o.y))
  }

  func toolResult(toolUseID: String, result: ToolResult) {
    let id = ItemID.tool(useID: toolUseID)
    model.finish(toolUseID: toolUseID, result: result)
    guard let item = model.item(id), let command = item.terminal?.command else { return }
    nodes[id]?.restyle(
      .shell(long: false, background: false), caption: result.success ? "done" : "failed",
      command: command)
  }

  func longShell(toolUseID: String) {
    let id = ItemID.tool(useID: toolUseID)
    guard let command = model.item(id)?.terminal?.command else { return }
    nodes[id]?.restyle(.shell(long: true, background: false), command: command)
  }

  /// Interim until cleanup exists (phase 3): a finished session's sole-owner items fade away.
  func sessionEnded(_ session: String) {
    let ownerless = model.releaseSession(session)
    ownerless.forEach { remove($0) }
  }

  // MARK: Nodes

  private func makeNode(
    _ item: Item, scene: ToolScene, at spot: CGPoint, display: CGDirectDisplayID
  ) {
    let node = ItemNode(
      id: item.id, scene: scene, display: display, privacy: privacy, uiScale: stage.scale)
    node.originOfDisplay = { [weak stage] d in stage?.screen(d)?.frame.origin ?? .zero }
    node.onDropped = { [weak self] n, p in self?.dropped(n, at: p) }
    node.tooltipLines = { [weak self] in self?.tooltip(for: item.id) ?? [] }
    if let command = item.terminal?.command { node.showCommand(command) }
    let origin = node.originOfDisplay(display)
    node.position = CGPoint(x: spot.x - origin.x, y: spot.y - origin.y)
    stage.overlay.overlays[display]?.scene.addChild(node)
    stage.draggables.append(node)
    nodes[item.id] = node
    node.popIn()
  }

  private func remove(_ id: ItemID) {
    model.remove([id])
    guard let node = nodes.removeValue(forKey: id) else { return }
    stage.draggables.removeAll { $0 === node }
    node.pointerExited()
    node.run(.sequence([.fadeOut(withDuration: 0.4), .removeFromParent()]))
  }

  func applyScale() {
    for node in nodes.values { node.setUIScale(stage.scale) }
  }

  private func tooltip(for id: ItemID) -> [String] {
    guard let item = model.item(id) else { return [] }
    if privacy { return ["•••"] }
    switch item.kind {
    case .file: return [String(id.raw.dropFirst("file:".count))]
    case .terminal:
      guard let t = item.terminal else { return [] }
      var lines = [t.command.split(separator: "\n").first.map(String.init) ?? t.command]
      switch t.state {
      case .running: lines.append("running…")
      case .done, .failed:
        let secs = t.result?.durationMs.map { String(format: " · %.1f s", Double($0) / 1000) } ?? ""
        lines.append((t.state == .done ? "done" : "failed") + secs)
        if let tail = t.result?.summary?.split(separator: "\n").last { lines.append(String(tail)) }
      }
      return lines
    case .tool: return []
    }
  }

  /// The mouse dropped an item: keep it fully on a screen, on whichever display it landed, and send
  /// anyone heading for it to the new spot.
  private func dropped(_ node: ItemNode, at point: CGPoint) {
    let old = node.display
    let settled = settle(node, at: point)
    if node.display != old {
      node.removeFromParent()
      stage.overlay.overlays[node.display]?.scene.addChild(node)
    }
    node.position = settled.scenePosition
    model.move(node.itemID, to: settled.center, display: node.display)
    for actor in stage.allActors where actor.task?.item == node.itemID {
      let intents = brain.plan(
        event: .itemMoved(node.itemID), actor: brainActor(actor), world: model.all,
        screens: stage.screenFrames, rng: &rng)
      run(intents, for: actor)
    }
  }

  // MARK: Executing intents

  private func brainActor(_ a: Actor) -> BrainActor {
    let sub = a.parent
    return BrainActor(
      position: stage.feet(of: a), holding: a.held?.itemID, isSubagent: sub != nil,
      anchor: sub.map { stage.feet(of: $0) }, leash: sub == nil ? 0 : leash, task: a.task)
  }

  func run(
    _ intents: [Intent], for a: Actor, wandering: Bool = false, then: (() -> Void)? = nil
  ) {
    a.puppet.removeAction(forKey: "brain")
    a.puppet.setWalking(false)
    a.wandering = wandering
    // Any new activity means she hops down (a sit step puts her back up).
    if a.perch != nil,
      !intents.contains(where: { if case .sit = $0 { return true } else { return false } })
    {
      a.perch = nil
      a.puppet.setPose(.stand)
    }
    guard !intents.isEmpty else {
      a.task = nil
      return
    }
    var steps: [SKAction] = []
    for intent in intents {
      switch intent {
      case .walk(let p):
        a.userPlaced = true
        steps.append(walk(a, to: p))
      case .play(let move):
        steps.append(.run { [weak a] in a?.puppet.perform(move) })
        steps.append(.wait(forDuration: 1.1))
      case .toss(let id, let to):
        steps.append(.run { [weak self] in self?.toss(id, to: to) })
        steps.append(.wait(forDuration: 0.5))
      case .wait(let t): steps.append(.wait(forDuration: t))
      case .pickUp(let id):
        steps.append(.run { [weak self, weak a] in if let a { self?.pickUp(a, id) } })
      case .putDown(let p):
        steps.append(.run { [weak self, weak a] in if let a { self?.putDownHeld(a, at: p) } })
      case .sit(let n):
        steps.append(.run { [weak self, weak a] in if let a { self?.sit(a, onWindow: n) } })
      case .fall: steps.append(fall(a))
      case .face: break
      }
    }
    steps.append(.run { [weak a] in a?.task = nil })
    if let then { steps.append(.run(then)) }
    a.puppet.run(.sequence(steps), withKey: "brain")
    stage.noteActivity()
  }

  private func walk(_ a: Actor, to target: CGPoint) -> SKAction {
    let start = stage.feet(of: a)
    let dist = hypot(target.x - start.x, target.y - start.y)
    guard dist > 1 else { return .wait(forDuration: 0) }
    let duration = stage.reduceMotion ? 0.05 : max(0.2, Double(dist) / (140 * Double(stage.scale)))
    let move = SKAction.customAction(withDuration: duration) { [weak self, weak a] _, elapsed in
      guard let self, let a else { return }
      let t = min(1, CGFloat(elapsed) / CGFloat(duration))
      let k = t * t * (3 - 2 * t)  // ease in and out
      self.stage.setFeet(
        a, CGPoint(x: start.x + (target.x - start.x) * k, y: start.y + (target.y - start.y) * k))
    }
    return .sequence([
      .run { [weak a] in a?.puppet.setWalking(true) }, move,
      .run { [weak a] in a?.puppet.setWalking(false) },
    ])
  }

  private func toss(_ id: ItemID, to point: CGPoint) {
    guard let node = nodes[id] else { return }
    // Thrown from her hands: it leaves from where she holds it.
    if let holder = stage.allActors.first(where: { $0.held === node }),
      let scene = stage.overlay.overlays[holder.display]?.scene, let parent = node.parent
    {
      let from = parent.convert(node.position, to: scene)
      holder.held = nil
      node.removeFromParent()
      node.setHeld(false)
      node.zPosition = 0
      node.position = from
      scene.addChild(node)
      stage.draggables.append(node)
    }
    let old = node.display
    let settled = settle(node, at: point)
    if node.display != old {
      node.removeFromParent()
      stage.overlay.overlays[node.display]?.scene.addChild(node)
    }
    model.move(id, to: settled.center, display: node.display)
    let hop = SKAction.customAction(withDuration: 0.45) { n, t in
      n.zRotation = sin(t / 0.45 * .pi * 2) * 0.35
    }
    let fly = SKAction.move(to: settled.scenePosition, duration: 0.45)
    fly.timingMode = .easeOut
    node.run(.group([fly, hop]), withKey: "toss")
    node.run(.sequence([.wait(forDuration: 0.5), .rotate(toAngle: 0, duration: 0.1)]))
  }
}
