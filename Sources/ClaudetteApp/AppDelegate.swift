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
    let scn = NSMenuItem(title: "Debug: simulate scene", action: nil, keyEquivalent: "")
    let scnMenu = NSMenu()
    for name in AppModel.scenes {
      let i = NSMenuItem(title: name, action: #selector(simulateScene(_:)), keyEquivalent: "")
      i.target = self
      scnMenu.addItem(i)
    }
    scn.submenu = scnMenu
    menu.addItem(scn)
    let sim = NSMenuItem(title: "Debug: simulate limits", action: nil, keyEquivalent: "")
    let simMenu = NSMenu()
    for (title, tag) in [
      ("Fresh (5h 12%, week 18%)", 0), ("Low (5h 88%, week 71%)", 1), ("In limit (5h 100%)", 2),
      ("Lifted (5h 3%)", 3), ("Unknown (no data)", 4),
    ] {
      let i = NSMenuItem(title: title, action: #selector(simulate(_:)), keyEquivalent: "")
      i.target = self
      i.tag = tag
      simMenu.addItem(i)
    }
    sim.submenu = simMenu
    menu.addItem(sim)
    menu.addItem(.separator())
    menu.addItem(
      NSMenuItem(
        title: "Quit Claudette", action: #selector(NSApplication.terminate(_:)),
        keyEquivalent: "q"))
    item.menu = menu
    statusItem = item

    model.hud.onGlyph = { [weak self] image in self?.statusItem?.button?.image = image }
    feed.title = model.start()
    if let n = ProcessInfo.processInfo.environment["CLAUDETTE_DEBUG_SPAWN"], let count = Int(n) {
      for _ in 0..<max(0, min(count, 12)) { debugAdd() }
    }
    if let seq = ProcessInfo.processInfo.environment["CLAUDETTE_DEBUG_SCENES"] {
      // e.g. "read,shell,mcp": one scene every 0.8 seconds starting after 2 seconds
      for (i, name) in seq.split(separator: ",").enumerated() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2 + Double(i) * 0.8) { [weak self] in
          self?.model.simulateScene(String(name))
        }
      }
    }
    if let seq = ProcessInfo.processInfo.environment["CLAUDETTE_DEBUG_LIMITS"] {
      // e.g. "fresh,low,limit,lifted": one step every 4 seconds starting after 2 seconds
      for (i, step) in seq.split(separator: ",").enumerated() {
        let tag = ["fresh": 0, "low": 1, "limit": 2, "lifted": 3, "unknown": 4][String(step)] ?? 4
        DispatchQueue.main.asyncAfter(deadline: .now() + 2 + Double(i) * 4) { [weak self] in
          let item = NSMenuItem()
          item.tag = tag
          self?.simulate(item)
        }
      }
    }
    if ProcessInfo.processInfo.environment["CLAUDETTE_DEBUG_DRAGTEST"] != nil {
      DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [model] in
        let f = NSScreen.main?.frame ?? .zero
        model.stage.debugDragFirst(to: CGPoint(x: f.midX - 200, y: f.midY))
      }
    }
  }

  @objc private func simulateScene(_ sender: NSMenuItem) { model.simulateScene(sender.title) }

  @objc private func simulate(_ sender: NSMenuItem) {
    switch sender.tag {
    case 0: model.simulateLimits(five: 12, seven: 18)
    case 1: model.simulateLimits(five: 88, fiveResetIn: 47 * 60, seven: 71)
    case 2: model.simulateLimits(five: 100, fiveResetIn: 3600, seven: 71)
    case 3: model.simulateLimits(five: 3, seven: 71)
    default: break
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
