import CoreGraphics
import Foundation
import Testing

@testable import ClaudetteCore

private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

private func item(_ name: String, at p: CGPoint?) -> Item {
  Item(
    id: ItemID.tool(useID: name), kind: .file, label: name, owners: ["s1"], createdAt: t0,
    lastTouched: t0, position: p, display: 1, terminal: nil)
}

private func actor(
  at p: CGPoint = CGPoint(x: 500, y: 300), holding: ItemID? = nil, sub: Bool = false,
  anchor: CGPoint? = nil, leash: CGFloat = 0, task: (item: ItemID, move: Move)? = nil
) -> BrainActor {
  BrainActor(
    position: p, holding: holding, isSubagent: sub, anchor: anchor, leash: leash, task: task)
}

private func plan(_ event: BrainEvent, _ a: BrainActor, world: [Item] = [], seed: UInt64 = 1)
  -> [Intent]
{
  var rng = SeededRandom(seed: seed)
  return Brain().plan(event: event, actor: a, world: world, screens: [screen], rng: &rng)
}

private func onScreen(_ p: CGPoint) -> Bool { screen.contains(p) }

private func walks(_ intents: [Intent]) -> [CGPoint] {
  intents.compactMap { if case .walk(let p) = $0 { return p } else { return nil } }
}

@Test func newItemMakesActorReadInPlaceThenToss() {
  let it = item("a", at: CGPoint(x: 520, y: 300))
  let intents = plan(.toolStarted(it, isNew: true, move: .read), actor(), world: [it])
  #expect(intents.count == 3)
  #expect(intents[0] == .face(CGPoint(x: 520, y: 300)))
  #expect(intents[1] == .play(.read))
  guard case .toss(let id, let to) = intents[2] else {
    Issue.record("expected a toss, got \(intents[2])")
    return
  }
  #expect(id == it.id)
  #expect(onScreen(to) && to != CGPoint(x: 520, y: 300))
}

@Test func existingItemFarAwayMakesActorWalkThereFirst() {
  let it = item("a", at: CGPoint(x: 900, y: 600))
  let intents = plan(
    .toolStarted(it, isNew: false, move: .read), actor(at: CGPoint(x: 100, y: 100)), world: [it])
  guard case .walk(let stand)? = intents.first else {
    Issue.record("expected a walk first: \(intents)")
    return
  }
  #expect(abs(hypot(stand.x - 900, stand.y - 600) - 60) < 1)
  #expect(stand.x < 900 && stand.y < 600)  // she stops on her own side of it
  #expect(intents.contains(.play(.read)))
  #expect(!intents.contains { if case .toss = $0 { return true } else { return false } })
}

@Test func existingItemNearbyIsReadInPlace() {
  let it = item("a", at: CGPoint(x: 540, y: 310))
  let intents = plan(.toolStarted(it, isNew: false, move: .typing), actor(), world: [it])
  #expect(walks(intents).isEmpty)
  #expect(intents.contains(.play(.typing)))
}

@Test func itemMovedWhileWalkingRetargets() {
  let moved = item("a", at: CGPoint(x: 1200, y: 700))
  let a = actor(task: (moved.id, .read))
  let intents = plan(.itemMoved(moved.id), a, world: [moved])
  guard case .walk(let stand)? = intents.first else {
    Issue.record("expected a re-target walk: \(intents)")
    return
  }
  #expect(abs(hypot(stand.x - 1200, stand.y - 700) - 60) < 1)
  #expect(intents.contains(.play(.read)))
  let other = item("b", at: CGPoint(x: 10, y: 10))
  #expect(plan(.itemMoved(other.id), a, world: [moved, other]).isEmpty)
}

@Test func thinkingProducesWanderLegsOnScreen() {
  for seed in 0..<30 {
    let intents = plan(.thinkingChanged(true), actor(at: CGPoint(x: 20, y: 20)), seed: UInt64(seed))
    #expect(intents.first == .play(.think))
    #expect(walks(intents).count >= 2)
    for p in walks(intents) { #expect(onScreen(p)) }
  }
}

@Test func thinkingEndsAndToolStartHasNoWander() {
  #expect(plan(.thinkingChanged(false), actor()).isEmpty)
  let it = item("a", at: CGPoint(x: 520, y: 300))
  let intents = plan(.toolStarted(it, isNew: true, move: .read), actor(), world: [it])
  #expect(!intents.contains(.play(.think)))
}

@Test func subagentWanderStaysInsideLeash() {
  let anchor = CGPoint(x: 700, y: 400)
  for seed in 0..<100 {
    let a = actor(at: anchor, sub: true, anchor: anchor, leash: 150)
    for p in walks(plan(.thinkingChanged(true), a, seed: UInt64(seed))) {
      #expect(hypot(p.x - anchor.x, p.y - anchor.y) <= 150.5)
    }
  }
}

@Test func subagentOutsideLeashReturnsWhenIdle() {
  let anchor = CGPoint(x: 700, y: 400)
  let far = actor(at: CGPoint(x: 1300, y: 800), sub: true, anchor: anchor, leash: 150)
  let back = walks(plan(.idle, far))
  #expect(back.count == 1)
  #expect(hypot(back[0].x - anchor.x, back[0].y - anchor.y) <= 150.5)
  let near = actor(at: CGPoint(x: 720, y: 410), sub: true, anchor: anchor, leash: 150)
  #expect(plan(.idle, near).isEmpty)
  #expect(plan(.idle, actor()).isEmpty)  // a parent never gets pulled anywhere
}

@Test func shyDodgeWhileHoldingPutsItemDownAtEndPoint() {
  let held = ItemID.tool(useID: "held")
  let end = CGPoint(x: 900, y: 120)
  #expect(plan(.dodge(to: end), actor(holding: held)) == [.putDown(at: end)])
  #expect(plan(.dodge(to: end), actor()).isEmpty)
}

@Test func sessionEndWhileHoldingPutsItemDownWhereSheStands() {
  let held = ItemID.tool(useID: "held")
  let here = CGPoint(x: 500, y: 300)
  #expect(plan(.sessionEnded, actor(at: here, holding: held)) == [.putDown(at: here)])
  #expect(plan(.sessionEnded, actor()).isEmpty)
}

@Test func holdingSomethingIsPutDownBeforeReading() {
  let held = ItemID.tool(useID: "held")
  let it = item("a", at: CGPoint(x: 520, y: 300))
  let intents = plan(
    .toolStarted(it, isNew: true, move: .read), actor(holding: held), world: [it])
  #expect(intents.first == .putDown(at: CGPoint(x: 500, y: 300)))
}

@Test func walkTargetsAreAlwaysOnScreen() {
  let corner = item("a", at: CGPoint(x: 1439, y: 899))
  let intents = plan(
    .toolStarted(corner, isNew: false, move: .read), actor(at: CGPoint(x: 1, y: 1)),
    world: [corner])
  for p in walks(intents) { #expect(onScreen(p)) }
}

@Test func moveForSceneCoversEveryScene() {
  #expect(Brain.move(for: .read(file: "a")) == .read)
  #expect(Brain.move(for: .edit(file: nil)) == .typing)
  #expect(Brain.move(for: .write(file: "a")) == .typing)
  #expect(Brain.move(for: .search) == .search)
  #expect(Brain.move(for: .shell(long: false, background: false)) == .typing)
  #expect(Brain.move(for: .web) == .read)
  #expect(Brain.move(for: .skill(name: "x")) == .read)
  #expect(Brain.move(for: .mcp(server: "g", tool: "t")) == .typing)
  #expect(Brain.move(for: .todo) == .think)
  #expect(Brain.move(for: .plan) == .think)
  #expect(Brain.move(for: .other(tool: "x")) == .shrug)
  #expect(Brain.move(for: .subagent) == .think)
}

@Test func nonFinitePositionsDoNotCrashOrEscapeTheScreen() {
  let a = actor(at: CGPoint(x: CGFloat.nan, y: 5))
  let it = item("a", at: CGPoint(x: CGFloat.infinity, y: 5))
  for event in [
    BrainEvent.toolStarted(it, isNew: false, move: .read), .thinkingChanged(true), .idle,
  ] {
    for p in walks(plan(event, a, world: [it])) { #expect(onScreen(p)) }
  }
}
