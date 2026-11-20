import CoreGraphics
import Foundation
import Testing

@testable import ClaudetteCore

private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
private let size = CGSize(width: 128, height: 100)

private func dist(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }
private func center(_ origin: CGPoint, _ s: CGSize = size) -> CGPoint {
  CGPoint(x: origin.x + s.width / 2, y: origin.y + s.height / 2)
}

// MARK: Placement

@Test func layoutNeverOverlapsAndCapsAtSix() {
  let r = Placement.layout(count: 10, screen: screen, spriteSize: size)
  #expect(r.full.count == 6)
  #expect(r.overflow == 4)
  let rects = r.full.map { CGRect(origin: $0, size: size) }
  for i in rects.indices {
    #expect(screen.contains(rects[i]))
    for j in rects.indices where j > i { #expect(!rects[i].intersects(rects[j])) }
  }
}

@Test func sevenSessionsGiveOverflowOne() {
  let r = Placement.layout(count: 7, screen: screen, spriteSize: size)
  #expect(r.full.count == 6 && r.overflow == 1)
}

@Test func layoutOnNarrowScreenFitsFewerAndReportsOverflow() {
  let narrow = CGRect(x: 0, y: 0, width: 400, height: 300)
  let r = Placement.layout(count: 5, screen: narrow, spriteSize: size)
  #expect(r.full.count + r.overflow == 5)
  #expect(r.full.count < 5)
  #expect(r.full.allSatisfy { narrow.contains(CGRect(origin: $0, size: size)) })
}

@Test func layoutHandlesZeroNegativeAndHugeSprites() {
  #expect(Placement.layout(count: 0, screen: screen, spriteSize: size).full.isEmpty)
  #expect(Placement.layout(count: -3, screen: screen, spriteSize: size).overflow == 0)
  let tiny = CGRect(x: 0, y: 0, width: 50, height: 50)
  let r = Placement.layout(count: 2, screen: tiny, spriteSize: CGSize(width: 256, height: 200))
  #expect(r.full.count == 1)  // at least one is always shown
  #expect(r.overflow == 1)
}

// MARK: Hover fade

@Test func fadeOpacityMatrix() {
  var s = ClaudetteSettings()
  #expect(HoverFade.opacity(pointerInside: false, settings: s) == 1.0)
  #expect(HoverFade.opacity(pointerInside: true, settings: s) == 0.25)
  s.hoverFadeOpacity = 0.3
  #expect(HoverFade.opacity(pointerInside: true, settings: s) == 0.3)
  s.hoverFadeEnabled = false
  #expect(HoverFade.opacity(pointerInside: true, settings: s) == 1.0)
}

// MARK: Dodge

@Test func dodgeDoesNothingWhenPointerIsFar() {
  let sprite = CGRect(x: 600, y: 300, width: 128, height: 100)
  let next = DodgePlanner.nextPosition(
    sprite: sprite, pointer: CGPoint(x: 1300, y: 800), screens: [screen], shyness: 0.5,
    otherSprites: [])
  #expect(next == sprite.origin)
}

@Test func dodgeMovesAwayFromPointerAndStaysOnScreen() throws {
  let sprite = CGRect(x: 600, y: 300, width: 128, height: 100)
  let pointer = CGPoint(x: 660, y: 340)
  let next = try #require(
    DodgePlanner.nextPosition(
      sprite: sprite, pointer: pointer, screens: [screen], shyness: 0.5, otherSprites: []))
  #expect(dist(center(next), pointer) > dist(center(sprite.origin), pointer))
  #expect(screen.contains(CGRect(origin: next, size: sprite.size)))
}

@Test func dodgeAvoidsOtherSprites() throws {
  let sprite = CGRect(x: 600, y: 300, width: 128, height: 100)
  let others = [
    CGRect(x: 440, y: 300, width: 128, height: 100),
    CGRect(x: 760, y: 300, width: 128, height: 100),
  ]
  let next = try #require(
    DodgePlanner.nextPosition(
      sprite: sprite, pointer: CGPoint(x: 660, y: 340), screens: [screen], shyness: 0.5,
      otherSprites: others))
  let rect = CGRect(origin: next, size: sprite.size)
  #expect(others.allSatisfy { !$0.intersects(rect) })
}

@Test func dodgeReturnsNilInTightCorner() {
  let small = CGRect(x: 0, y: 0, width: 140, height: 120)
  let sprite = CGRect(x: 6, y: 6, width: 128, height: 100)
  let next = DodgePlanner.nextPosition(
    sprite: sprite, pointer: CGPoint(x: 70, y: 56), screens: [small], shyness: 0.5, otherSprites: []
  )
  #expect(next == nil)
}

@Test func higherShynessDodgesFromFurtherAway() throws {
  let sprite = CGRect(x: 600, y: 300, width: 128, height: 100)
  let pointer = CGPoint(x: 664 + 190, y: 350)  // 190 pt from the sprite centre
  let shy = DodgePlanner.nextPosition(
    sprite: sprite, pointer: pointer, screens: [screen], shyness: 0.9, otherSprites: [])
  let bold = DodgePlanner.nextPosition(
    sprite: sprite, pointer: pointer, screens: [screen], shyness: 0.1, otherSprites: [])
  #expect(shy != sprite.origin)
  #expect(bold == sprite.origin)
}

@Test func dodgeCanUseAnotherScreen() throws {
  let right = CGRect(x: 1440, y: 0, width: 1440, height: 900)
  let sprite = CGRect(x: 1330, y: 300, width: 128, height: 100)  // straddles nothing, near the edge
  let next = try #require(
    DodgePlanner.nextPosition(
      sprite: sprite, pointer: CGPoint(x: 1300, y: 350), screens: [screen, right], shyness: 0.6,
      otherSprites: []))
  let rect = CGRect(origin: next, size: sprite.size)
  #expect(screen.contains(rect) || right.contains(rect))
}

// MARK: Drag

@Test func dragVelocityFromRecentMoves() {
  var d = DragPhysics()
  d.begin(at: .zero)
  for i in 1...10 { d.move(to: CGPoint(x: CGFloat(i) * 10, y: 0), dt: 0.01) }
  let v = d.release()
  #expect(abs(v.dx - 1000) < 20)
  #expect(abs(v.dy) < 1)
}

@Test func releaseWithoutMovesHasZeroVelocity() {
  var d = DragPhysics()
  d.begin(at: CGPoint(x: 5, y: 5))
  let v = d.release()
  #expect(v == .zero)
}

@Test func oldMovesDoNotCountTowardsVelocity() {
  var d = DragPhysics()
  d.begin(at: .zero)
  d.move(to: CGPoint(x: 500, y: 0), dt: 0.01)  // a fast move long ago...
  for _ in 0..<30 { d.move(to: CGPoint(x: 500, y: 0), dt: 0.02) }  // ...then holding still
  #expect(d.release() == .zero)
}

@Test func glideStaysInsideScreenAndDecelerates() {
  let path = DragPhysics.glide(
    from: CGPoint(x: 1300, y: 400), velocity: CGVector(dx: 2500, dy: 300), screen: screen,
    spriteSize: size)
  #expect(!path.isEmpty)
  #expect(path.allSatisfy { screen.contains(CGRect(origin: $0, size: size)) })
  let steps = zip(path, path.dropFirst()).map { dist($0, $1) }
  #expect(zip(steps, steps.dropFirst()).allSatisfy { $1 <= $0 + 0.001 })
  #expect(path.count < 700)  // it stops
}

@Test func glideWithZeroVelocityStaysPut() {
  let p = CGPoint(x: 10, y: 10)
  #expect(DragPhysics.glide(from: p, velocity: .zero, screen: screen, spriteSize: size) == [p])
}

@Test func glideWithNonFiniteVelocityDoesNotCrash() {
  let p = CGPoint(x: 10, y: 10)
  let path = DragPhysics.glide(
    from: p, velocity: CGVector(dx: CGFloat.nan, dy: CGFloat.infinity), screen: screen,
    spriteSize: size)
  #expect(path == [p])
}

// MARK: ScreenFit

@Test func clampKeepsSpriteOnItsScreen() {
  let o = ScreenFit.clamp(CGPoint(x: 1400, y: -50), size: size, to: [screen])
  #expect(screen.contains(CGRect(origin: o, size: size)))
}

@Test func clampRelocatesFromRemovedDisplay() {
  // The sprite stood on a display at x 1440..2880 that is gone; only the main screen remains.
  let o = ScreenFit.clamp(CGPoint(x: 2000, y: 300), size: size, to: [screen])
  #expect(screen.contains(CGRect(origin: o, size: size)))
}

@Test func clampPrefersTheNearestScreen() {
  let right = CGRect(x: 1440, y: 0, width: 1440, height: 900)
  let o = ScreenFit.clamp(CGPoint(x: 1500, y: 300), size: size, to: [screen, right])
  #expect(right.contains(CGRect(origin: o, size: size)))
}

@Test func clampCentresOversizedSprite() {
  let tiny = CGRect(x: 0, y: 0, width: 100, height: 100)
  let big = CGSize(width: 300, height: 200)
  let o = ScreenFit.clamp(CGPoint(x: 900, y: 900), size: big, to: [tiny])
  #expect(center(o, big) == CGPoint(x: 50, y: 50))
}

@Test func zeroSizedOrEmptyScreenListDoesNotCrash() {
  let p = CGPoint(x: 5, y: 5)
  #expect(ScreenFit.clamp(p, size: size, to: []) == p)
  _ = ScreenFit.clamp(p, size: size, to: [.zero])
  #expect(
    DodgePlanner.nextPosition(
      sprite: CGRect(origin: p, size: size), pointer: p, screens: [], shyness: 0.5, otherSprites: []
    )
      == nil)
  #expect(Placement.layout(count: 3, screen: .zero, spriteSize: size).full.count <= 1)
}
