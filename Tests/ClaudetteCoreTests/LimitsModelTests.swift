import Foundation
import Testing

@testable import ClaudetteCore

private final class Clock: @unchecked Sendable {
  var now = Date(timeIntervalSince1970: 1_700_000_000)
  func advance(_ s: TimeInterval) { now = now.addingTimeInterval(s) }
}

private final class Recorder {
  var lifted: [LimitKind] = []
  var transitions: [String] = []
}

private func make() -> (LimitsModel, Clock, Recorder) {
  let clock = Clock()
  let model = LimitsModel(now: { clock.now })
  let rec = Recorder()
  model.onLifted = { rec.lifted.append($0) }
  model.onTransition = { k, a, b in rec.transitions.append("\(k):\(a)->\(b)") }
  return (model, clock, rec)
}

private func status(
  five: Double? = nil, seven: Double? = nil, clock: Clock, fiveIn: TimeInterval = 3600,
  sevenIn: TimeInterval = 86400
) -> StatusPayload {
  StatusPayload(
    sessionID: "s1", cwd: nil, modelDisplayName: nil, contextUsedPercentage: nil, totalCostUSD: nil,
    fiveHour: five.flatMap {
      LimitWindow(usedPercentage: $0, resetsAt: clock.now.addingTimeInterval(fiveIn))
    },
    sevenDay: seven.flatMap {
      LimitWindow(usedPercentage: $0, resetsAt: clock.now.addingTimeInterval(sevenIn))
    })
}

@Test func unknownBeforeAnyData() {
  let (m, _, _) = make()
  #expect(m.state(.fiveHour).status == .unknown)
  #expect(m.state(.sevenDay).status == .unknown)
  #expect(m.state(.fiveHour).usedPercentage == nil)
}

@Test func freshBelow80LowFrom80InLimitAt100() {
  let (m, c, _) = make()
  m.ingest(status(five: 79.9, clock: c))
  #expect(m.state(.fiveHour).status == .fresh)
  m.ingest(status(five: 80, clock: c))
  #expect(m.state(.fiveHour).status == .low)
  m.ingest(status(five: 99.9, clock: c))
  #expect(m.state(.fiveHour).status == .low)
  m.ingest(status(five: 100, clock: c))
  #expect(m.state(.fiveHour).status == .inLimit)
}

@Test func rateLimitFailureForcesInLimit() {
  let (m, c, _) = make()
  m.ingest(status(five: 50, clock: c))
  m.ingestRateLimitFailure(resetsAt: c.now.addingTimeInterval(1800))
  #expect(m.state(.fiveHour).status == .inLimit)
  #expect(m.state(.fiveHour).resetsAt == c.now.addingTimeInterval(1800))
}

@Test func liftedFiresOnceWhenResetsAtPasses() {
  let (m, c, r) = make()
  m.ingest(status(five: 100, clock: c, fiveIn: 600))
  c.advance(599)
  m.tick()
  #expect(r.lifted.isEmpty)
  c.advance(2)
  m.tick()
  m.tick()
  #expect(r.lifted == [.fiveHour])
  #expect(m.state(.fiveHour).status == .fresh)
}

@Test func liftedFiresWhenLaterPayloadShowsLowerPercentage() {
  let (m, c, r) = make()
  m.ingest(status(five: 100, clock: c))
  m.ingest(status(five: 5, clock: c))
  #expect(r.lifted == [.fiveHour])
  #expect(m.state(.fiveHour).status == .fresh)
}

@Test func noLiftedWhenWindowSimplyVanishesWithoutBeingInLimit() {
  let (m, c, r) = make()
  m.ingest(status(five: 60, clock: c, fiveIn: 100))
  c.advance(200)
  m.tick()
  m.ingest(status(clock: c))  // window absent
  #expect(r.lifted.isEmpty)
}

@Test func absentWindowKeepsInLimitUntilResetTime() {
  let (m, c, r) = make()
  m.ingest(status(five: 100, clock: c, fiveIn: 600))
  m.ingest(status(clock: c))
  #expect(m.state(.fiveHour).status == .inLimit)
  #expect(r.lifted.isEmpty)
}

@Test func windowIndependence() {
  let (m, c, _) = make()
  m.ingest(status(seven: 90, clock: c))
  #expect(m.state(.fiveHour).status == .unknown)
  #expect(m.state(.sevenDay).status == .low)
}

@Test func pastResetsAtInFreshPayloadIsIgnored() {
  let (m, c, _) = make()
  let stale = StatusPayload(
    sessionID: "s", cwd: nil, modelDisplayName: nil, contextUsedPercentage: nil, totalCostUSD: nil,
    fiveHour: LimitWindow(usedPercentage: 100, resetsAt: c.now.addingTimeInterval(-10)),
    sevenDay: nil)
  m.ingest(stale)
  #expect(m.state(.fiveHour).status == .unknown)
}

@Test func staleHighPayloadDoesNotLiftForcedLimit() {
  let (m, c, r) = make()
  m.ingestRateLimitFailure(resetsAt: c.now.addingTimeInterval(1800))
  m.ingest(status(five: 92, clock: c))  // contradicts the rejection; do not announce "lifted"
  #expect(m.state(.fiveHour).status == .inLimit)
  #expect(r.lifted.isEmpty)
  m.ingest(status(five: 10, clock: c))
  #expect(r.lifted == [.fiveHour])
}

@Test func transitionsAreReported() {
  let (m, c, r) = make()
  m.ingest(status(five: 10, clock: c))
  m.ingest(status(five: 95, clock: c))
  #expect(r.transitions == ["fiveHour:unknown->fresh", "fiveHour:fresh->low"])
}

@Test func failureWithoutResetTimeStillInLimitUntilLowerPayload() {
  let (m, c, r) = make()
  m.ingestRateLimitFailure(resetsAt: nil)
  #expect(m.state(.fiveHour).status == .inLimit)
  c.advance(10_000)
  m.tick()
  #expect(m.state(.fiveHour).status == .inLimit)
  m.ingest(status(five: 3, clock: c))
  #expect(r.lifted == [.fiveHour])
}

@Test func failureForcesTheWindowThatIsActuallyExhausted() {
  let (m, c, r) = make()
  m.ingest(status(five: 30, seven: 100, clock: c))  // weekly is the exhausted one
  m.ingestRateLimitFailure(resetsAt: nil)
  #expect(m.state(.sevenDay).status == .inLimit)
  #expect(m.state(.fiveHour).status == .fresh)
  m.ingest(status(five: 20, seven: 100, clock: c))  // 5h moves; weekly still exhausted
  #expect(r.lifted.isEmpty)
}

@Test func failureWithNoDataFallsBackToFiveHourWindow() {
  let (m, _, _) = make()
  m.ingestRateLimitFailure(resetsAt: nil)
  #expect(m.state(.fiveHour).status == .inLimit)
  #expect(m.state(.sevenDay).status == .unknown)
}

@Test func forcedLimitWithoutResetTimeExpiresAfterTheFallbackWindow() {
  let (m, c, r) = make()
  m.ingestRateLimitFailure(resetsAt: nil)
  c.advance(5 * 3600 - 1)
  m.tick()
  #expect(m.state(.fiveHour).status == .inLimit)
  c.advance(2)
  m.tick()
  #expect(m.state(.fiveHour).status == .fresh)
  #expect(r.lifted == [.fiveHour])
}

@Test func successfulWorkLiftsAForcedLimit() {
  let (m, _, r) = make()
  m.ingestRateLimitFailure(resetsAt: nil)
  m.noteSuccessfulWork()
  #expect(m.state(.fiveHour).status == .fresh)
  #expect(r.lifted == [.fiveHour])
}

@Test func successfulWorkDoesNotTouchAPercentageBasedLimit() {
  let (m, c, r) = make()
  m.ingest(status(five: 100, clock: c))  // in limit because the usage says so
  m.noteSuccessfulWork()
  #expect(m.state(.fiveHour).status == .inLimit)
  #expect(r.lifted.isEmpty)
}
