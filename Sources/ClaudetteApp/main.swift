import AppKit
import ClaudetteCore

// Developer helper: `Claudette --write-plugin <dir>` writes the Claude Code plugin and exits.
let args = CommandLine.arguments
if let i = args.firstIndex(of: "--write-plugin") {
  guard i + 1 < args.count else {
    FileHandle.standardError.write(Data("usage: Claudette --write-plugin <dir>\n".utf8))
    exit(2)
  }
  do {
    try PluginInstaller.write(
      to: URL(fileURLWithPath: args[i + 1]), port: Int(AppDelegate.feedPort))
    print("wrote plugin to \(args[i + 1])")
    exit(0)
  } catch {
    FileHandle.standardError.write(Data("failed: \(error)\n".utf8))
    exit(1)
  }
}

// Developer helper: `Claudette --validate-art <dir>` checks an art export and exits.
if let i = args.firstIndex(of: "--validate-art") {
  guard i + 1 < args.count else {
    FileHandle.standardError.write(Data("usage: Claudette --validate-art <dir>\n".utf8))
    exit(2)
  }
  do {
    let n = try ArtCheck.validate(dir: URL(fileURLWithPath: args[i + 1]))
    print("OK: \(n) assets")
    exit(0)
  } catch {
    FileHandle.standardError.write(Data("art invalid: \(error)\n".utf8))
    exit(1)
  }
}

// Developer helper: `Claudette --render-props <png>` draws a sheet of props on a light and a dark
// backdrop (label legibility) and exits.
if let i = args.firstIndex(of: "--render-props") {
  guard i + 1 < args.count else {
    FileHandle.standardError.write(Data("usage: Claudette --render-props <png>\n".utf8))
    exit(2)
  }
  _ = NSApplication.shared
  exit(PropSheet.render(to: URL(fileURLWithPath: args[i + 1])) ? 0 : 1)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
