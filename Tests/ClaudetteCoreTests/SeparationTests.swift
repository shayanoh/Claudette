import CoreGraphics
import Foundation
import Testing

@testable import ClaudetteCore

private func dist(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }

@Test func pushMovesAwayFromCloseOthersOnly() {
  let p = CGPoint(x: 500, y: 300)
  let pushed = Separation.push(p, awayFrom: [CGPoint(x: 540, y: 300)], minGap: 120)
  #expect(pushed.x < p.x && abs(pushed.y - p.y) < 0.001)
  #expect(dist(pushed, CGPoint(x: 540, y: 300)) > dist(p, CGPoint(x: 540, y: 300)))
  #expect(Separation.push(p, awayFrom: [CGPoint(x: 900, y: 300)], minGap: 120) == p)
}

@Test func pushHandlesCoincidentAndNonFinitePointsAndIsBounded() {
  let p = CGPoint(x: 500, y: 300)
  let same = Separation.push(p, awayFrom: [p, p], minGap: 100)
  #expect(same.x.isFinite && same.y.isFinite && same != p)
  let junk = Separation.push(p, awayFrom: [CGPoint(x: CGFloat.nan, y: 1)], minGap: 100)
  #expect(junk == p)
  let crowd = (0..<50).map { CGPoint(x: 505 + CGFloat($0) * 0.1, y: 300) }
  let out = Separation.push(p, awayFrom: crowd, minGap: 100)
  #expect(dist(out, p) <= 100.001)  // never flung further than one gap
}

@Test func aStandSpotIsOnTheSideSheComesFromWhenNobodyIsThere() {
  let spot = Separation.standSpot(
    target: CGPoint(x: 500, y: 300), from: CGPoint(x: 100, y: 300), standOff: 60,
    avoiding: [], minGap: 120)
  #expect(abs(spot.x - 440) < 0.5 && abs(spot.y - 300) < 0.5)
}

@Test func aStandSpotGoesAroundSomeoneAlreadyStandingThere() {
  let target = CGPoint(x: 500, y: 300)
  let other = CGPoint(x: 440, y: 300)  // exactly where she would stand
  let spot = Separation.standSpot(
    target: target, from: CGPoint(x: 100, y: 300), standOff: 60, avoiding: [other], minGap: 50)
  #expect(dist(spot, other) >= 50)
  #expect(abs(dist(spot, target) - 60) < 0.5)  // still beside the item
}

@Test func whenEverySideIsTakenTheRoomiestOneWins() {
  let target = CGPoint(x: 500, y: 300)
  let ring = (0..<12).map { i -> CGPoint in
    let a = Double(i) / 12 * 2 * .pi
    return CGPoint(x: 500 + 60 * cos(a), y: 300 + 60 * sin(a))
  }
  let spot = Separation.standSpot(
    target: target, from: CGPoint(x: 100, y: 300), standOff: 60, avoiding: ring, minGap: 500)
  #expect(spot.x.isFinite && spot.y.isFinite)
  #expect(abs(dist(spot, target) - 60) < 0.5)
}

@Test func theBrainDoesNotStandOnSomeoneElsesSpot() {
  let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
  let item = Item(
    id: ItemID.tool(useID: "a"), kind: .file, label: "a", owners: ["s"],
    createdAt: Date(timeIntervalSince1970: 0), lastTouched: Date(timeIntervalSince1970: 0),
    position: CGPoint(x: 900, y: 600), display: 1, terminal: nil)
  let other = CGPoint(x: 840, y: 560)
  var rng = SeededRandom(seed: 3)
  let actor = BrainActor(
    position: CGPoint(x: 100, y: 100), others: [other], gap: 100)
  let intents = Brain().plan(
    event: .toolStarted(item, isNew: false, move: .read), actor: actor, world: [item],
    screens: [screen], rng: &rng)
  guard case .walk(let stand)? = intents.first else {
    Issue.record("expected a walk")
    return
  }
  #expect(dist(stand, other) >= 100)
}
