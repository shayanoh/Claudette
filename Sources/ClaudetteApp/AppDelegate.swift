import AppKit
import ClaudetteCore

final class AppDelegate: NSObject, NSApplicationDelegate {
  static let feedPort: UInt16 = 47631

  private var statusItem: NSStatusItem?
  private var server: FeedServer?
  private let log = EventLog(url: EventLog.defaultURL)

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    item.button?.title = "C"
    let menu = NSMenu()
    let feed = NSMenuItem(title: "Starting feed…", action: nil, keyEquivalent: "")
    menu.addItem(feed)
    menu.addItem(.separator())
    menu.addItem(
      NSMenuItem(
        title: "Quit Claudette", action: #selector(NSApplication.terminate(_:)),
        keyEquivalent: "q"))
    item.menu = menu
    statusItem = item

    let log = self.log
    let server = FeedServer(port: Self.feedPort) { message in
      log.append(message.logLine(at: Date()))
    }
    do {
      try server.start()
      self.server = server
      feed.title = "Listening on 127.0.0.1:\(server.boundPort ?? Self.feedPort)"
    } catch {
      feed.title = "Feed unavailable: \(error)"
    }
  }

  func applicationWillTerminate(_ notification: Notification) {
    server?.stop()
  }
}
