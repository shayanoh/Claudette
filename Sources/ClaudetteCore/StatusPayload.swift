import Foundation

public enum StatusDecodeError: Error, Equatable {
  case notAnObject
  case missingSessionID
}

public struct LimitWindow: Equatable, Sendable {
  public let usedPercentage: Double
  public let resetsAt: Date

  /// Clamps the percentage to 0...100; non-finite values are rejected.
  public init?(usedPercentage: Double, resetsAt: Date) {
    guard usedPercentage.isFinite else { return nil }
    self.usedPercentage = min(100, max(0, usedPercentage))
    self.resetsAt = resetsAt
  }

  /// Reads `{used_percentage, resets_at}` where `resets_at` is epoch seconds (or an ISO-8601
  /// string, tolerated in case the schema drifts). A window missing either value is dropped.
  init?(json: JSONValue?) {
    guard let json,
      let used = json["used_percentage"]?.doubleValue ?? json["utilization"]?.doubleValue
    else { return nil }
    let reset: Date?
    if let secs = json["resets_at"]?.doubleValue, secs.isFinite {
      reset = Date(timeIntervalSince1970: secs)
    } else if let text = json["resets_at"]?.stringValue {
      reset = ISO8601DateFormatter().date(from: text)
    } else {
      reset = nil
    }
    guard let reset else { return nil }
    self.init(usedPercentage: used, resetsAt: reset)
  }
}

/// The JSON Claude Code passes to the status line command (only the parts we use).
public struct StatusPayload: Equatable, Sendable {
  public let sessionID: String
  public let cwd: String?
  public let modelDisplayName: String?
  public let contextUsedPercentage: Double?
  public let totalCostUSD: Double?
  public let fiveHour: LimitWindow?
  public let sevenDay: LimitWindow?

  public init(
    sessionID: String, cwd: String?, modelDisplayName: String?, contextUsedPercentage: Double?,
    totalCostUSD: Double?, fiveHour: LimitWindow?, sevenDay: LimitWindow?
  ) {
    self.sessionID = sessionID
    self.cwd = cwd
    self.modelDisplayName = modelDisplayName
    self.contextUsedPercentage = contextUsedPercentage
    self.totalCostUSD = totalCostUSD
    self.fiveHour = fiveHour
    self.sevenDay = sevenDay
  }

  public static func decode(_ data: Data) throws -> StatusPayload {
    let raw = try JSONDecoder().decode(JSONValue.self, from: data)
    guard case .object = raw else { throw StatusDecodeError.notAnObject }
    guard let id = raw["session_id"]?.stringValue, !id.isEmpty else {
      throw StatusDecodeError.missingSessionID
    }
    let limits = raw["rate_limits"]
    return StatusPayload(
      sessionID: id,
      cwd: raw["cwd"]?.stringValue,
      modelDisplayName: raw["model"]?["display_name"]?.stringValue,
      contextUsedPercentage: raw["context_window"]?["used_percentage"]?.doubleValue,
      totalCostUSD: raw["cost"]?["total_cost_usd"]?.doubleValue,
      fiveHour: LimitWindow(json: limits?["five_hour"]),
      sevenDay: LimitWindow(json: limits?["seven_day"]))
  }
}
