import Foundation

extension FeedMessage {
  /// One JSON object: `{"kind":"hook"|"status","at":<epoch seconds>,"payload":{...}}`.
  public func logLine(at date: Date) -> Data {
    let kind: String
    let payload: JSONValue
    switch self {
    case .hook(let e):
      kind = "hook"
      payload = e.raw
    case .status(let d):
      kind = "status"
      payload = (try? JSONDecoder().decode(JSONValue.self, from: d)) ?? .null
    }
    let line: JSONValue = .object([
      "kind": .string(kind), "at": .number(date.timeIntervalSince1970), "payload": payload,
    ])
    return (try? JSONEncoder().encode(line)) ?? Data("{}".utf8)
  }
}

/// Append-only JSON-lines log. Failures are reported to stderr and never thrown, so logging can
/// never break event handling.
public final class EventLog: @unchecked Sendable {
  private let url: URL
  private let lock = NSLock()

  public init(url: URL) {
    self.url = url
  }

  public static var defaultURL: URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Logs/Claudette/events.jsonl")
  }

  public func append(_ line: Data) {
    lock.lock()
    defer { lock.unlock() }
    do {
      try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      if !FileManager.default.fileExists(atPath: url.path) {
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
          throw CocoaError(.fileWriteUnknown)
        }
      }
      let handle = try FileHandle(forWritingTo: url)
      defer { try? handle.close() }
      try handle.seekToEnd()
      try handle.write(contentsOf: line + Data([0x0A]))
    } catch {
      FileHandle.standardError.write(Data("EventLog: \(error)\n".utf8))
    }
  }
}
