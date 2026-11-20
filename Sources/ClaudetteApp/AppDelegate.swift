import AppKit
import ClaudetteCore

final class AppDelegate: NSObject, NSApplicationDelegate {
  static let feedPort: UInt16 = 47631

  private var statusItem: NSStatusItem?
  private var server: FeedServer?
  private let log = EventLog(url: EventLog.defaultURL)
  private lazy var overlay = OverlayController()

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    item.button?.title = "C"
    let menu = NSMenu()
    let feed = NSMenuItem(title: "Starting feed…", action: nil, keyEquivalent: "")
    menu.addItem(feed)
    menu.addItem(.separator())
    let spawn = NSMenuItem(
      title: "Spawn test Claudette", action: #selector(spawnTest), keyEquivalent: "")
    spawn.target = self
    menu.addItem(spawn)
    let clear = NSMenuItem(
      title: "Remove test Claudettes", action: #selector(clearTests), keyEquivalent: "")
    clear.target = self
    menu.addItem(clear)
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
    if ProcessInfo.processInfo.environment["CLAUDETTE_DEBUG_SPAWN"] != nil {
      spawnTest()
      spawnTest()
    }
    do {
      try server.start()
      self.server = server
      feed.title = "Listening on 127.0.0.1:\(server.boundPort ?? Self.feedPort)"
    } catch {
      feed.title = "Feed unavailable: \(error)"
    }
  }

  @objc private func spawnTest() {
    guard let scene = overlay.mainScene else { return }
    let puppet = PuppetNode()
    puppet.name = "test-puppet"
    let n = scene.children.filter { $0.name == "test-puppet" }.count
    puppet.position = CGPoint(x: 220 + CGFloat(n) * 260, y: 120)
    scene.addChild(puppet)
    puppet.wake()
  }

  @objc private func clearTests() {
    overlay.mainScene?.children.filter { $0.name == "test-puppet" }.forEach {
      $0.removeFromParent()
    }
  }

  func applicationWillTerminate(_ notification: Notification) {
    server?.stop()
  }
}
