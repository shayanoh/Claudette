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
    settings.onChange = { [stage] _ in stage.settingsChanged() }
    timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
      self?.tick()
    }
    _ = stage
    let server = FeedServer(port: Self.feedPort) { [weak self] message in
      DispatchQueue.main.async { self?.handle(message) }
    }
    do {
      try server.start()
      self.server = server
      return "Listening on 127.0.0.1:\(server.boundPort ?? Self.feedPort)"
    } catch {
      return "Feed unavailable: \(error)"
    }
  }

  func stop() {
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
      }
      stage.apply(store.apply(event))
    case .status(let data):
      guard let payload = try? StatusPayload.decode(data) else { return }
      limits.ingest(payload)
      stage.apply(store.applyStatus(payload))
    }
  }

  private func tick() {
    limits.tick()
    stage.apply(store.tick())
  }

  /// Debug helper: feeds a hook event as if it came from Claude Code.
  func inject(_ json: String) {
    guard let event = try? HookEvent.decode(Data(json.utf8)) else { return }
    handle(.hook(event))
  }
}
