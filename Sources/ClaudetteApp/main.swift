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

// Developer helper: `Claudette --render-overlap <png>` draws two overlapping Claudettes and exits.
if let i = args.firstIndex(of: "--render-overlap"), i + 1 < args.count {
  _ = NSApplication.shared
  exit(PropSheet.renderOverlap(to: URL(fileURLWithPath: args[i + 1])) ? 0 : 1)
}

if let i = args.firstIndex(of: "--render-poses"), i + 1 < args.count {
  _ = NSApplication.shared
  exit(PropSheet.renderPoses(to: URL(fileURLWithPath: args[i + 1])) ? 0 : 1)
}

if let i = args.firstIndex(of: "--render-hover"), i + 1 < args.count {
  _ = NSApplication.shared
  exit(PropSheet.renderHover(to: URL(fileURLWithPath: args[i + 1])) ? 0 : 1)
}

// Developer helper: `Claudette --print-walk-area` prints each screen, its visible frame and the area
// Claudettes and items may use (Dock and magnification reserved), then exits.
if args.contains("--print-walk-area") {
  _ = NSApplication.shared
  print("dock magnified extra: \(DockInfo.magnifiedExtra)")
  for s in NSScreen.screens {
    let walk = WalkArea.frame(
      screen: s.frame, visible: s.visibleFrame, magnifiedExtra: DockInfo.magnifiedExtra)
    print("screen \(s.frame)  visible \(s.visibleFrame)  walk \(walk)")
  }
  exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
