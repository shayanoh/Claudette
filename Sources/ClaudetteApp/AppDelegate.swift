import AppKit
import ClaudetteCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
  static let feedPort = AppModel.feedPort

  private var statusItem: NSStatusItem?
  private let model = AppModel()
  private var feedStatus = "Starting feed…"
  private var debugCount = 0
  private lazy var settingsModel = SettingsModel(
    store: model.settings,
    activeProjectDirs: { [model] in model.store.sessions.values.compactMap(\.cwd) })
  private lazy var settingsWindow = SettingsWindowController(model: settingsModel)
  private let debugMenus = ProcessInfo.processInfo.environment["CLAUDETTE_DEBUG"] != nil

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    item.button?.title = "C"
    let menu = NSMenu()
    menu.delegate = self
    item.menu = menu
    statusItem = item
    model.hud.onGlyph = { [weak self] image in self?.statusItem?.button?.image = image }
    feedStatus = model.start()
    runDebugHooks()
  }

  // MARK: Menu

  func menuNeedsUpdate(_ menu: NSMenu) {
    menu.removeAllItems()
    let privacy = model.settings.settings.privacyMode
    let sessions = model.store.sessions.values.sorted { $0.startedAt < $1.startedAt }
    if sessions.isEmpty {
      menu.addItem(withTitle: "No Claude Code sessions", action: nil, keyEquivalent: "")
    }
    for s in sessions {
      let name =
        privacy
        ? "•••" : (s.cwd.map { ($0 as NSString).lastPathComponent } ?? String(s.id.prefix(8)))
      let item = NSMenuItem(
        title: "\(name) · \(Self.phaseText(s.phase))", action: nil, keyEquivalent: "")
      item.isEnabled = false
      menu.addItem(item)
    }
    menu.addItem(.separator())
    let focus = NSMenuItem(title: "Focus mode", action: #selector(toggleFocus), keyEquivalent: "")
    focus.target = self
    focus.state = model.settings.settings.focusMode ? .on : .off
    menu.addItem(focus)
    let settings = NSMenuItem(
      title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
    settings.target = self
    menu.addItem(settings)
    let feed = NSMenuItem(title: feedStatus, action: nil, keyEquivalent: "")
    feed.isEnabled = false
    menu.addItem(feed)
    if debugMenus { addDebugItems(to: menu) }
    menu.addItem(.separator())
    menu.addItem(
      NSMenuItem(
        title: "Quit Claudette", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"
      ))
  }

  static func phaseText(_ phase: SessionPhase) -> String {
    switch phase {
    case .sleeping: return "asleep"
    case .idle: return "idle"
    case .working: return "working"
    case .needsApproval: return "needs approval"
    case .hasQuestion: return "has a question"
    case .error(let kind): return PuppetNode.errorText(kind)
    }
  }

  @objc private func openSettings() { settingsWindow.show() }

  @objc private func toggleFocus() {
    model.settings.update { $0.focusMode.toggle() }
  }

  // MARK: Debug helpers (CLAUDETTE_DEBUG=1 adds the menus; env vars script them)

  private func addDebugItems(to menu: NSMenu) {
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
      ("Weekly limit (week 100%)", 5),
    ] {
      let i = NSMenuItem(title: title, action: #selector(simulate(_:)), keyEquivalent: "")
      i.target = self
      i.tag = tag
      simMenu.addItem(i)
    }
    sim.submenu = simMenu
    menu.addItem(sim)
  }

  private func runDebugHooks() {
    let env = ProcessInfo.processInfo.environment
    if let n = env["CLAUDETTE_DEBUG_SPAWN"], let count = Int(n) {
      for _ in 0..<max(0, min(count, 12)) { debugAdd() }
    }
    if let seq = env["CLAUDETTE_DEBUG_SCENES"] {
      // e.g. "read,shell,mcp": one scene every 0.8 seconds starting after 2 seconds
      for (i, name) in seq.split(separator: ",").enumerated() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2 + Double(i) * 0.8) { [weak self] in
          self?.model.simulateScene(String(name))
        }
      }
    }
    if let seq = env["CLAUDETTE_DEBUG_LIMITS"] {
      // e.g. "fresh,low,limit,lifted": one step every 4 seconds starting after 2 seconds
      for (i, step) in seq.split(separator: ",").enumerated() {
        let tag =
          ["fresh": 0, "low": 1, "limit": 2, "lifted": 3, "unknown": 4, "weeklimit": 5][
            String(step)] ?? 4
        DispatchQueue.main.asyncAfter(deadline: .now() + 2 + Double(i) * 4) { [weak self] in
          let item = NSMenuItem()
          item.tag = tag
          self?.simulate(item)
        }
      }
    }
    if env["CLAUDETTE_DEBUG_DRAGTEST"] != nil {
      DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [model] in
        let f = NSScreen.main?.frame ?? .zero
        model.stage.debugDragFirst(to: CGPoint(x: f.midX - 200, y: f.midY))
      }
    }
    if let steps = env["CLAUDETTE_DEBUG_INSTALL"] {
      // e.g. "plugin,statusline" or "unplugin,unstatusline" (needs CLAUDETTE_HOME + AUTOCONFIRM)
      DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
        guard let self else { return }
        for step in steps.split(separator: ",") {
          switch step {
          case "plugin": self.settingsModel.installPlugin()
          case "statusline": self.settingsModel.installStatusLine()
          case "unplugin": self.settingsModel.uninstallPlugin()
          case "unstatusline": self.settingsModel.uninstallStatusLine()
          default: break
          }
          FileHandle.standardError.write(
            Data("install step \(step): \(self.settingsModel.message)\n".utf8))
        }
      }
    }
    if env["CLAUDETTE_DEBUG_SETTINGS"] != nil {
      DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.openSettings() }
    }
  }

  @objc private func simulateScene(_ sender: NSMenuItem) { model.simulateScene(sender.title) }

  @objc private func simulate(_ sender: NSMenuItem) {
    switch sender.tag {
    case 0: model.simulateLimits(five: 12, seven: 18)
    case 1: model.simulateLimits(five: 88, fiveResetIn: 47 * 60, seven: 71)
    case 2: model.simulateLimits(five: 100, fiveResetIn: 3600, seven: 71)
    case 3: model.simulateLimits(five: 3, seven: 71)
    case 5: model.simulateLimits(five: 20, seven: 100, sevenResetIn: 2 * 86400 + 3600)
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
