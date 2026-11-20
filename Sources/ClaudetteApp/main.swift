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

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
