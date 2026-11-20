import AppKit
import ClaudetteCore
import ServiceManagement
import SwiftUI

/// Where Claudette reads and writes outside its own bundle. `CLAUDETTE_HOME` redirects everything
/// (used for testing without touching the real `~/.claude`).
enum Paths {
  static var home: URL {
    if let h = ProcessInfo.processInfo.environment["CLAUDETTE_HOME"], !h.isEmpty {
      return URL(fileURLWithPath: h)
    }
    return FileManager.default.homeDirectoryForCurrentUser
  }
  static var claudeSettings: URL { home.appendingPathComponent(".claude/settings.json") }
  static var pluginDir: URL { home.appendingPathComponent(".claude/skills/claudette") }
  static var stateDir: URL { home.appendingPathComponent("Library/Application Support/Claudette") }
  static var wrapper: String { stateDir.appendingPathComponent("claudette-statusline.sh").path }
}

/// Settings plus the install state of the two Claude Code hooks-ups. UI only: all file edits are
/// done by the tested installers in ClaudetteCore.
final class SettingsModel: ObservableObject {
  let store: SettingsStore
  private let activeProjectDirs: () -> [String]
  @Published var pluginInstalled = false
  @Published var statusLine = InstallState.notInstalled
  @Published var message = ""

  init(store: SettingsStore, activeProjectDirs: @escaping () -> [String]) {
    self.store = store
    self.activeProjectDirs = activeProjectDirs
    refresh()
  }

  var settings: ClaudetteSettings { store.settings }

  func set(_ change: @escaping (inout ClaudetteSettings) -> Void) {
    store.update(change)
    objectWillChange.send()
  }

  func refresh() {
    pluginInstalled = PluginInstaller.isInstalled(pluginDir: Paths.pluginDir)
    var state = StatusLineInstaller.status(
      settingsURL: Paths.claudeSettings, wrapperPath: Paths.wrapper, projectSettingsURL: nil)
    if state == .installed {
      for dir in activeProjectDirs() {
        for name in ["settings.json", "settings.local.json"] {
          let url = URL(fileURLWithPath: dir).appendingPathComponent(".claude/\(name)")
          if StatusLineInstaller.status(
            settingsURL: Paths.claudeSettings, wrapperPath: Paths.wrapper, projectSettingsURL: url)
            == .overriddenByProject
          {
            state = .overriddenByProject
          }
        }
      }
    }
    statusLine = state
  }

  private func confirm(_ title: String, _ text: String, button: String) -> Bool {
    // Test hook: only honoured when Claudette is redirected to a sandbox home (never your real one).
    let env = ProcessInfo.processInfo.environment
    if env["CLAUDETTE_HOME"] != nil, env["CLAUDETTE_DEBUG_AUTOCONFIRM"] != nil { return true }
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = text
    alert.addButton(withTitle: button)
    alert.addButton(withTitle: "Cancel")
    NSApp.activate(ignoringOtherApps: true)
    return alert.runModal() == .alertFirstButtonReturn
  }

  func installPlugin() {
    let dir = Paths.pluginDir.path
    guard
      confirm(
        "Install the Claude Code plugin?",
        "Claudette will create the folder\n\(dir)\n\nIt only contains hook settings that send activity (tool names, file names, session ids) to Claudette on this Mac (127.0.0.1). New Claude Code sessions pick it up.",
        button: "Install")
    else { return }
    do {
      try PluginInstaller.install(pluginDir: Paths.pluginDir, port: Int(AppModel.feedPort))
      message = "Plugin installed. Start a new Claude Code session to use it."
    } catch {
      message = "Could not install the plugin: \(error)"
    }
    refresh()
  }

  func uninstallPlugin() {
    do {
      try PluginInstaller.uninstall(pluginDir: Paths.pluginDir)
      message = "Plugin removed."
    } catch {
      message = "Could not remove the plugin: \(error)"
    }
    refresh()
  }

  func installStatusLine() {
    let file = Paths.claudeSettings.path
    guard
      confirm(
        "Add Claudette to your status line?",
        "Claudette will edit\n\(file)\n\nIt keeps a backup, keeps your existing status line command working (it is wrapped, not replaced), and refuses to touch the file if it is not valid JSON. Uninstalling restores it.",
        button: "Edit settings")
    else { return }
    do {
      let outcome = try StatusLineInstaller.install(
        settingsURL: Paths.claudeSettings, wrapperPath: Paths.wrapper, stateDir: Paths.stateDir,
        port: Int(AppModel.feedPort))
      message = outcome == .installed ? "Status line installed." : "Already installed."
    } catch InstallError.settingsNotValidJSON {
      message = "Your settings.json is not valid JSON, so Claudette left it alone."
    } catch {
      message = "Could not edit settings: \(error)"
    }
    refresh()
  }

  func uninstallStatusLine() {
    do {
      switch try StatusLineInstaller.uninstall(
        settingsURL: Paths.claudeSettings, wrapperPath: Paths.wrapper, stateDir: Paths.stateDir)
      {
      case .restored: message = "Status line restored."
      case .leftAlone: message = "Your status line was changed since install, so it was left alone."
      case .notInstalled: message = "Nothing to remove."
      }
    } catch {
      message = "Could not restore settings: \(error)"
    }
    refresh()
  }

  var launchAtLogin: Bool { SMAppService.mainApp.status == .enabled }

  func setLaunchAtLogin(_ on: Bool) {
    do {
      if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
      set { $0.launchAtLogin = on }
    } catch {
      message = "Launch at login failed: \(error.localizedDescription)"
      objectWillChange.send()
    }
  }
}

struct SettingsView: View {
  @ObservedObject var model: SettingsModel

  private func binding<T>(_ keyPath: WritableKeyPath<ClaudetteSettings, T>) -> Binding<T> {
    Binding(
      get: { model.settings[keyPath: keyPath] },
      set: { value in model.set { $0[keyPath: keyPath] = value } })
  }

  var body: some View {
    Form {
      Section("Size") {
        HStack {
          Slider(value: binding(\.scale), in: 0.5...2.0, step: 0.05)
          Text("\(Int(model.settings.scale * 100))%").monospacedDigit().frame(width: 48)
        }
      }
      Section("Pointer") {
        Toggle("Fade when the pointer is over her", isOn: binding(\.hoverFadeEnabled))
        if model.settings.hoverFadeEnabled {
          HStack {
            Text("Opacity")
            Slider(value: binding(\.hoverFadeOpacity), in: 0.2...0.3)
            Text("\(Int(model.settings.hoverFadeOpacity * 100))%").monospacedDigit().frame(
              width: 48)
          }
        }
        Toggle("Dodge the pointer", isOn: binding(\.dodgeEnabled))
        if model.settings.dodgeEnabled {
          HStack {
            Text("Shyness")
            Slider(value: binding(\.shyness), in: 0...1)
          }
          Text(
            "Hold Option while moving the pointer to keep her still so you can grab and drag her."
          )
          .font(.caption).foregroundStyle(.secondary)
        }
      }
      Section("Comfort") {
        Toggle("Privacy mode (hide file, project and server names)", isOn: binding(\.privacyMode))
        Toggle("Focus mode (hide Claudette)", isOn: binding(\.focusMode))
        Toggle("Reduce motion", isOn: binding(\.reduceMotion))
        Toggle(
          "Launch at login",
          isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
      }
      Section("Claude Code") {
        HStack {
          Text(model.pluginInstalled ? "Plugin installed" : "Plugin not installed")
          Spacer()
          if model.pluginInstalled {
            Button("Remove") { model.uninstallPlugin() }
          } else {
            Button("Install…") { model.installPlugin() }
          }
        }
        HStack {
          VStack(alignment: .leading) {
            switch model.statusLine {
            case .installed: Text("Usage limits connected")
            case .notInstalled: Text("Usage limits not connected")
            case .overriddenByProject:
              Text("A project status line overrides Claudette").foregroundStyle(.orange)
            }
          }
          Spacer()
          if model.statusLine == .notInstalled {
            Button("Connect…") { model.installStatusLine() }
          } else {
            Button("Disconnect") { model.uninstallStatusLine() }
          }
        }
        if !model.message.isEmpty {
          Text(model.message).font(.caption).foregroundStyle(.secondary)
        }
      }
    }
    .formStyle(.grouped)
    .frame(width: 460, height: 740)
    .onAppear { model.refresh() }
  }
}

/// Owns the single settings window.
final class SettingsWindowController {
  private var window: NSWindow?
  private let model: SettingsModel

  init(model: SettingsModel) {
    self.model = model
  }

  func show() {
    if window == nil {
      let hosting = NSHostingController(rootView: SettingsView(model: model))
      let w = NSWindow(contentViewController: hosting)
      w.title = "Claudette Settings"
      w.styleMask = [.titled, .closable]
      w.isReleasedWhenClosed = false
      w.setContentSize(NSSize(width: 460, height: 740))
      window = w
    }
    model.refresh()
    window?.center()
    NSApp.activate(ignoringOtherApps: true)
    window?.makeKeyAndOrderFront(nil)
  }
}
