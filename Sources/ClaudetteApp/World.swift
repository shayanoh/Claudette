import AppKit
import ClaudetteCore
import SpriteKit

/// Everything lying around on the screen, shared by all Claudettes: owns the `WorldModel`, the item
/// nodes and the execution of what the `Brain` plans (walking to items, working, tossing).
final class World {
  unowned let stage: Stage
  var model = WorldModel()
  var nodes: [ItemID: ItemNode] = [:]
  private let brain = Brain()
  var rng = SystemRandomNumberGenerator()

  init(stage: Stage) { self.stage = stage }

  private var privacy: Bool { stage.settings.settings.privacyMode }
  var itemCount: Int { model.all.count }

  // MARK: Tool events

  func toolStarted(session: String, tool: ToolActivity, cwd: String?) {
    guard let parent = stage.actors[session] else { return }
    // A tool call inside a sub-agent is that little actor's work, not the parent's.
    let actor = tool.agentID.flatMap { parent.subs[$0] } ?? parent
    guard let placed = materialize(for: actor, session: session, tool: tool, cwd: cwd) else {
      return
    }
    let (item, isNew, scene) = placed
    if let run = actor.cleaning {
      // A manual cleanup runs to completion (the new item just lies there afterwards); an automatic
      // tidy-up gives way to real work.
      if run.manual { return }
      cancelCleanup(actor)
    }
    let move = Brain.move(for: scene)
    let intents = brain.plan(
      event: .toolStarted(item, isNew: isNew, move: move), actor: brainActor(actor),
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
    run(intents, for: a, wandering: true)
  }

  /// A brain sequence has finished (checked one turn later, when SpriteKit has dropped the action):
  /// keep pacing while Claude still thinks, or tidy up if the session is waiting and messy.
  func brainEnded(_ a: Actor) {
    guard a.parent == nil, a.cleaning == nil, a.puppet.action(forKey: "brain") == nil,
      stage.actors[a.sessionID] === a
    else { return }
    if a.thinking {
      startWander(a)
    } else {
      phaseChanged(session: a.sessionID, phase: a.lastPhase)
    }
  }

  /// She was grabbed or is stepping aside: whatever she was doing stops (a cleanup she was on is
  /// given up cleanly, dropping what she carries).
  func interrupt(_ a: Actor) {
    cancelCleanup(a)
    a.puppet.removeAction(forKey: "brain")
    a.puppet.setWalking(false)
    a.wandering = false
    a.task = nil
    if a.perch != nil {
      a.perch = nil
      a.puppet.setPose(.stand)
    }
  }

  /// About 4 Hz: sub-agents without a job drift around their parent, or come back inside the leash.
  func tickSubs() {
    let now = Date()
    for parent in stage.actors.values {
      for sub in parent.subs.values
      where sub.puppet.action(forKey: "brain") == nil && sub.cleaning == nil {
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
    let candidates = stage.actors.values.filter {
      $0.cleaning == nil && ($0.perch != nil || $0.wandering)
    }
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
    let vf =
      stage.screen(a.display).map { stage.walkFrame(for: $0) } ?? stage.screenFrames.first ?? .zero
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

  /// Carrying arms while she holds anything, resting arms otherwise.
  func updateArms(_ a: Actor) {
    a.puppet.carrying = a.held != nil || !a.armful.isEmpty
    a.puppet.restoreArms()
  }

  /// She takes the item into her hands (it rides along if she dodges) until she tosses or sets it down.
  private func pickUp(_ a: Actor, _ id: ItemID) {
    guard a.held == nil, let node = nodes[id] else { return }
    detachFromHolders(node, except: a)
    node.removeAllActions()
    node.pointerExited()
    stage.draggables.removeAll { $0 === node }
    node.removeFromParent()
    node.setHeld(true)
    node.position = CGPoint(x: -88, y: 112)
    node.zPosition = 6
    a.puppet.addChild(node)
    a.held = node
    updateArms(a)
  }

  /// An item node is in at most one pair of hands: take it from anybody else holding or carrying it.
  func detachFromHolders(_ node: ItemNode, except keep: Actor? = nil) {
    for a in stage.allActors where a !== keep {
      var changed = false
      if a.held === node {
        a.held = nil
        changed = true
      }
      if a.armful.contains(where: { $0 === node }) {
        a.armful.removeAll { $0 === node }
        changed = true
      }
      if changed { updateArms(a) }
    }
  }

  /// Puts what she holds on the screen at `point` (global), or beside her feet.
  func putDownHeld(_ a: Actor, at point: CGPoint? = nil) {
    guard let node = a.held else { return }
    a.held = nil
    updateArms(a)
    // Thrown away or evicted while she held it: nothing to put down.
    guard nodes[node.itemID] === node else {
      node.removeFromParent()
      return
    }
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
    cancelCleanup(a)
    putDownHeld(a)
    a.puppet.removeAction(forKey: "brain")
  }

  /// Keeps `center` fully on a screen and works out the display and scene position.
  func settle(_ node: ItemNode, at center: CGPoint) -> (
    center: CGPoint, scenePosition: CGPoint
  ) {
    let size = node.extent
    let fitted = ScreenFit.clamp(
      CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2), size: size,
      to: stage.screenFrames)
    let c = CGPoint(x: fitted.x + size.width / 2, y: fitted.y + size.height / 2)
    node.moveToDisplay(stage.display(at: c) ?? node.display)
    let o = node.originOfDisplay(node.display)
    return (c, CGPoint(x: c.x - o.x, y: c.y - o.y))
  }

  /// Records the touch in the model and, for something new, puts an item on the screen by `actor`.
  private func materialize(for actor: Actor, session: String, tool: ToolActivity, cwd: String?)
    -> (item: Item, isNew: Bool, scene: ToolScene)?
  {
    let scene = SceneMapper.scene(for: tool, now: Date())
    model.hardCap = stage.settings.settings.itemCap
    guard
      let touched = model.touch(for: session, tool: tool, scene: scene, cwd: cwd, now: Date())
    else { return nil }
    touched.evicted.forEach { remove($0) }
    var item = touched.item
    if item.position == nil || nodes[item.id] == nil {
      let feet = stage.feet(of: actor)
      let side: CGFloat = Bool.random(using: &rng) ? 1 : -1
      let spot = Scatter.spot(
        near: CGPoint(x: feet.x + side * 150 * stage.scale, y: feet.y + 30),
        existing: model.all.filter { $0.id != item.id }.compactMap(\.position),
        itemSize: ItemNode.spacing, screens: stage.screenFrames, seed: rng.next())
      let display = stage.display(at: spot) ?? actor.display
      model.move(item.id, to: spot, display: display)
      item = model.item(item.id) ?? item
      makeNode(item, scene: scene, at: spot, display: display)
    } else {
      nodes[item.id]?.pop()
    }
    return (item, touched.isNew, scene)
  }

  /// CLAUDETTE_DEBUG_CLUTTER: leaves `count` files and terminals around the first Claudette.
  func debugClutter(_ count: Int) {
    guard let actor = stage.actors.values.min(by: { $0.order < $1.order }) else { return }
    for i in 0..<max(0, min(count, 500)) {
      let isShell = i % 5 == 0
      let tool = ToolActivity(
        toolUseID: "debug-clutter-\(i)", toolName: isShell ? "Bash" : "Read", mcpServer: nil,
        input: .object(
          isShell
            ? ["command": .string("make build-\(i)")]
            : ["file_path": .string("/debug/src/file\(i).swift")]),
        startedAt: Date(), isBackground: false)
      _ = materialize(for: actor, session: actor.sessionID, tool: tool, cwd: "/debug")
    }
    stage.noteActivity()
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

  // MARK: Nodes

  private func makeNode(
    _ item: Item, scene: ToolScene, at spot: CGPoint, display: CGDirectDisplayID
  ) {
    let node = ItemNode(
      id: item.id, scene: scene, display: display, privacy: privacy, uiScale: stage.scale)
    node.originOfDisplay = { [weak stage] d in stage?.screen(d)?.frame.origin ?? .zero }
    node.onDropped = { [weak self] n, p in self?.dropped(n, at: p) }
    node.onClicked = { [weak self] n in self?.itemClicked(n) }
    node.tooltipLines = { [weak self] in self?.tooltip(for: item.id) ?? [] }
    if let command = item.terminal?.command { node.showCommand(command) }
    let origin = node.originOfDisplay(display)
    node.position = CGPoint(x: spot.x - origin.x, y: spot.y - origin.y)
    stage.overlay.overlays[display]?.scene.addChild(node)
    stage.draggables.append(node)
    nodes[item.id] = node
    node.popIn()
  }

  func remove(_ id: ItemID) {
    model.remove([id])
    guard let node = nodes.removeValue(forKey: id) else { return }
    detachFromHolders(node)
    stage.draggables.removeAll { $0 === node }
    node.pointerExited()
    node.run(.sequence([.fadeOut(withDuration: 0.4), .removeFromParent()]))
  }

  // MARK: Items keep away from the pointer

  private var itemDodgedAt: [ItemID: Date] = [:]

  /// With dodging on (and Option not held) things on the screen step away from the pointer, so
  /// they never get in the way of what is behind them. Option lets you hover and click them.
  func dodgeItems(from pointer: CGPoint) {
    let now = Date()
    let busy = Set(stage.allActors.compactMap { $0.task?.item })
    for (id, node) in nodes {
      guard node.parent is SKScene, !node.isBeingDragged, !busy.contains(id) else { continue }
      if let t = itemDodgedAt[id], now.timeIntervalSince(t) < 0.45 { continue }
      let c = node.globalCenter
      guard hypot(c.x - pointer.x, c.y - pointer.y) < 62 * node.xScale else { continue }
      itemDodgedAt[id] = now
      flee(node, from: pointer)
    }
    if itemDodgedAt.count > 400 { itemDodgedAt = itemDodgedAt.filter { nodes[$0.key] != nil } }
  }

  private func flee(_ node: ItemNode, from pointer: CGPoint) {
    let c = node.globalCenter
    var ang = atan2(c.y - pointer.y, c.x - pointer.x)
    if hypot(c.x - pointer.x, c.y - pointer.y) < 1 {
      ang = Double.random(in: 0..<(2 * .pi), using: &rng)
    }
    let others = model.all.filter { $0.id != node.itemID }.compactMap(\.position)
    let step = 150 * stage.scale
    var best: (spot: CGPoint, room: CGFloat)?
    for off in [0.0, 35, -35, 70, -70, 110, -110] {
      let a = ang + off * .pi / 180
      let cand = CGPoint(x: c.x + step * cos(a), y: c.y + step * sin(a))
      let size = node.extent
      let fitted = ScreenFit.clamp(
        CGPoint(x: cand.x - size.width / 2, y: cand.y - size.height / 2), size: size,
        to: stage.screenFrames)
      let spot = CGPoint(x: fitted.x + size.width / 2, y: fitted.y + size.height / 2)
      guard hypot(spot.x - c.x, spot.y - c.y) > 40 else { continue }  // cornered that way
      let room = others.map { hypot(spot.x - $0.x, spot.y - $0.y) }.min() ?? .infinity
      if room >= 70 {
        best = (spot, room)
        break
      }
      if room > (best?.room ?? -1) { best = (spot, room) }
    }
    guard let target = best?.spot else { return }
    let settled = settle(node, at: target)
    let scene = stage.overlay.overlays[node.display]?.scene
    if node.parent !== scene {
      node.removeFromParent()
      scene?.addChild(node)
    }
    model.move(node.itemID, to: settled.center, display: node.display)
    let go = SKAction.move(to: settled.scenePosition, duration: 0.22)
    go.timingMode = .easeOut
    node.run(
      .group([
        go,
        .sequence([.rotate(toAngle: 0.25, duration: 0.11), .rotate(toAngle: 0, duration: 0.11)]),
      ]), withKey: "dodge")
    stage.noteActivity()
  }

  /// Privacy mode changed: names on items already lying around are redrawn.
  func applyPrivacy() {
    for node in nodes.values { node.setPrivacy(privacy) }
  }

  /// A display came or went: every item is pulled back fully onto a screen that exists, and into
  /// that screen's scene (a removed display's scene is no longer shown).
  func relocateItems() {
    for (id, node) in nodes where node.parent is SKScene || node.parent == nil {
      guard let center = model.item(id)?.position else { continue }
      let settled = settle(node, at: center)
      let target = stage.overlay.overlays[node.display]?.scene
      if node.parent !== target {
        node.removeFromParent()
        target?.addChild(node)
      }
      node.position = settled.scenePosition
      model.move(id, to: settled.center, display: node.display)
    }
  }

  func applyScale() {
    for node in nodes.values { node.setUIScale(stage.scale) }
  }

  /// A few short lines on hover: the whole thing when it is short, a wrapped summary otherwise.
  private func tooltip(for id: ItemID) -> [String] {
    guard let item = model.item(id) else { return [] }
    return privacy ? ["•••"] : ItemDetails.hover(item)
  }

  /// A click: a file is revealed in Finder; anything else opens a window with everything we know.
  private func itemClicked(_ node: ItemNode) {
    guard !privacy, let item = model.item(node.itemID) else { return }
    if item.kind == .file {
      let path = String(node.itemID.raw.dropFirst("file:".count))
      if FileManager.default.fileExists(atPath: path) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        return
      }
    }
    ItemDetailWindows.shared.show(item)
  }

  /// The mouse dropped an item: keep it fully on a screen, on whichever display it landed, and send
  /// anyone heading for it to the new spot.
  private func dropped(_ node: ItemNode, at point: CGPoint) {
    let settled = settle(node, at: point)
    let target = stage.overlay.overlays[node.display]?.scene
    if node.parent !== target {
      node.removeFromParent()
      target?.addChild(node)
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

  func brainActor(_ a: Actor) -> BrainActor {
    let sub = a.parent
    return BrainActor(
      position: stage.feet(of: a), holding: a.held?.itemID, isSubagent: sub != nil,
      anchor: sub.map { stage.feet(of: $0) }, leash: sub == nil ? 0 : leash, task: a.task,
      others: othersFeet(of: a), gap: personalSpace(a))
  }

  /// How much room she keeps around herself (sub-agents are smaller).
  func personalSpace(_ a: Actor) -> CGFloat { (a.sizeFactor < 1 ? 110 : 140) * stage.scale }

  func othersFeet(of a: Actor) -> [CGPoint] {
    stage.allActors.filter { $0 !== a && $0.visible }.map { stage.feet(of: $0) }
  }

  func run(_ intents: [Intent], for a: Actor, wandering: Bool = false) {
    cancelCleanup(a)  // nothing may end a cleanup without its bookkeeping
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
    var cursor = stage.feet(of: a)
    for intent in intents {
      switch intent {
      case .walk(let p):
        a.userPlaced = true
        steps.append(walk(a, from: cursor, to: p))
        cursor = p
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
    steps.append(
      .run { [weak self, weak a] in
        DispatchQueue.main.async { if let self, let a { self.brainEnded(a) } }
      })
    a.puppet.run(.sequence(steps), withKey: "brain")
    stage.noteActivity()
  }

  /// Remembers where she really was when a walk began (an earlier nudge may have moved her).
  private final class WalkStart { var point: CGPoint? }

  /// A walk to `target`. `start` (where the plan expects her to be) only sets how long it takes; the
  /// path begins wherever she is when the walk starts, and keeps clear of the other Claudettes.
  func walk(_ a: Actor, from start: CGPoint, to target: CGPoint) -> SKAction {
    let dist = hypot(target.x - start.x, target.y - start.y)
    guard dist > 1 else { return .wait(forDuration: 0) }
    let duration = stage.reduceMotion ? 0.05 : max(0.2, Double(dist) / (140 * Double(stage.scale)))
    let begin = WalkStart()
    let move = SKAction.customAction(withDuration: duration) { [weak self, weak a] _, elapsed in
      guard let self, let a else { return }
      let from = begin.point ?? self.stage.feet(of: a)
      begin.point = from
      let t = min(1, CGFloat(elapsed) / CGFloat(duration))
      let k = t * t * (3 - 2 * t)  // ease in and out
      let p = CGPoint(x: from.x + (target.x - from.x) * k, y: from.y + (target.y - from.y) * k)
      self.stage.setFeet(
        a, Separation.push(p, awayFrom: self.othersFeet(of: a), minGap: self.personalSpace(a)))
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
      updateArms(holder)
      holder.puppet.tossGesture()
      node.removeFromParent()
      node.setHeld(false)
      node.zPosition = 0
      node.position = from
      scene.addChild(node)
      stage.draggables.append(node)
    }
    let settled = settle(node, at: point)
    let target = stage.overlay.overlays[node.display]?.scene
    if node.parent !== target {
      node.removeFromParent()
      target?.addChild(node)
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
