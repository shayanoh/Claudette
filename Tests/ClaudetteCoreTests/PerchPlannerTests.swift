import CoreGraphics
import Foundation
import Testing

@testable import ClaudetteCore

private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
private let own: Int32 = 100
private let min = CGSize(width: 200, height: 120)

private func win(_ n: Int, _ f: CGRect, layer: Int = 0, pid: Int32 = 7) -> WindowFrame {
  WindowFrame(number: n, frame: f, layer: layer, ownerPID: pid)
}

private func pick(near: CGPoint, _ ws: [WindowFrame], reach: CGFloat = 200)
  -> (window: Int, spot: CGPoint)?
{
  PerchPlanner.candidate(
    near: near, windows: ws, screens: [screen], ownPID: own, minSize: min, reach: reach)
}

@Test func picksTheNearestUncoveredTopEdge() {
  let far = win(1, CGRect(x: 800, y: 100, width: 400, height: 300))  // top edge y 400
  let near = win(2, CGRect(x: 100, y: 100, width: 400, height: 250))  // top edge y 350
  let c = pick(near: CGPoint(x: 300, y: 330), [far, near])
  #expect(c?.window == 2)
  #expect(c?.spot.y == 350)
  #expect(c.map { $0.spot.x >= 100 && $0.spot.x <= 500 } == true)
}

@Test func spotStaysInsideTheWindowsHorizontalSpan() {
  let w = win(1, CGRect(x: 100, y: 100, width: 400, height: 250))
  let c = pick(near: CGPoint(x: 5, y: 350), [w])
  #expect(c.map { $0.spot.x >= 130 && $0.spot.x <= 470 } == true)
}

@Test func ignoresOwnTinyAndNonZeroLayerWindows() {
  let ws = [
    win(1, CGRect(x: 100, y: 100, width: 400, height: 250), pid: own),
    win(2, CGRect(x: 100, y: 100, width: 50, height: 30)),
    win(3, CGRect(x: 100, y: 100, width: 400, height: 250), layer: 25),
  ]
  #expect(pick(near: CGPoint(x: 300, y: 350), ws) == nil)
}

@Test func aCoveredTopEdgeIsNotACandidate() {
  let front = win(1, CGRect(x: 0, y: 200, width: 1000, height: 600))  // covers the edge below; its own top is out of reach
  let back = win(2, CGRect(x: 100, y: 100, width: 400, height: 300))  // top edge y 400
  #expect(pick(near: CGPoint(x: 300, y: 400), [front, back]) == nil)
}

@Test func windowsOutOfReachAreNotCandidates() {
  let w = win(1, CGRect(x: 1000, y: 100, width: 400, height: 250))
  #expect(pick(near: CGPoint(x: 100, y: 100), [w], reach: 200) == nil)
}

@Test func aWindowAtTheTopOfTheScreenHasNoFreeEdge() {
  let full = win(1, screen)
  let nearTop = win(2, CGRect(x: 100, y: 500, width: 400, height: 380))  // top 880, no headroom
  #expect(pick(near: CGPoint(x: 300, y: 880), [full, nearTop]) == nil)
}

@Test func movedBeyondToleranceCountsAsMoved() {
  let before = win(1, CGRect(x: 100, y: 100, width: 400, height: 250))
  let spot = CGPoint(x: 300, y: 350)
  func moved(_ now: WindowFrame) -> Bool {
    PerchPlanner.moved(perched: before, spot: spot, now: [now], tolerance: 6)
  }
  #expect(!moved(before))
  #expect(!moved(win(1, CGRect(x: 103, y: 102, width: 400, height: 250))))
  #expect(moved(win(1, CGRect(x: 100, y: 130, width: 400, height: 250))))
  #expect(moved(win(1, CGRect(x: 160, y: 100, width: 400, height: 250))))
  #expect(moved(win(1, CGRect(x: 100, y: 100, width: 300, height: 250))))
}

@Test func aGoneWindowCountsAsMoved() {
  let before = win(1, CGRect(x: 100, y: 100, width: 400, height: 250))
  #expect(PerchPlanner.moved(perched: before, spot: CGPoint(x: 300, y: 350), now: [], tolerance: 6))
  let other = win(2, CGRect(x: 0, y: 0, width: 50, height: 50))
  #expect(
    PerchPlanner.moved(perched: before, spot: CGPoint(x: 300, y: 350), now: [other], tolerance: 6))
}

@Test func beingCoveredAfterPerchingCountsAsMoved() {
  let before = win(1, CGRect(x: 100, y: 100, width: 400, height: 250))
  let cover = win(2, CGRect(x: 0, y: 200, width: 1000, height: 300))
  #expect(
    PerchPlanner.moved(
      perched: before, spot: CGPoint(x: 300, y: 350), now: [cover, before], tolerance: 6))
}
