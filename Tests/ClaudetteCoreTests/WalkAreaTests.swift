import CoreGraphics
import Foundation
import Testing

@testable import ClaudetteCore

private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)

@Test func aBottomDockShrinksTheAreaByItsMagnifiedExtra() {
  let visible = CGRect(x: 0, y: 70, width: 1440, height: 800)  // Dock 70 pt, menu bar 30 pt
  let area = WalkArea.frame(screen: screen, visible: visible, magnifiedExtra: 80)
  #expect(area.minY == 150)
  #expect(area.maxY == 870 && area.minX == 0 && area.maxX == 1440)
}

@Test func aLeftOrRightDockShrinksThatSide() {
  let left = WalkArea.frame(
    screen: screen, visible: CGRect(x: 60, y: 0, width: 1380, height: 870), magnifiedExtra: 50)
  #expect(left.minX == 110 && left.minY == 0)
  let right = WalkArea.frame(
    screen: screen, visible: CGRect(x: 0, y: 0, width: 1380, height: 870), magnifiedExtra: 50)
  #expect(right.maxX == 1330)
}

@Test func noDockOrAHiddenDockReturnsTheVisibleFrame() {
  let visible = CGRect(x: 0, y: 0, width: 1440, height: 870)  // auto-hide: only the menu bar
  #expect(WalkArea.frame(screen: screen, visible: visible, magnifiedExtra: 80) == visible)
}

@Test func noMagnificationLeavesTheVisibleFrameAlone() {
  let visible = CGRect(x: 0, y: 70, width: 1440, height: 800)
  #expect(WalkArea.frame(screen: screen, visible: visible, magnifiedExtra: 0) == visible)
}

@Test func nonsenseExtrasAreIgnoredAndTheAreaNeverCollapses() {
  let visible = CGRect(x: 0, y: 70, width: 1440, height: 800)
  #expect(
    WalkArea.frame(screen: screen, visible: visible, magnifiedExtra: CGFloat.nan) == visible)
  #expect(WalkArea.frame(screen: screen, visible: visible, magnifiedExtra: -20) == visible)
  let tiny = WalkArea.frame(
    screen: CGRect(x: 0, y: 0, width: 300, height: 300),
    visible: CGRect(x: 0, y: 40, width: 300, height: 230), magnifiedExtra: 5000)
  #expect(tiny.height >= 150)  // a huge value cannot swallow the screen
}
