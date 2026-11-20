import Foundation
import Testing

@testable import ClaudetteCore

private func payload(_ json: String) throws -> StatusPayload {
  try StatusPayload.decode(Data(json.utf8))
}

@Test func decodesBothWindows() throws {
  let p = try payload(
    """
    {"session_id":"s1","cwd":"/p","model":{"id":"claude-opus-5-5","display_name":"Opus"},
     "context_window":{"used_percentage":8},"cost":{"total_cost_usd":0.01234},
     "rate_limits":{"five_hour":{"used_percentage":23.5,"resets_at":1738425600},
                    "seven_day":{"used_percentage":41.2,"resets_at":1738857600}}}
    """)
  #expect(p.sessionID == "s1")
  #expect(p.cwd == "/p")
  #expect(p.modelDisplayName == "Opus")
  #expect(p.contextUsedPercentage == 8)
  #expect(p.totalCostUSD == 0.01234)
  #expect(p.fiveHour?.usedPercentage == 23.5)
  #expect(p.fiveHour?.resetsAt == Date(timeIntervalSince1970: 1_738_425_600))
  #expect(p.sevenDay?.usedPercentage == 41.2)
  #expect(p.sevenDay?.resetsAt == Date(timeIntervalSince1970: 1_738_857_600))
}

@Test func windowAbsentIsNil() throws {
  let p = try payload(
    #"{"session_id":"s1","rate_limits":{"seven_day":{"used_percentage":10,"resets_at":1738857600}}}"#
  )
  #expect(p.fiveHour == nil)
  #expect(p.sevenDay != nil)
}

@Test func clampsPercentage() throws {
  let p = try payload(
    #"{"session_id":"s1","rate_limits":{"five_hour":{"used_percentage":-5,"resets_at":1738425600},"seven_day":{"used_percentage":140,"resets_at":1738857600}}}"#
  )
  #expect(p.fiveHour?.usedPercentage == 0)
  #expect(p.sevenDay?.usedPercentage == 100)
}

@Test func limitWindowRejectsNonFiniteValues() {
  #expect(LimitWindow(usedPercentage: .nan, resetsAt: Date()) == nil)
  #expect(LimitWindow(usedPercentage: .infinity, resetsAt: Date()) == nil)
  #expect(LimitWindow(usedPercentage: 50, resetsAt: Date()) != nil)
}

@Test func windowWithoutResetTimeOrPercentageIsDropped() throws {
  let p = try payload(
    #"{"session_id":"s1","rate_limits":{"five_hour":{"used_percentage":10},"seven_day":{"resets_at":1738857600}}}"#
  )
  #expect(p.fiveHour == nil)
  #expect(p.sevenDay == nil)
}

@Test func acceptsISOResetTime() throws {
  let p = try payload(
    #"{"session_id":"s1","rate_limits":{"five_hour":{"used_percentage":10,"resets_at":"2025-02-01T16:00:00Z"}}}"#
  )
  #expect(p.fiveHour?.resetsAt == Date(timeIntervalSince1970: 1_738_425_600))
}

@Test func noRateLimitsKeyGivesNilWindows() throws {
  let p = try payload(#"{"session_id":"s1"}"#)
  #expect(p.fiveHour == nil && p.sevenDay == nil)
  #expect(p.modelDisplayName == nil && p.contextUsedPercentage == nil)
}

@Test func rejectsNonObjectAndMissingSession() {
  #expect(throws: (any Error).self) { try payload("[1]") }
  #expect(throws: (any Error).self) { try payload("nope") }
  #expect(throws: (any Error).self) { try payload(#"{"cwd":"/p"}"#) }
}
