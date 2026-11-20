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
  /// The installed plugin still uses the old `http` hooks, which report errors when Claudette is closed.
  @Published var pluginNeedsUpdate = false
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
    pluginNeedsUpdate = PluginInstaller.isLegacy(pluginDir: Paths.pluginDir)
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

  /// Rewrites our own plugin folder with the silent command hooks (never touches anything else).
  func updatePlugin() {
    guard
      confirm(
        "Update the Claude Code plugin?",
        "The installed plugin reports an error in Claude Code whenever Claudette is not running. The update replaces its hooks with a small script that fails silently.\n\nOnly the folder\n\(Paths.pluginDir.path)\nis rewritten. New Claude Code sessions pick it up.",
        button: "Update")
    else { return }
    do {
      try PluginInstaller.install(pluginDir: Paths.pluginDir, port: Int(AppModel.feedPort))
      message = "Plugin updated. Start a new Claude Code session to use it."
    } catch {
      message = "Could not update the plugin: \(error)"
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

  private static func percent(_ v: Double) -> String { "\(Int((v * 100).rounded()))%" }

  var body: some View {
    let s = model.settings
    Form {
      Section {
        SliderRow(
          title: "Size", caption: "How big Claudette is on screen.",
          value: binding(\.scale), range: 0.5...2.0,
          minLabel: "50%", maxLabel: "200%", readout: Self.percent(s.scale))
        Toggle(isOn: binding(\.reduceMotion)) {
          Text("Reduce motion")
          Text("Calmer animation with less bouncing and fewer effects.")
        }
      } header: {
        SectionHeader(title: "Appearance", symbol: "paintbrush")
      }

      Section {
        Toggle(isOn: binding(\.hoverFadeEnabled)) {
          Text("Fade under the pointer")
          Text("She turns see-through while the pointer is over her, so she never hides text.")
        }
        SliderRow(
          title: "Faded opacity", caption: "How visible she stays while faded.",
          value: binding(\.hoverFadeOpacity), range: 0.2...0.3,
          minLabel: "20%", maxLabel: "30%", readout: Self.percent(s.hoverFadeOpacity)
        )
        .disabled(!s.hoverFadeEnabled)
        Toggle(isOn: binding(\.dodgeEnabled)) {
          Text("Dodge the pointer")
          Text("She steps out of the way when the pointer comes close.")
        }
        SliderRow(
          title: "Shyness",
          caption: "How early she moves away. Hold Option to keep her still and drag her.",
          value: binding(\.shyness), range: 0...1,
          minLabel: "Bold", maxLabel: "Shy", readout: Self.percent(s.shyness)
        )
        .disabled(!s.dodgeEnabled)
      } header: {
        SectionHeader(title: "Pointer", symbol: "cursorarrow.rays")
      }

      Section {
        Toggle(isOn: binding(\.privacyMode)) {
          Text("Privacy mode")
          Text("Hide file, project and server names, for screen sharing.")
        }
        Toggle(isOn: binding(\.focusMode)) {
          Text("Focus mode")
          Text("Hide Claudette completely. The menubar icon still shows status.")
        }
        Toggle(
          isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) })
        ) {
          Text("Launch at login")
          Text("Start Claudette automatically when you log in.")
        }
      } header: {
        SectionHeader(title: "Privacy and comfort", symbol: "hand.raised")
      }

      Section {
        pluginRow
        statusLineRow
        if !model.message.isEmpty {
          Label(model.message, systemImage: "info.circle")
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      } header: {
        SectionHeader(title: "Claude Code connection", symbol: "link")
      } footer: {
        Text(
          "Both only talk to Claudette on this Mac. Start a new Claude Code session after a change."
        )
        .font(.footnote)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .formStyle(.grouped)
    .frame(minWidth: 460, idealWidth: 500, minHeight: 420, idealHeight: 680)
    .onAppear { model.refresh() }
  }

  @ViewBuilder private var pluginRow: some View {
    ConnectionRow(
      title: "Activity plugin",
      caption: "Lets Claudette see what Claude Code is doing.",
      state: model.pluginNeedsUpdate
        ? .warning("Needs update: reports errors while Claudette is closed")
        : model.pluginInstalled ? .good("Installed") : .off("Not installed")
    ) {
      if model.pluginNeedsUpdate {
        Button("Remove") { model.uninstallPlugin() }
        Button("Update…") { model.updatePlugin() }.buttonStyle(.borderedProminent)
      } else if model.pluginInstalled {
        Button("Remove") { model.uninstallPlugin() }
      } else {
        Button("Install…") { model.installPlugin() }.buttonStyle(.borderedProminent)
      }
    }
  }

  private var statusLineState: ConnectionState {
    switch model.statusLine {
    case .installed: return .good("Connected")
    case .notInstalled: return .off("Not connected")
    case .overriddenByProject:
      return .warning("A project status line overrides Claudette, so limits may not arrive")
    }
  }

  @ViewBuilder private var statusLineRow: some View {
    ConnectionRow(
      title: "Usage limits",
      caption: "Reads your 5-hour and weekly limits from the Claude Code status line.",
      state: statusLineState
    ) {
      if model.statusLine == .notInstalled {
        Button("Connect…") { model.installStatusLine() }.buttonStyle(.borderedProminent)
      } else {
        Button("Disconnect") { model.uninstallStatusLine() }
      }
    }
  }
}

/// Section title with an SF Symbol. New sections (clutter, cleanup) reuse it.
private struct SectionHeader: View {
  let title: String
  let symbol: String
  var body: some View {
    Label(title, systemImage: symbol).font(.headline).foregroundStyle(.primary)
  }
}

/// Title, live value, slider with range hints, and a one-line explanation.
private struct SliderRow: View {
  @Environment(\.isEnabled) private var isEnabled
  let title: String
  let caption: String
  let value: Binding<Double>
  let range: ClosedRange<Double>
  let minLabel: String
  let maxLabel: String
  let readout: String

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(alignment: .firstTextBaseline) {
        Text(title)
        Spacer()
        Text(readout).monospacedDigit().foregroundStyle(.secondary)
      }
      HStack(spacing: 8) {
        Text(minLabel).frame(minWidth: 32, alignment: .leading).accessibilityHidden(true)
        Slider(value: value, in: range) { Text(title) }
          .labelsHidden()
          .accessibilityValue(readout)
        Text(maxLabel).frame(minWidth: 32, alignment: .trailing).accessibilityHidden(true)
      }
      .font(.caption)
      .foregroundStyle(.secondary)
      Text(caption)
        .font(.callout)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .opacity(isEnabled ? 1 : 0.5)
    .padding(.vertical, 2)
  }
}

private enum ConnectionState {
  case good(String)
  case warning(String)
  case off(String)
  var text: String {
    switch self {
    case .good(let t), .warning(let t), .off(let t): return t
    }
  }
  var color: Color {
    switch self {
    case .good: return .green
    case .warning: return .orange
    case .off: return .secondary
    }
  }
  var symbol: String {
    switch self {
    case .good: return "checkmark.circle.fill"
    case .warning: return "exclamationmark.triangle.fill"
    case .off: return "circle.dashed"
    }
  }
}

/// One Claude Code hook-up: what it is, a coloured state, and its actions (primary last).
private struct ConnectionRow<Actions: View>: View {
  let title: String
  let caption: String
  let state: ConnectionState
  @ViewBuilder let actions: Actions

  var body: some View {
    HStack(alignment: .center, spacing: 12) {
      VStack(alignment: .leading, spacing: 3) {
        Text(title)
        Text(caption).font(.callout).foregroundStyle(.secondary)
        Label(state.text, systemImage: state.symbol)
          .font(.callout.weight(.medium))
          .foregroundStyle(state.color)
      }
      .fixedSize(horizontal: false, vertical: true)
      .accessibilityElement(children: .combine)
      Spacer(minLength: 8)
      HStack(spacing: 8) { actions }.fixedSize()
    }
    .padding(.vertical, 2)
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
      w.styleMask = [.titled, .closable, .resizable]
      w.isReleasedWhenClosed = false
      w.setContentSize(NSSize(width: 500, height: 680))
      window = w
    }
    model.refresh()
    window?.center()
    NSApp.activate(ignoringOtherApps: true)
    window?.makeKeyAndOrderFront(nil)
  }
}
