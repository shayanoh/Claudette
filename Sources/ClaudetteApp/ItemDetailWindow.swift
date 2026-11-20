import AppKit
import ClaudetteCore
import SwiftUI

/// Everything we know about an item, in a window: the full command, its result, which session and
/// project it came from.
struct ItemDetailView: View {
  let title: String
  let rows: [DetailRow]
  let command: String?

  private var plainText: String {
    ([title] + rows.map { "\($0.label): \($0.value)" }).joined(separator: "\n")
  }

  private func copy(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
            VStack(alignment: .leading, spacing: 3) {
              Text(row.label).font(.caption).foregroundStyle(.secondary)
              Text(row.value)
                .font(row.mono ? .system(.body, design: .monospaced) : .body)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
          }
        }
        .padding(20)
      }
      Divider()
      HStack {
        Spacer()
        if let command { Button("Copy command") { copy(command) } }
        Button("Copy all") { copy(plainText) }
      }
      .padding(12)
    }
    .frame(minWidth: 420, minHeight: 260)
  }
}

/// Keeps the open detail windows alive until they are closed.
final class ItemDetailWindows {
  static let shared = ItemDetailWindows()
  private var windows: [NSWindow] = []

  func show(_ item: Item) {
    let rows = ItemDetails.rows(item)
    let command = item.terminal?.command
    let host = NSHostingController(
      rootView: ItemDetailView(title: item.label, rows: rows, command: command))
    let window = NSWindow(contentViewController: host)
    window.title = ItemDetails.kindName(item) + ": " + item.label
    window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
    window.isReleasedWhenClosed = false
    window.setContentSize(NSSize(width: 560, height: 420))
    window.center()
    // Staggered, so several windows do not sit exactly on top of each other.
    window.setFrameOrigin(
      NSPoint(
        x: window.frame.origin.x + CGFloat(windows.count % 6) * 24,
        y: window.frame.origin.y - CGFloat(windows.count % 6) * 24))
    windows.append(window)
    NotificationCenter.default.addObserver(
      forName: NSWindow.willCloseNotification, object: window, queue: .main
    ) { [weak self] note in
      guard let w = note.object as? NSWindow else { return }
      self?.windows.removeAll { $0 === w }
    }
    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
  }
}
