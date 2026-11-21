import CoreGraphics
import Foundation
import Testing

@testable import ClaudetteCore

@Suite struct ZellijCaretTests {
  let tabs = #"[{"position":0,"active":true,"display_area_rows":60,"display_area_columns":224}]"#
  func pane(focused: Bool = true, cursor: String = "[3,53]", tab: Int = 0) -> String {
    #"[{"is_plugin":false,"is_focused":\#(focused),"is_suppressed":false,"pane_x":0,"pane_y":1,"cursor_coordinates_in_pane":\#(cursor),"tab_position":\#(tab)}]"#
  }
  let window = CGRect(x: 0, y: 25, width: 1680, height: 960)

  @Test func mapsCursorCellToScreen() throws {
    let p = try #require(
      ZellijCaret.point(panes: Data(pane().utf8), tabs: Data(tabs.utf8), window: window))
    #expect(abs(p.x - 26.25) < 0.01)  // (0+3+0.5) * 7.5
    #expect(abs(p.y - (25 + 54.5 * 16)) < 0.01)  // (1+53+0.5) * 16
  }

  @Test func ignoresUnfocusedOtherTabNoCursorAndBadInput() {
    let t = Data(tabs.utf8)
    #expect(
      ZellijCaret.point(panes: Data(pane(focused: false).utf8), tabs: t, window: window) == nil)
    #expect(ZellijCaret.point(panes: Data(pane(tab: 1).utf8), tabs: t, window: window) == nil)
    #expect(
      ZellijCaret.point(panes: Data(pane(cursor: "null").utf8), tabs: t, window: window) == nil)
    #expect(ZellijCaret.point(panes: Data("junk".utf8), tabs: t, window: window) == nil)
    #expect(ZellijCaret.point(panes: Data(pane().utf8), tabs: t, window: .zero) == nil)
  }
}
