import CoreGraphics
import Foundation

/// Turns what `zellij action list-panes -a -t --json` and `list-tabs -a --json` report into a caret
/// position on screen. Terminals hide their caret from Accessibility, but Zellij knows the cursor
/// cell; the window is assumed to be exactly the Zellij cell grid.
public enum ZellijCaret {
  private struct Pane: Decodable {
    let is_plugin: Bool
    let is_focused: Bool
    let is_suppressed: Bool?
    let pane_x: Int
    let pane_y: Int
    let cursor_coordinates_in_pane: [Int]?
    let tab_position: Int?
  }
  private struct Tab: Decodable {
    let position: Int
    let active: Bool
    let display_area_rows: Int
    let display_area_columns: Int
  }

  /// The caret's centre in screen coordinates with a TOP-left origin (like Accessibility), or nil
  /// when anything is missing or malformed.
  public static func point(panes: Data, tabs: Data, window: CGRect) -> CGPoint? {
    guard window.width > 0, window.height > 0,
      let tabList = try? JSONDecoder().decode([Tab].self, from: tabs),
      let tab = tabList.first(where: \.active), tab.display_area_columns > 0,
      tab.display_area_rows > 0,
      let paneList = try? JSONDecoder().decode([Pane].self, from: panes),
      let pane = paneList.first(where: {
        !$0.is_plugin && $0.is_focused && $0.is_suppressed != true
          && $0.tab_position == tab.position
          && $0.cursor_coordinates_in_pane?.count == 2
      }), let cursor = pane.cursor_coordinates_in_pane
    else { return nil }
    let cellW = window.width / CGFloat(tab.display_area_columns)
    let cellH = window.height / CGFloat(tab.display_area_rows)
    let p = CGPoint(
      x: window.minX + (CGFloat(pane.pane_x + cursor[0]) + 0.5) * cellW,
      y: window.minY + (CGFloat(pane.pane_y + cursor[1]) + 0.5) * cellH)
    return p.x.isFinite && p.y.isFinite ? p : nil
  }
}
