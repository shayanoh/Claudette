import Foundation

public enum LimitKind: Equatable, Sendable, CaseIterable {
  case fiveHour
  case sevenDay
}

public enum LimitStatus: Equatable, Sendable {
  case unknown, fresh, low, inLimit
}

public struct WindowState: Equatable, Sendable {
  public var status: LimitStatus
  public var usedPercentage: Double?
  public var resetsAt: Date?

  public static let unknown = WindowState(status: .unknown, usedPercentage: nil, resetsAt: nil)
}

/// Tracks the 5-hour and weekly usage windows. Not thread-safe: use from one queue (main).
public final class LimitsModel {
  public static let lowThreshold = 80.0

  public var onTransition: ((LimitKind, LimitStatus, LimitStatus) -> Void)?
  public var onLifted: ((LimitKind) -> Void)?

  private let now: () -> Date
  private var states: [LimitKind: WindowState] = [:]
  /// Set when a rate-limit failure (not a usage percentage) put the window in limit.
  private var forced: Set<LimitKind> = []

  public init(now: @escaping () -> Date) {
    self.now = now
  }

  public func state(_ kind: LimitKind) -> WindowState {
    states[kind] ?? .unknown
  }

  public func ingest(_ payload: StatusPayload) {
    apply(.fiveHour, payload.fiveHour)
    apply(.sevenDay, payload.sevenDay)
  }

  /// A rate-limit StopFailure means we are in limit even if no percentage says so. The failure
  /// does not say which window ran out, so the window with the higher reading is blamed (the
  /// 5-hour window when there is no data). Without a reset time the window's own length is the
  /// fallback, so a limit can never stay on forever.
  public func ingestRateLimitFailure(resetsAt: Date?) {
    let five = state(.fiveHour).usedPercentage ?? -1
    let seven = state(.sevenDay).usedPercentage ?? -1
    let kind: LimitKind = seven > five ? .sevenDay : .fiveHour
    let length: TimeInterval = kind == .fiveHour ? 5 * 3600 : 7 * 86400
    let reset = resetsAt ?? state(kind).resetsAt ?? now().addingTimeInterval(length)
    forced.insert(kind)
    set(kind, WindowState(status: .inLimit, usedPercentage: 100, resetsAt: reset))
  }

  /// Claude Code completed real work again (a tool call succeeded): a limit that was only
  /// inferred from a failure is over. Limits backed by a usage percentage are left alone.
  public func noteSuccessfulWork() {
    for kind in forced {
      forced.remove(kind)
      set(kind, WindowState(status: .fresh, usedPercentage: 0, resetsAt: nil))
    }
  }

  /// Call about once a second: lifts limits whose reset time has passed.
  public func tick() {
    for kind in LimitKind.allCases {
      guard let reset = state(kind).resetsAt, reset <= now() else { continue }
      forced.remove(kind)
      set(kind, WindowState(status: .fresh, usedPercentage: 0, resetsAt: nil))
    }
  }

  private func apply(_ kind: LimitKind, _ window: LimitWindow?) {
    // An absent window changes nothing (Claude Code drops windows after their reset time, and
    // tick() handles that). A window whose reset time already passed is stale data.
    guard let window, window.resetsAt > now() else { return }
    // After a rate-limit rejection, a payload still showing high usage is stale; only a clearly
    // lower reading lifts the limit.
    if forced.contains(kind) {
      if window.usedPercentage >= Self.lowThreshold { return }
      forced.remove(kind)
    }
    let status: LimitStatus
    switch window.usedPercentage {
    case 100...: status = .inLimit
    case Self.lowThreshold...: status = .low
    default: status = .fresh
    }
    set(
      kind,
      WindowState(
        status: status, usedPercentage: window.usedPercentage, resetsAt: window.resetsAt))
  }

  private func set(_ kind: LimitKind, _ new: WindowState) {
    let old = state(kind)
    states[kind] = new
    guard old.status != new.status else { return }
    onTransition?(kind, old.status, new.status)
    if old.status == .inLimit { onLifted?(kind) }
  }
}
