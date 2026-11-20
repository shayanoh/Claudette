import CryptoKit
import Foundation

public enum InstallError: Error, Equatable {
  case settingsNotValidJSON
}

public enum InstallOutcome: Equatable, Sendable { case installed, alreadyInstalled }
public enum UninstallOutcome: Equatable, Sendable { case restored, leftAlone, notInstalled }
public enum InstallState: Equatable, Sendable { case notInstalled, installed, overriddenByProject }

/// Wraps the user's `statusLine` command in a script that also forwards the payload to Claudette.
/// Only ever edits the settings file it is given, keeps a backup, and refuses invalid JSON.
public enum StatusLineInstaller {
  private static let backupName = "settings.backup"
  private static let existedName = "settings.existed"
  private static let originalName = "original-statusline.json"
  private static let hashName = "installed.sha256"

  // MARK: - Public API

  public static func install(
    settingsURL rawSettingsURL: URL, wrapperPath: String, stateDir: URL, port: Int
  ) throws -> InstallOutcome {
    let fm = FileManager.default
    // A symlinked settings file (dotfile managers) must stay a symlink: edit its target.
    let settingsURL = rawSettingsURL.resolvingSymlinksInPath()
    let existing: Data? =
      fm.fileExists(atPath: settingsURL.path) ? try Data(contentsOf: settingsURL) : nil
    var settings = try parseSettings(existing)
    let ours = shellQuote(wrapperPath)
    let current = settings["statusLine"]
    if let obj = current as? [String: Any], obj["command"] as? String == ours {
      if !fm.isExecutableFile(atPath: wrapperPath) {  // repair a deleted wrapper script
        try writeWrapper(wrapperPath: wrapperPath, stateDir: stateDir, port: port)
        return .installed
      }
      return .alreadyInstalled
    }

    // Everything we need to undo this is written before the settings file is touched.
    try fm.createDirectory(at: stateDir, withIntermediateDirectories: true)
    try (existing ?? Data()).write(
      to: stateDir.appendingPathComponent(backupName), options: .atomic)
    try Data((existing == nil ? "0" : "1").utf8).write(
      to: stateDir.appendingPathComponent(existedName), options: .atomic)
    let originalValue: Any = current ?? NSNull()
    try JSONSerialization.data(withJSONObject: originalValue, options: [.fragmentsAllowed]).write(
      to: stateDir.appendingPathComponent(originalName), options: .atomic)

    try writeWrapper(wrapperPath: wrapperPath, stateDir: stateDir, port: port)

    var entry = (current as? [String: Any]) ?? [:]
    entry["type"] = "command"
    entry["command"] = ours
    settings["statusLine"] = entry
    let written = try serialize(settings)
    try fm.createDirectory(
      at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try written.write(to: settingsURL, options: .atomic)
    try Data(sha256(written).utf8).write(
      to: stateDir.appendingPathComponent(hashName), options: .atomic)
    return .installed
  }

  public static func uninstall(
    settingsURL rawSettingsURL: URL, wrapperPath: String, stateDir: URL
  ) throws -> UninstallOutcome {
    let fm = FileManager.default
    let settingsURL = rawSettingsURL.resolvingSymlinksInPath()
    let hashURL = stateDir.appendingPathComponent(hashName)
    guard fm.fileExists(atPath: hashURL.path) else { return .notInstalled }

    // The backup and the saved original are only deleted after a successful outcome: if anything
    // below throws, they are the only copy of the user's original status line.
    guard fm.fileExists(atPath: settingsURL.path) else {
      cleanState(stateDir: stateDir, wrapperPath: wrapperPath)
      return .notInstalled
    }
    let current = try Data(contentsOf: settingsURL)
    var settings = try parseSettings(current)
    let ours = shellQuote(wrapperPath)
    guard let entry = settings["statusLine"] as? [String: Any], entry["command"] as? String == ours
    else {
      cleanState(stateDir: stateDir, wrapperPath: wrapperPath)
      return .leftAlone  // the user changed it after we installed; not ours to touch
    }

    let installedHash = (try? String(contentsOf: hashURL, encoding: .utf8)) ?? ""
    if sha256(current) == installedHash {
      let existed =
        (try? String(contentsOf: stateDir.appendingPathComponent(existedName), encoding: .utf8))
        == "1"
      if existed {
        try Data(contentsOf: stateDir.appendingPathComponent(backupName)).write(
          to: settingsURL, options: .atomic)
      } else {
        try fm.removeItem(at: settingsURL)
      }
      cleanState(stateDir: stateDir, wrapperPath: wrapperPath)
      return .restored
    }

    // The file changed since install: put back only the status line.
    let originalData = try Data(contentsOf: stateDir.appendingPathComponent(originalName))
    let original = try? JSONSerialization.jsonObject(
      with: originalData, options: [.fragmentsAllowed])
    if let original, !(original is NSNull) {
      settings["statusLine"] = original
    } else {
      settings.removeValue(forKey: "statusLine")
    }
    try serialize(settings).write(to: settingsURL, options: .atomic)
    cleanState(stateDir: stateDir, wrapperPath: wrapperPath)
    return .restored
  }

  public static func status(
    settingsURL rawSettingsURL: URL, wrapperPath: String, projectSettingsURL: URL?
  ) -> InstallState {
    let settingsURL = rawSettingsURL.resolvingSymlinksInPath()
    guard let data = try? Data(contentsOf: settingsURL),
      let user = (try? parseSettings(data)),
      let entry = user["statusLine"] as? [String: Any],
      entry["command"] as? String == shellQuote(wrapperPath)
    else { return .notInstalled }
    if let projectSettingsURL, let pdata = try? Data(contentsOf: projectSettingsURL),
      let project = try? parseSettings(pdata), project["statusLine"] != nil
    {
      return .overriddenByProject
    }
    return .installed
  }

  // MARK: - Wrapper script

  /// The script Claude Code runs as the status line command.
  public static func wrapperScript(stateDir: URL, port: Int) -> String {
    """
    #!/bin/bash
    # Claudette status line wrapper (generated; do not edit).
    # Forwards Claude Code's status line JSON to the Claudette app, then runs the original
    # status line command, if there was one. Never fails the status line.
    STATE=\(shellQuote(stateDir.path))
    PORT=\(port)
    input="$(cat)"
    ( printf '%s' "$input" | /usr/bin/curl -s -m 1 -o /dev/null -X POST \\
        -H 'Content-Type: application/json' --data-binary @- \\
        "http://127.0.0.1:$PORT/status" >/dev/null 2>&1 & )
    orig=""
    if [ -f "$STATE/\(originalName)" ]; then
      orig="$(/usr/bin/plutil -extract command raw -o - "$STATE/\(originalName)" 2>/dev/null)" || orig=""
    fi
    if [ -n "$orig" ]; then
      printf '%s' "$input" | /bin/bash -c "$orig"
    else
      echo
    fi
    exit 0

    """
  }

  // MARK: - Helpers

  private static func writeWrapper(wrapperPath: String, stateDir: URL, port: Int) throws {
    try FileManager.default.createDirectory(at: stateDir, withIntermediateDirectories: true)
    try Data(wrapperScript(stateDir: stateDir, port: port).utf8).write(
      to: URL(fileURLWithPath: wrapperPath), options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wrapperPath)
  }

  static func shellQuote(_ s: String) -> String {
    "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
  }

  private static func parseSettings(_ data: Data?) throws -> [String: Any] {
    guard let data, !data.isEmpty else { return [:] }
    guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw InstallError.settingsNotValidJSON
    }
    return obj
  }

  private static func serialize(_ obj: [String: Any]) throws -> Data {
    try JSONSerialization.data(
      withJSONObject: obj, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
  }

  private static func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  private static func cleanState(stateDir: URL, wrapperPath: String) {
    for name in [backupName, existedName, originalName, hashName] {
      try? FileManager.default.removeItem(at: stateDir.appendingPathComponent(name))
    }
    try? FileManager.default.removeItem(atPath: wrapperPath)
  }
}
