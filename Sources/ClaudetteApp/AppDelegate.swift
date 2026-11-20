import AppKit
import ClaudetteCore

final class AppDelegate: NSObject, NSApplicationDelegate {
  static let feedPort = AppModel.feedPort

  private var statusItem: NSStatusItem?
  private let model = AppModel()
  private var debugCount = 0

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    item.button?.title = "C"
    let menu = NSMenu()
    let feed = NSMenuItem(title: "Starting feed…", action: nil, keyEquivalent: "")
    menu.addItem(feed)
    menu.addItem(.separator())
    for (title, action) in [
      ("Debug: add session", #selector(debugAdd)), ("Debug: end last session", #selector(debugEnd)),
    ] {
      let i = NSMenuItem(title: title, action: action, keyEquivalent: "")
      i.target = self
      menu.addItem(i)
    }
    menu.addItem(.separator())
    menu.addItem(
      NSMenuItem(
        title: "Quit Claudette", action: #selector(NSApplication.terminate(_:)),
        keyEquivalent: "q"))
    item.menu = menu
    statusItem = item

    feed.title = model.start()
    if let n = ProcessInfo.processInfo.environment["CLAUDETTE_DEBUG_SPAWN"], let count = Int(n) {
      for _ in 0..<max(0, min(count, 12)) { debugAdd() }
    }
    if ProcessInfo.processInfo.environment["CLAUDETTE_DEBUG_DRAGTEST"] != nil {
      DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [model] in
        let f = NSScreen.main?.frame ?? .zero
        model.stage.debugDragFirst(to: CGPoint(x: f.midX - 200, y: f.midY))
      }
    }
  }

  @objc private func debugAdd() {
    debugCount += 1
    model.inject(
      #"{"hook_event_name":"SessionStart","session_id":"debug-\#(debugCount)","cwd":"/tmp/debug"}"#)
  }

  @objc private func debugEnd() {
    guard debugCount > 0 else { return }
    model.inject(#"{"hook_event_name":"SessionEnd","session_id":"debug-\#(debugCount)"}"#)
    debugCount -= 1
  }

  func applicationWillTerminate(_ notification: Notification) {
    model.stop()
  }
}
