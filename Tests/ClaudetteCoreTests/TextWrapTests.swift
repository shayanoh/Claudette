import Foundation
import Testing

@testable import ClaudetteCore

@Test func wrapsByWordsPerLine() {
  let text = (1...30).map { "w\($0)" }.joined(separator: " ")
  let lines = TextWrap.wrap(text, wordsPerLine: 12, maxCharsPerLine: 200, maxLines: 5)
  #expect(lines.count == 3)
  #expect(lines[0].split(separator: " ").count == 12)
  #expect(lines[2] == "w25 w26 w27 w28 w29 w30")
}

@Test func wrapsByCharactersToo() {
  let text = Array(repeating: "abcdefghij", count: 12).joined(separator: " ")  // 12 words, 131 chars
  let lines = TextWrap.wrap(text, wordsPerLine: 12, maxCharsPerLine: 40, maxLines: 10)
  #expect(lines.allSatisfy { $0.count <= 40 })
  #expect(lines.joined(separator: " ") == text)
}

@Test func tooMuchTextEndsInAnEllipsisWithinTheLineBudget() {
  let text = (1...200).map { "word\($0)" }.joined(separator: " ")
  let lines = TextWrap.wrap(text, wordsPerLine: 12, maxCharsPerLine: 80, maxLines: 4)
  #expect(lines.count == 4)
  #expect(lines.last?.hasSuffix("…") == true)
  #expect(lines.allSatisfy { $0.count <= 80 })
}

@Test func anExactFitHasNoEllipsis() {
  let text = (1...48).map { "w\($0)" }.joined(separator: " ")
  let lines = TextWrap.wrap(text, wordsPerLine: 12, maxCharsPerLine: 200, maxLines: 4)
  #expect(lines.count == 4)
  #expect(lines.last?.hasSuffix("…") == false)
}

@Test func aVeryLongWordIsBrokenAndNewlinesAreSpaces() {
  let lines = TextWrap.wrap(
    String(repeating: "x", count: 250), wordsPerLine: 12, maxCharsPerLine: 80, maxLines: 5)
  #expect(lines.count == 4)
  #expect(lines.allSatisfy { $0.count <= 80 })
  #expect(TextWrap.wrap("ls -la\n  && echo   hi", maxLines: 3) == ["ls -la && echo hi"])
}

@Test func emptyAndHostileInputIsHandled() {
  #expect(TextWrap.wrap("").isEmpty)
  #expect(TextWrap.wrap("   \n\t ").isEmpty)
  #expect(TextWrap.wrap("a b", wordsPerLine: 0, maxCharsPerLine: 0, maxLines: 0).isEmpty)
}
