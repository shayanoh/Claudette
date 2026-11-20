import CoreGraphics
import Foundation
import Testing

@testable import ClaudetteCore

private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
private let size = CGSize(width: 60, height: 70)

private func inside(_ p: CGPoint, _ s: CGRect = screen) -> Bool {
  s.contains(
    CGRect(
      x: p.x - size.width / 2, y: p.y - size.height / 2, width: size.width, height: size.height))
}

@Test func spotKeepsMinimumSpacing() {
  let existing = [
    CGPoint(x: 700, y: 400), CGPoint(x: 740, y: 420), CGPoint(x: 660, y: 380),
    CGPoint(x: 720, y: 360), CGPoint(x: 690, y: 450),
  ]
  for seed in 0..<50 {
    let p = Scatter.spot(
      near: CGPoint(x: 700, y: 400), existing: existing, itemSize: size, screens: [screen],
      seed: UInt64(seed))
    for e in existing { #expect(hypot(p.x - e.x, p.y - e.y) >= size.width) }
  }
}

@Test func radiusGrowsWithCrowding() {
  let near = CGPoint(x: 700, y: 450)
  let crowd = (0..<12).map { i in
    CGPoint(x: 700 + 30 * cos(Double(i)), y: 450 + 30 * sin(Double(i)))
  }
  func mean(_ existing: [CGPoint]) -> Double {
    let ds = (0..<40).map { seed -> Double in
      let p = Scatter.spot(
        near: near, existing: existing, itemSize: size, screens: [screen], seed: UInt64(seed))
      return hypot(p.x - near.x, p.y - near.y)
    }
    return ds.reduce(0, +) / Double(ds.count)
  }
  #expect(mean(crowd) > mean([]) + 20)
}

@Test func alwaysFullyOnScreen() {
  for near in [
    CGPoint(x: 0, y: 0), CGPoint(x: 1440, y: 900), CGPoint(x: -500, y: 2000),
    CGPoint(x: 720, y: 5),
  ] {
    for seed in 0..<20 {
      let p = Scatter.spot(
        near: near, existing: [], itemSize: size, screens: [screen], seed: UInt64(seed))
      #expect(inside(p))
    }
  }
}

@Test func deterministicPerSeed() {
  let a = Scatter.spot(
    near: CGPoint(x: 300, y: 300), existing: [CGPoint(x: 310, y: 300)], itemSize: size,
    screens: [screen], seed: 42)
  let b = Scatter.spot(
    near: CGPoint(x: 300, y: 300), existing: [CGPoint(x: 310, y: 300)], itemSize: size,
    screens: [screen], seed: 42)
  #expect(a == b)
}

@Test func emptyScreensReturnsNearUnchanged() {
  let p = Scatter.spot(
    near: CGPoint(x: 5, y: 6), existing: [], itemSize: size, screens: [], seed: 1)
  #expect(p == CGPoint(x: 5, y: 6))
}

@Test func nonFiniteInputsStayOnScreen() {
  let p = Scatter.spot(
    near: CGPoint(x: CGFloat.nan, y: CGFloat.infinity), existing: [CGPoint(x: CGFloat.nan, y: 1)],
    itemSize: CGSize(width: 0, height: 0), screens: [screen], seed: 3)
  #expect(p.x.isFinite && p.y.isFinite)
  #expect(screen.contains(p))
}

@Test func fullScreenOfItemsStillReturnsAPointOnScreen() {
  let small = CGRect(x: 0, y: 0, width: 300, height: 200)
  var existing: [CGPoint] = []
  var y: CGFloat = 35
  while y < 200 {
    var x: CGFloat = 30
    while x < 300 {
      existing.append(CGPoint(x: x, y: y))
      x += 30
    }
    y += 35
  }
  let p = Scatter.spot(
    near: CGPoint(x: 150, y: 100), existing: existing, itemSize: size, screens: [small], seed: 9)
  #expect(inside(p, small))
}

@Test func choosesTheScreenHoldingTheAnchor() {
  let second = CGRect(x: 1440, y: 0, width: 1280, height: 800)
  let p = Scatter.spot(
    near: CGPoint(x: 2000, y: 400), existing: [], itemSize: size, screens: [screen, second],
    seed: 5)
  #expect(inside(p, second))
}
