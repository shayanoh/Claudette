import CoreGraphics
import Foundation
import Testing

@testable import ClaudetteCore

private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
private let can = CGPoint(x: 1300, y: 60)

private func item(
  _ n: Int, at p: CGPoint? = CGPoint(x: 700, y: 400), owners: Set<String> = ["s1"], age: Double = 0,
  terminal: TerminalState? = nil
) -> Item {
  Item(
    id: ItemID.tool(useID: "i\(n)"), kind: terminal == nil ? .file : .terminal, label: "i\(n)",
    owners: owners, createdAt: t0, lastTouched: t0.addingTimeInterval(age), position: p,
    display: 1,
    terminal: terminal.map { TerminalInfo(command: "x", state: $0, result: nil) })
}

private func many(_ n: Int) -> [Item] {
  (0..<n).map {
    item($0, at: CGPoint(x: 100 + Double($0 % 20) * 60, y: 300 + Double($0 / 20) * 60))
  }
}

@Test func durationIsClampedTo10And30() {
  let one = CleanupPlanner.plan(
    items: [item(1)], actors: ["a": CGPoint(x: 600, y: 100)], can: can, now: t0)
  #expect(one.duration == 10)
  let lots = CleanupPlanner.plan(
    items: many(200), actors: ["a": CGPoint(x: 600, y: 100)], can: can, now: t0)
  #expect(lots.duration == 30)
}

@Test func everyItemIsAssignedExactlyOnce() {
  let items = many(37)
  let plan = CleanupPlanner.plan(
    items: items, actors: ["a": CGPoint(x: 100, y: 100), "b": CGPoint(x: 900, y: 100)], can: can,
    now: t0)
  let assigned = plan.assignments.flatMap { $0.trips.flatMap { $0 } }
  #expect(assigned.count == 37)
  #expect(Set(assigned) == Set(items.map(\.id)))
}

@Test func nearestActorGetsTheNearestItems() {
  let left = (0..<4).map { item($0, at: CGPoint(x: 100 + Double($0) * 10, y: 300)) }
  let right = (10..<14).map { item($0, at: CGPoint(x: 1200 + Double($0) * 5, y: 300)) }
  let plan = CleanupPlanner.plan(
    items: left + right, actors: ["L": CGPoint(x: 100, y: 100), "R": CGPoint(x: 1250, y: 100)],
    can: can, now: t0)
  func ids(_ a: String) -> Set<ItemID> {
    Set(plan.assignments.first { $0.actor == a }?.trips.flatMap { $0 } ?? [])
  }
  #expect(ids("L") == Set(left.map(\.id)))
  #expect(ids("R") == Set(right.map(\.id)))
}

@Test func manyItemsMeanBiggerTripsNotLongerTime() {
  let few = CleanupPlanner.plan(
    items: many(4), actors: ["a": CGPoint(x: 600, y: 100)], can: can, now: t0)
  let lots = CleanupPlanner.plan(
    items: many(80), actors: ["a": CGPoint(x: 600, y: 100)], can: can, now: t0)
  let fewMax = few.assignments.flatMap(\.trips).map(\.count).max() ?? 0
  let lotsMax = lots.assignments.flatMap(\.trips).map(\.count).max() ?? 0
  #expect(fewMax >= 1 && fewMax <= 3)
  #expect(lotsMax == 3)  // never more than three per trip
  #expect(lots.duration <= 30)
}

@Test func noActorsOrNoItemsMeansNoAssignments() {
  #expect(CleanupPlanner.plan(items: many(5), actors: [:], can: can, now: t0).assignments.isEmpty)
  let none = CleanupPlanner.plan(items: [], actors: ["a": CGPoint.zero], can: can, now: t0)
  #expect(none.assignments.isEmpty && none.duration == 0)
}

@Test func itemsWithoutAPositionAreStillCollected() {
  let plan = CleanupPlanner.plan(
    items: [item(1, at: nil)], actors: ["a": CGPoint(x: 100, y: 100)], can: can, now: t0)
  #expect(plan.assignments.flatMap { $0.trips.flatMap { $0 } }.count == 1)
}

// MARK: - ClutterPolicy

private func owned(_ n: Int) -> [Item] { (0..<n).map { item($0, age: Double($0)) } }

@Test func autoTidyOnlyWhenWaitingAndOverTheLimit() {
  let items = owned(20)
  func tidy(_ phase: SessionPhase, limit: Int = 12, enabled: Bool = true) -> [ItemID] {
    ClutterPolicy.autoTidy(
      session: "s1", owned: items, phase: phase, softLimit: limit, enabled: enabled)
  }
  #expect(!tidy(.needsApproval).isEmpty)
  #expect(!tidy(.hasQuestion).isEmpty)
  #expect(!tidy(.idle).isEmpty)
  #expect(tidy(.working).isEmpty)
  #expect(tidy(.sleeping).isEmpty)
  #expect(tidy(.idle, limit: 20).isEmpty)  // not over
  #expect(tidy(.idle, enabled: false).isEmpty)
}

@Test func autoTidyLeavesHalfTheLimitAndTakesTheOldestFirst() {
  let items = owned(20)
  let ids = ClutterPolicy.autoTidy(
    session: "s1", owned: items, phase: .idle, softLimit: 12, enabled: true)
  #expect(ids.count == 20 - 6)
  #expect(ids.first == items[0].id)  // oldest first
  #expect(!ids.contains(items[19].id))
}

@Test func runningTerminalsAreNeverAutoTidied() {
  var items = owned(20)
  items[0] = item(0, age: 0, terminal: .running)
  let ids = ClutterPolicy.autoTidy(
    session: "s1", owned: items, phase: .idle, softLimit: 12, enabled: true)
  #expect(!ids.contains(items[0].id))
}

@Test func otherSessionsItemsAreNeverTouchedByAutoTidy() {
  var items = owned(20)
  items[3].owners = ["s1", "s2"]  // shared: another session still uses it
  let ids = ClutterPolicy.autoTidy(
    session: "s1", owned: items, phase: .idle, softLimit: 12, enabled: true)
  #expect(!ids.contains(items[3].id))
}

@Test func sessionEndReturnsOnlySoleOwnerItems() {
  let mine = item(1, owners: ["s1"])
  let shared = item(2, owners: ["s1", "s2"])
  let theirs = item(3, owners: ["s2"])
  let ids = ClutterPolicy.sessionEnd(session: "s1", items: [mine, shared, theirs])
  #expect(ids == [mine.id])
}

@Test func theUnscaledTimeIsReportedSoTheSceneCanSpeedUpOrDawdle() {
  let plan = CleanupPlanner.plan(
    items: many(200), actors: ["a": CGPoint(x: 600, y: 100)], can: can, now: t0)
  #expect(plan.natural > plan.duration)  // far too much work for 30 s: she must hurry
  let one = CleanupPlanner.plan(
    items: [item(1)], actors: ["a": CGPoint(x: 600, y: 100)], can: can, now: t0)
  #expect(one.natural < one.duration)  // a single item: she dawdles to fill the 10 s
}
