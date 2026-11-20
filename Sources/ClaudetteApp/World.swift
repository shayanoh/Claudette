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
    guard let actor = stage.actors[session] else { return }
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
    let size = ItemNode.footprint
    let origin = CGPoint(x: point.x - size.width / 2, y: point.y - size.height / 2)
    let fitted = ScreenFit.clamp(origin, size: size, to: stage.screenFrames)
    let center = CGPoint(x: fitted.x + size.width / 2, y: fitted.y + size.height / 2)
    let display = stage.display(at: center) ?? node.display
    if display != node.display {
      node.removeFromParent()
      node.moveToDisplay(display)
      stage.overlay.overlays[display]?.scene.addChild(node)
    }
    let o = node.originOfDisplay(display)
    node.position = CGPoint(x: center.x - o.x, y: center.y - o.y)
    model.move(node.itemID, to: center, display: display)
    for actor in stage.actors.values where actor.task?.item == node.itemID {
      let intents = brain.plan(
        event: .itemMoved(node.itemID), actor: brainActor(actor), world: model.all,
        screens: stage.screenFrames, rng: &rng)
      run(intents, for: actor)
    }
  }

  // MARK: Executing intents

  private func brainActor(_ a: Actor) -> BrainActor {
    BrainActor(position: stage.feet(of: a), task: a.task)
  }

  func run(_ intents: [Intent], for a: Actor) {
    a.puppet.removeAction(forKey: "brain")
    a.puppet.setWalking(false)
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
      case .face, .pickUp, .putDown, .sit, .fall: break  // later tasks
      }
    }
    steps.append(.run { [weak a] in a?.task = nil })
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
    let size = ItemNode.footprint
    let fitted = ScreenFit.clamp(
      CGPoint(x: point.x - size.width / 2, y: point.y - size.height / 2), size: size,
      to: stage.screenFrames)
    let center = CGPoint(x: fitted.x + size.width / 2, y: fitted.y + size.height / 2)
    let display = stage.display(at: center) ?? node.display
    if display != node.display {
      node.removeFromParent()
      node.moveToDisplay(display)
      stage.overlay.overlays[display]?.scene.addChild(node)
    }
    let o = node.originOfDisplay(display)
    let dest = CGPoint(x: center.x - o.x, y: center.y - o.y)
    model.move(id, to: center, display: display)
    let hop = SKAction.customAction(withDuration: 0.45) { n, t in
      n.zRotation = sin(t / 0.45 * .pi * 2) * 0.35
    }
    let fly = SKAction.move(to: dest, duration: 0.45)
    fly.timingMode = .easeOut
    node.run(.group([fly, hop]), withKey: "toss")
    node.run(.sequence([.wait(forDuration: 0.5), .rotate(toAngle: 0, duration: 0.1)]))
  }
}
