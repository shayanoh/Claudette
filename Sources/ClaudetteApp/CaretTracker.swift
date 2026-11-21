import AppKit
import ApplicationServices
import ClaudetteCore

/// Finds the text caret of whatever app has keyboard focus, through the Accessibility API (the
/// same source the Caps Lock and input-language tips use). Polls off the main thread: a hung app
/// must never stall the overlay. Needs Accessibility permission; without it nothing is reported.
final class CaretTracker {
  /// The caret's centre in global screen coordinates (bottom-left origin), or nil when there is none.
  var onCaret: ((CGPoint?) -> Void)?
  private var timer: DispatchSourceTimer?
  private let queue = DispatchQueue(label: "claudette.caret", qos: .utility)

  /// Shows the system Accessibility prompt if access has not been granted yet.
  static func requestAccess() {
    let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
    _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
  }

  func start() {
    guard timer == nil else { return }
    let t = DispatchSource.makeTimerSource(queue: queue)
    t.schedule(deadline: .now(), repeating: .milliseconds(300))
    t.setEventHandler { [weak self] in
      let p = Self.caret()
      DispatchQueue.main.async { self?.onCaret?(p) }
    }
    t.resume()
    timer = t
  }

  func stop() {
    timer?.cancel()
    timer = nil
  }

  private static func caret() -> CGPoint? {
    guard AXIsProcessTrusted() else { return nil }
    if let p = zellijCaret() { return p }
    let system = AXUIElementCreateSystemWide()
    AXUIElementSetMessagingTimeout(system, 0.15)
    var focused: CFTypeRef?
    if AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused)
      != .success, let app = NSWorkspace.shared.frontmostApplication
    {
      // The system-wide query fails for some apps; asking the frontmost app directly can work.
      let appElement = AXUIElementCreateApplication(app.processIdentifier)
      AXUIElementSetMessagingTimeout(appElement, 0.15)
      focused = nil
      _ = AXUIElementCopyAttributeValue(
        appElement, kAXFocusedUIElementAttribute as CFString, &focused)
    }
    guard let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
    let element = focused as! AXUIElement  // type checked just above
    var pid: pid_t = 0
    AXUIElementGetPid(element, &pid)
    guard pid != ProcessInfo.processInfo.processIdentifier else { return nil }
    AXUIElementSetMessagingTimeout(element, 0.15)

    var value: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &value)
        == .success, let value, CFGetTypeID(value) == AXValueGetTypeID()
    else { return nil }
    var range = CFRange()
    guard AXValueGetValue(value as! AXValue, .cfRange, &range), range.location >= 0 else {
      return nil
    }
    let end = range.location + range.length
    // Many apps return an empty rect for an empty range: fall back to the character after the
    // caret, then the one before it.
    for (location, length) in [(end, 0), (end, 1), (end - 1, 1)] where location >= 0 {
      if let rect = bounds(element, CFRange(location: location, length: length)) {
        let screenHeight = NSScreen.screens.first?.frame.height ?? 0
        let x = length == 1 && location == end - 1 ? rect.maxX : rect.minX
        return CGPoint(x: x, y: screenHeight - rect.midY)  // AX is top-left origin
      }
    }
    return nil
  }

  private static func bounds(_ element: AXUIElement, _ range: CFRange) -> CGRect? {
    var r = range
    guard let arg = AXValueCreate(.cfRange, &r) else { return nil }
    var out: CFTypeRef?
    guard
      AXUIElementCopyParameterizedAttributeValue(
        element, kAXBoundsForRangeParameterizedAttribute as CFString, arg, &out) == .success,
      let out, CFGetTypeID(out) == AXValueGetTypeID()
    else { return nil }
    var rect = CGRect.zero
    guard AXValueGetValue(out as! AXValue, .cgRect, &rect), rect.height > 0, rect.height < 400,
      rect.origin.x.isFinite, rect.origin.y.isFinite
    else { return nil }
    return rect
  }

  // MARK: Zellij

  /// Terminals that can host Zellij; their own Accessibility tree has no caret.
  private static let terminals: Set<String> = [
    "dev.zellij.Zellij", "com.mitchellh.ghostty", "com.apple.Terminal", "com.googlecode.iterm2",
    "net.kovidgoyal.kitty", "org.alacritty", "com.github.wez.wezterm",
  ]
  private static let zellijPaths = [
    "/usr/local/bin/zellij", "/opt/homebrew/bin/zellij",
    NSHomeDirectory() + "/Applications/Zellij.app/Contents/MacOS/zellij",
  ]
  private static var session: (name: String, at: Date)?  // only touched on `queue`

  private static func zellijCaret() -> CGPoint? {
    guard let app = NSWorkspace.shared.frontmostApplication,
      let id = app.bundleIdentifier, terminals.contains(id),
      let exe = zellijPaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) })
    else { return nil }
    let ax = AXUIElementCreateApplication(app.processIdentifier)
    AXUIElementSetMessagingTimeout(ax, 0.15)
    var w: CFTypeRef?
    var f: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(ax, kAXFocusedWindowAttribute as CFString, &w) == .success,
      let w, CFGetTypeID(w) == AXUIElementGetTypeID(),
      AXUIElementCopyAttributeValue(w as! AXUIElement, "AXFrame" as CFString, &f) == .success,
      let f, CFGetTypeID(f) == AXValueGetTypeID()
    else { return nil }
    var frame = CGRect.zero
    guard AXValueGetValue(f as! AXValue, .cgRect, &frame) else { return nil }

    if session == nil || Date().timeIntervalSince(session!.at) > 10 {
      let list = run(exe, ["list-sessions", "--no-formatting"]) ?? ""
      let live = list.split(separator: "\n").first { !$0.contains("EXITED") }
      session = (String(live?.split(separator: " ").first ?? ""), Date())
    }
    guard let name = session?.name, !name.isEmpty,
      let panes = run(exe, ["--session", name, "action", "list-panes", "-a", "-t", "--json"]),
      let tabs = run(exe, ["--session", name, "action", "list-tabs", "-a", "--json"]),
      let top = ZellijCaret.point(
        panes: Data(panes.utf8), tabs: Data(tabs.utf8), window: frame)
    else { return nil }
    let screenHeight = NSScreen.screens.first?.frame.height ?? 0
    return CGPoint(x: top.x, y: screenHeight - top.y)  // AX is top-left origin
  }

  /// Runs a short command with a 1 s limit; nil on any failure.
  private static func run(_ exe: String, _ args: [String]) -> String? {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: exe)
    p.arguments = args
    p.environment = [:]
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = FileHandle.nullDevice
    guard (try? p.run()) != nil else { return nil }
    let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
    DispatchQueue.global().asyncAfter(deadline: .now() + 1, execute: killer)
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    killer.cancel()
    return p.terminationStatus == 0 ? String(data: data, encoding: .utf8) : nil
  }
}
