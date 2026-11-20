import Foundation

/// Wraps command lines and paths for hover text: a few words per line, a few lines, an ellipsis
/// when it does not fit.
public enum TextWrap {
  public static func wrap(
    _ text: String, wordsPerLine: Int = 12, maxCharsPerLine: Int = 80, maxLines: Int = 4
  ) -> [String] {
    guard wordsPerLine > 0, maxCharsPerLine > 1, maxLines > 0 else { return [] }
    var words: [String] = []
    for word in text.split(whereSeparator: \.isWhitespace) {
      var rest = Substring(word)
      while rest.count > maxCharsPerLine {  // a word longer than a line is cut
        words.append(String(rest.prefix(maxCharsPerLine)))
        rest = rest.dropFirst(maxCharsPerLine)
      }
      if !rest.isEmpty { words.append(String(rest)) }
    }
    var lines: [String] = []
    var line = ""
    var count = 0
    for word in words {
      if count > 0, count >= wordsPerLine || line.count + 1 + word.count > maxCharsPerLine {
        lines.append(line)
        line = ""
        count = 0
      }
      line += count == 0 ? word : " " + word
      count += 1
    }
    if count > 0 { lines.append(line) }
    guard lines.count > maxLines else { return lines }
    var kept = Array(lines.prefix(maxLines))
    var last = kept[maxLines - 1]
    if last.count >= maxCharsPerLine { last = String(last.prefix(maxCharsPerLine - 1)) }
    kept[maxLines - 1] = last + "…"
    return kept
  }
}
