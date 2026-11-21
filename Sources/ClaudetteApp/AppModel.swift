import AppKit
import ClaudetteCore

/// Wires the feed, the state machines and the on-screen stage together. Everything below runs on
/// the main thread.
final class AppModel {
  static let feedPort: UInt16 = 47631

  let settings = SettingsStore()
  let store = SessionStore(now: Date.init)
  let limits = LimitsModel(now: Date.init)
  let overlay = OverlayController()
  private(set) lazy var stage = Stage(overlay: overlay, settings: settings)
  private let pointer = PointerTracker()
  private let caret = CaretTracker()
  private var caretAsked = false
  private(set) lazy var hud = LimitsHUD(
    limits: limits, stage: stage, overlay: overlay, settings: settings)
  private var server: FeedServer?
  private var timer: Timer?
  /// Raw payload logging is off by default (it can contain prompts); set CLAUDETTE_LOG_EVENTS=1.
  private let log: EventLog? =
    ProcessInfo.processInfo.environment["CLAUDETTE_LOG_EVENTS"] != nil
    ? EventLog(url: EventLog.defaultURL) : nil

  /// Starts the feed server; returns a menu-friendly status line.
  func start() -> String {
    pointer.onMove = { [stage] p, flags in stage.pointerMoved(p, modifiers: flags) }
    pointer.start()
    caret.onCaret = { [stage] p in stage.caretMoved(p) }
    settings.onChange = { [weak self, stage] s in
      stage.settingsChanged()
      self?.updateCaretTracking()
    }
    updateCaretTracking()
    timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
      self?.tick()
    }
    _ = stage
    _ = hud
    stage.settingsChanged()  // applies a saved Focus mode and size right away
    // The model is only touched on the main queue; the compiler cannot see that.
    nonisolated(unsafe) weak var model = self
    let server = FeedServer(port: Self.feedPort) { message in
      DispatchQueue.main.async { model?.handle(message) }
    }
    do {
      try server.start()
      self.server = server
      return "Listening on 127.0.0.1:\(server.boundPort ?? Self.feedPort)"
    } catch {
      return "Feed unavailable: \(error)"
    }
  }

  private func updateCaretTracking() {
    let s = settings.settings
    if s.dodgeEnabled && s.dodgeTextCursor {
      if !caretAsked && !AXIsProcessTrusted() {
        caretAsked = true
        CaretTracker.requestAccess()
      }
      caret.start()
    } else {
      caret.stop()
    }
  }

  func stop() {
    caret.stop()
    server?.stop()
    pointer.stop()
    timer?.invalidate()
  }

  func handle(_ message: FeedMessage) {
    log?.append(message.logLine(at: Date()))
    switch message {
    case .hook(let event):
      if event.name == "StopFailure", event.errorType == "rate_limit" {
        limits.ingestRateLimitFailure(resetsAt: nil)
      } else if event.name == "PostToolUse" {
        limits.noteSuccessfulWork()  // real work succeeded: an inferred limit is over
      }
      stage.apply(store.apply(event), sessions: store.sessions)
      hud.refresh()
    case .status(let data):
      guard let payload = try? StatusPayload.decode(data) else { return }
      limits.ingest(payload)
      stage.apply(store.applyStatus(payload), sessions: store.sessions)
      hud.refresh()
    }
  }

  /// The menubar "Finish stale sessions": sessions silent for a minute are treated as ended.
  func finishStaleSessions() {
    stage.apply(store.finishStale(), sessions: store.sessions)
    hud.refresh()
  }

  private func tick() {
    limits.tick()
    stage.apply(store.tick(), sessions: store.sessions)
    hud.refresh()
  }

  /// Debug helper: feeds limit readings (percent used; reset in seconds) as a status payload.
  func simulateLimits(
    five: Double?, fiveResetIn: TimeInterval = 2 * 3600 + 41 * 60, seven: Double?,
    sevenResetIn: TimeInterval = 3 * 86400
  ) {
    let now = Date()
    let payload = StatusPayload(
      sessionID: "debug-limits", cwd: nil, modelDisplayName: nil, contextUsedPercentage: nil,
      totalCostUSD: nil,
      fiveHour: five.flatMap {
        LimitWindow(usedPercentage: $0, resetsAt: now.addingTimeInterval(fiveResetIn))
      },
      sevenDay: seven.flatMap {
        LimitWindow(usedPercentage: $0, resetsAt: now.addingTimeInterval(sevenResetIn))
      })
    limits.ingest(payload)
    hud.refresh()
  }

  /// Debug helper: acts out one named scene on session `debug-1` (see `scenes`).
  static let scenes = [
    "read", "search", "edit", "write", "shell", "longshell", "bgshell", "web", "skill", "mcp",
    "todo", "plan", "other", "subagent", "approval", "question", "err-api", "err-auth",
    "err-billing", "err-limit", "recover", "compact", "done", "context",
  ]

  private var debugToolCount = 0

  func simulateScene(_ name: String) {
    let s = "\"session_id\":\"debug-1\""
    func pre(_ tool: String, _ id: String, _ input: String) -> String {
      // A fresh tool_use_id each time, so repeating a scene is a new tool call on the same item.
      debugToolCount += 1
      return
        "{\"hook_event_name\":\"PreToolUse\",\(s),\"tool_name\":\"\(tool)\",\"tool_use_id\":\"\(id)-\(debugToolCount)\",\"tool_input\":\(input)}"
    }
    func ev(_ n: String, _ extra: String = "") -> String {
      "{\"hook_event_name\":\"\(n)\",\(s)\(extra.isEmpty ? "" : "," + extra)}"
    }
    let json: String
    switch name {
    case "read": json = pre("Read", "r1", "{\"file_path\":\"/proj/src/auth.ts\"}")
    case "search": json = pre("Grep", "g1", "{\"pattern\":\"foo\"}")
    case "edit": json = pre("Edit", "e1", "{\"file_path\":\"/proj/src/login.swift\"}")
    case "write": json = pre("Write", "w1", "{\"file_path\":\"/proj/README.md\"}")
    case "shell": json = pre("Bash", "b1", "{\"command\":\"ls\"}")
    case "longshell": json = pre("Bash", "b2", "{\"command\":\"sleep 99\"}")
    case "bgshell":
      json = pre("Bash", "b3", "{\"command\":\"npm run dev\",\"run_in_background\":true}")
    case "web": json = pre("WebFetch", "f1", "{}")
    case "skill": json = pre("Skill", "k1", "{\"skill\":\"superpowers:brainstorming\"}")
    case "mcp": json = pre("mcp__github__create_issue", "m1", "{}")
    case "todo": json = pre("TodoWrite", "t1", "{}")
    case "plan": json = pre("ExitPlanMode", "p1", "{}")
    case "other": json = pre("Brand_new", "o1", "{}")
    case "subagent": json = ev("SubagentStart", "\"agent_id\":\"a1\",\"agent_type\":\"Explore\"")
    case "approval": json = ev("PermissionRequest", "\"tool_name\":\"Write\"")
    case "question": json = ev("Notification", "\"notification_type\":\"elicitation_dialog\"")
    case "err-api": json = ev("StopFailure", "\"error_type\":\"server_error\"")
    case "err-auth": json = ev("StopFailure", "\"error_type\":\"authentication_failed\"")
    case "err-billing": json = ev("StopFailure", "\"error_type\":\"billing_error\"")
    case "err-limit": json = ev("StopFailure", "\"error_type\":\"rate_limit\"")
    case "recover": json = ev("UserPromptSubmit")
    case "compact": json = ev("PreCompact")
    case "done": json = ev("Stop")
    case "context":
      let p = StatusPayload(
        sessionID: "debug-1", cwd: nil, modelDisplayName: "Opus", contextUsedPercentage: 62,
        totalCostUSD: nil, fiveHour: nil, sevenDay: nil)
      stage.apply(store.applyStatus(p), sessions: store.sessions)
      return
    default: return
    }
    inject(json)
  }

  /// Debug helper: feeds a hook event as if it came from Claude Code.
  func inject(_ json: String) {
    guard let event = try? HookEvent.decode(Data(json.utf8)) else { return }
    handle(.hook(event))
  }
}
