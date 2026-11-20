import AppKit
import ClaudetteCore
import SpriteKit

/// One cleanup scene: the can and how many Claudettes are still collecting.
final class CleanupRun {
  var remaining = 0
  let can: TrashCanNode
  let canBase: CGPoint
  let display: CGDirectDisplayID
  let edgeX: CGFloat
  let manual: Bool
  var completion: (() -> Void)?

  init(
    can: TrashCanNode, canBase: CGPoint, display: CGDirectDisplayID, edgeX: CGFloat, manual: Bool
  ) {
    self.can = can
    self.canBase = canBase
    self.display = display
    self.edgeX = edgeX
    self.manual = manual
  }
}

/// A point `distance` from `target` on the side `from` is on.
private func near(_ target: CGPoint, from: CGPoint, distance d: CGFloat) -> CGPoint {
  let dx = from.x - target.x
  let dy = from.y - target.y
  let len = hypot(dx, dy)
  let (ux, uy) = len > 1 ? (dx / len, dy / len) : (-1, 0)
  return CGPoint(x: target.x + ux * d, y: target.y + uy * d)
}

private let traceCleanup = ProcessInfo.processInfo.environment["CLAUDETTE_DEBUG_CLEANUP"] != nil
private func trace(_ s: @autoclosure () -> String) {
  if traceCleanup { fputs("cleanup: \(s())\n", stderr) }
}

extension World {
  // MARK: Triggers

  /// The menubar "Clean up": everybody collects everything.
  func cleanUpAll() {
    let started = Date()
    let before = model.all.count
    startCleanup(
      ids: model.all.map(\.id), crew: stage.allActors.filter { $0.cleaning == nil }, manual: true
    ) { [weak self] in
      guard ProcessInfo.processInfo.environment["CLAUDETTE_DEBUG_CLEANUP"] != nil else { return }
      let left = self?.model.all.count ?? -1
      fputs(
        String(
          format: "cleanup: %d items, finished after %.1f s, %d left\n", before,
          Date().timeIntervalSince(started), left), stderr)
    }
  }

  /// Waiting for the user is a good moment to tidy a little.
  func phaseChanged(session: String, phase: SessionPhase) {
    guard let a = stage.actors[session], a.cleaning == nil,
      a.puppet.action(forKey: "brain") == nil
    else { return }
    let s = stage.settings.settings
    let ids = ClutterPolicy.autoTidy(
      session: session, owned: model.items(ownedBy: session), phase: phase,
      softLimit: s.clutterSoftLimit, enabled: s.autoCleanup)
    guard !ids.isEmpty else { return }
    startCleanup(ids: ids, crew: [a], manual: false) {}
  }

  /// A leaving session's Claudette (and her sub-agents) collects what nobody else uses first.
  func collectForLeaving(session: String, actor a: Actor, completion: @escaping () -> Void) {
    cancelCleanup(a)
    let ids = ClutterPolicy.sessionEnd(session: session, items: model.all)
    _ = model.releaseSession(session)  // shared items just lose this owner
    let crew = [a] + Array(a.subs.values)
    for sub in a.subs.values { cancelCleanup(sub) }
    startCleanup(ids: ids, crew: crew, manual: false, completion: completion)
  }

  // MARK: The scene

  func startCleanup(ids: [ItemID], crew: [Actor], manual: Bool, completion: @escaping () -> Void) {
    let items = ids.compactMap { model.item($0) }.filter { nodes[$0.id] != nil }
    let crew = crew.filter { $0.cleaning == nil }
    trace("start: \(items.count) items, crew \(crew.count)")
    guard !items.isEmpty else {
      completion()
      return
    }
    guard !crew.isEmpty else {  // nobody to do it: they just disappear
      items.forEach { remove($0.id) }
      completion()
      return
    }
    for a in crew {
      putDownHeld(a)
      a.puppet.removeAction(forKey: "brain")
      a.puppet.setWalking(false)
      a.task = nil
      a.wandering = false
      if a.perch != nil {  // she hops off her window to help
        a.perch = nil
        a.puppet.setPose(.stand)
      }
    }
    // The can goes on the display holding most of the clutter, at the edge nearest to it.
    let live = Set(stage.overlay.overlays.keys)
    let display =
      Dictionary(grouping: items.filter { live.contains($0.display ?? 0) }, by: { $0.display ?? 0 })
      .max { $0.value.count < $1.value.count }?.key
      ?? (live.contains(crew[0].display) ? crew[0].display : live.first ?? crew[0].display)
    let frame =
      stage.screen(display).map { stage.walkFrame(for: $0) } ?? stage.screenFrames.first ?? .zero
    let meanX = items.compactMap(\.position).map(\.x).reduce(0, +) / CGFloat(max(1, items.count))
    let right = meanX > frame.midX
    let k = stage.scale
    let canBase = CGPoint(
      x: right ? frame.maxX - 110 * k : frame.minX + 110 * k, y: frame.minY + 24)
    let canStand = CGPoint(x: canBase.x + (right ? -110 : 110) * k, y: canBase.y + 6 * k)
    guard let scene = stage.overlay.overlays[display]?.scene else {
      completion()
      return
    }
    let origin = stage.screen(display)?.frame.origin ?? .zero
    let can = TrashCanNode()
    can.setScale(k)
    can.zPosition = 10
    scene.addChild(can)
    let edge = right ? scene.size.width + 90 : -90
    can.slideIn(to: CGPoint(x: canBase.x - origin.x, y: canBase.y - origin.y), from: edge)
    let run = CleanupRun(can: can, canBase: canBase, display: display, edgeX: edge, manual: manual)
    run.completion = completion

    func key(_ a: Actor) -> String { "\(ObjectIdentifier(a).hashValue)" }
    let byKey = Dictionary(uniqueKeysWithValues: crew.map { (key($0), $0) })
    let plan = CleanupPlanner.plan(
      items: items, actors: byKey.mapValues { stage.feet(of: $0) }, can: canStand, now: Date())
    // The scene must take 10-30 s however clumsy she is: measure what was built, then hurry if it
    // is too long, or first look the clutter over if it is too short.
    trace(
      "plan: duration \(plan.duration) natural \(plan.natural), \(plan.assignments.count) assignments"
    )
    for (index, assignment) in plan.assignments.enumerated() {
      guard let a = byKey[assignment.actor] else { continue }
      // Everybody ends up at the can: each stands a little further along, so they read as separate.
      let toward: CGFloat = canStand.x < canBase.x ? -1 : 1
      let myCan = CGPoint(
        x: canStand.x + toward * CGFloat(index) * 90 * k,
        y: canStand.y + (index % 2 == 1 ? 18 * k : 0))
      a.cleaning = run
      run.remaining += 1
      var list = steps(for: a, trips: assignment.trips, run: run, canStand: myCan)
      let actual = SKAction.sequence(list).duration
      trace(
        "actor \(a.sessionID): \(assignment.trips.flatMap { $0 }.count) items, built \(actual) s")
      let target = plan.duration
      let seq: SKAction
      if actual > target {
        seq = SKAction.sequence(list)
        seq.speed = CGFloat(actual / target)
      } else {
        list.insert(.run { [weak a] in a?.puppet.perform(.shrug) }, at: 0)
        list.insert(.wait(forDuration: target - actual), at: 1)
        seq = SKAction.sequence(list)
      }
      a.puppet.run(seq, withKey: "brain")
    }
    if run.remaining == 0 { finish(run) }
    stage.noteActivity()
  }

  private func steps(
    for a: Actor, trips: [[ItemID]], run: CleanupRun, canStand: CGPoint
  ) -> [SKAction] {
    var out: [SKAction] = []
    var cursor = stage.feet(of: a)
    let k = stage.scale
    func chance(_ p: Double) -> Bool { Double.random(in: 0..<1, using: &rng) < p }
    func go(_ p: CGPoint) {
      a.userPlaced = true
      out.append(walk(a, from: cursor, to: p))
      cursor = p
    }
    for trip in trips {
      for id in trip {
        guard let pos = model.item(id)?.position else { continue }
        go(stage.clampFeet(near(pos, from: cursor, distance: 60 * k), of: a))
        out.append(.run { [weak self, weak a] in if let a { self?.carry(a, id) } })
        out.append(.wait(forDuration: 0.25))
        if chance(0.25) {  // trips over its own feet and drops it
          let spot = Scatter.spot(
            near: CGPoint(x: cursor.x + .random(in: -90...90, using: &rng), y: cursor.y + 40),
            existing: [], itemSize: ItemNode.footprint, screens: stage.screenFrames,
            seed: rng.next())
          out.append(
            .run { [weak self, weak a] in if let a { self?.stumble(a, dropping: id, at: spot) } })
          out.append(.wait(forDuration: 1.0))
          go(stage.clampFeet(near(spot, from: cursor, distance: 60 * k), of: a))
          out.append(.run { [weak self, weak a] in if let a { self?.carry(a, id) } })
          out.append(.wait(forDuration: 0.25))
        }
      }
      go(canStand)
      for id in trip {
        let missSpot: CGPoint? =
          chance(0.25)
          ? CGPoint(
            x: run.canBase.x + (canStand.x < run.canBase.x ? -1 : 1) * 170 * k, y: canStand.y + 20)
          : nil
        out.append(
          .run { [weak self, weak a] in
            if let a { self?.throwIn(a, id, run: run, missSpot: missSpot) }
          }
        )
        out.append(.wait(forDuration: 0.75))
        if let miss = missSpot {  // it bounced off the rim: fetch it and try again
          go(stage.clampFeet(near(miss, from: cursor, distance: 50 * k), of: a))
          out.append(.run { [weak self, weak a] in if let a { self?.carry(a, id) } })
          out.append(.wait(forDuration: 0.25))
          go(canStand)
          out.append(
            .run { [weak self, weak a] in if let a { self?.throwIn(a, id, run: run, missSpot: nil) }
            })
          out.append(.wait(forDuration: 0.75))
        }
      }
    }
    out.append(.run { [weak self, weak a] in if let a { self?.doneCleaning(a, run) } })
    return out
  }

  // MARK: Carrying an armful

  private func carry(_ a: Actor, _ id: ItemID) {
    guard let node = nodes[id], !a.armful.contains(where: { $0 === node }) else { return }
    detachFromHolders(node, except: a)
    node.removeAllActions()
    node.pointerExited()
    stage.draggables.removeAll { $0 === node }
    node.removeFromParent()
    node.setHeld(true)
    let i = CGFloat(a.armful.count)
    node.position = CGPoint(x: -88 + 14 * i, y: 112 + 16 * i)
    node.zPosition = 6 + i
    a.puppet.addChild(node)
    a.armful.append(node)
    updateArms(a)
  }

  /// Takes an item out of her arms, into the scene at its current screen position.
  private func detach(_ node: ItemNode, from a: Actor) -> SKScene? {
    guard let scene = stage.overlay.overlays[a.display]?.scene, let parent = node.parent else {
      return nil
    }
    let from = parent.convert(node.position, to: scene)
    a.armful.removeAll { $0 === node }
    updateArms(a)
    node.removeFromParent()
    node.setHeld(false)
    node.position = from
    node.zPosition = Stage.overlayZ - 20
    scene.addChild(node)
    return scene
  }

  /// An item is back on the screen as an ordinary, draggable one at `center`.
  private func landed(_ node: ItemNode, at center: CGPoint) {
    // Trashed or evicted while in the air: it must not come back as an invisible, click-eating item.
    guard nodes[node.itemID] === node else {
      node.removeFromParent()
      return
    }
    node.zPosition = 0
    stage.draggables.append(node)
    let settled = settle(node, at: center)
    model.move(node.itemID, to: settled.center, display: node.display)
  }

  private func arc(from: CGPoint, to: CGPoint, height: CGFloat, duration: TimeInterval) -> SKAction
  {
    let path = CGMutablePath()
    path.move(to: from)
    path.addQuadCurve(
      to: to, control: CGPoint(x: (from.x + to.x) / 2, y: max(from.y, to.y) + height))
    return .follow(path, asOffset: false, orientToPath: false, duration: duration)
  }

  /// She trips: the top item flies out of her arms and lands nearby.
  private func stumble(_ a: Actor, dropping id: ItemID, at spot: CGPoint) {
    guard let node = a.armful.first(where: { $0.itemID == id }), detach(node, from: a) != nil
    else { return }
    a.puppet.perform(.trip)
    a.puppet.run(
      .sequence([
        .rotate(toAngle: 0.18, duration: 0.1), .rotate(toAngle: -0.12, duration: 0.12),
        .rotate(toAngle: 0, duration: 0.1),
      ]), withKey: "trip")
    let settled = settle(node, at: spot)
    let flight = arc(from: node.position, to: settled.scenePosition, height: 60, duration: 0.5)
    node.run(
      .sequence([
        .group([flight, .rotate(byAngle: 3, duration: 0.5)]),
        .run { [weak self, weak node] in
          if let self, let node { self.landed(node, at: spot) }
        },
      ]))
  }

  /// Tosses an item at the can. A miss bounces off the rim and lands on the floor (`missSpot`).
  private func throwIn(_ a: Actor, _ id: ItemID, run: CleanupRun, missSpot: CGPoint?) {
    guard let node = a.armful.first(where: { $0.itemID == id }), detach(node, from: a) != nil
    else { return }
    let origin = stage.screen(run.display)?.frame.origin ?? .zero
    let k = stage.scale
    let mouth = CGPoint(
      x: run.canBase.x - origin.x + TrashCanNode.mouth.x * k,
      y: run.canBase.y - origin.y + TrashCanNode.mouth.y * k)
    let toMouth = arc(from: node.position, to: mouth, height: 70, duration: 0.5)
    if let miss = missSpot {
      let settled = settle(node, at: miss)
      let bounce = arc(from: mouth, to: settled.scenePosition, height: 50, duration: 0.45)
      node.run(
        .sequence([
          toMouth,
          .run { [weak run] in run?.can.clank() },
          .group([bounce, .rotate(byAngle: -4, duration: 0.45)]),
          .run { [weak self, weak node] in
            if let self, let node { self.landed(node, at: miss) }
          },
        ]))
    } else {
      node.run(
        .sequence([
          toMouth,
          .run { [weak run] in run?.can.clank() },
          .group([.scale(to: 0.1, duration: 0.15), .fadeOut(withDuration: 0.15)]),
          .removeFromParent(),
        ]))
      model.remove([id])
      nodes.removeValue(forKey: id)
    }
  }

  // MARK: Finishing

  private func doneCleaning(_ a: Actor, _ run: CleanupRun) {
    guard a.cleaning === run else { return }
    trace("done: \(a.sessionID), \(run.remaining) crew left")
    a.cleaning = nil
    a.armful.removeAll()
    updateArms(a)
    run.remaining -= 1
    if run.remaining <= 0 { finish(run) }
    DispatchQueue.main.async { [weak self, weak a] in if let self, let a { self.brainEnded(a) } }
  }

  private func finish(_ run: CleanupRun) {
    // Strong capture on purpose: the last crew member may be the only thing keeping the run alive.
    run.can.slideOut(toward: run.edgeX) {
      let done = run.completion
      run.completion = nil
      done?()
    }
  }

  /// Real work arrived during an automatic tidy-up: she puts down what she carries and gets on.
  func cancelCleanup(_ a: Actor) {
    guard let run = a.cleaning else { return }
    a.puppet.removeAction(forKey: "brain")
    a.puppet.setWalking(false)
    let spot = stage.feet(of: a)
    for node in a.armful where detach(node, from: a) != nil {
      landed(node, at: CGPoint(x: spot.x - 130 * stage.scale, y: spot.y + 20))
      node.pop()
    }
    a.armful.removeAll()
    updateArms(a)
    a.cleaning = nil
    run.remaining -= 1
    if run.remaining <= 0 { finish(run) }
  }
}
