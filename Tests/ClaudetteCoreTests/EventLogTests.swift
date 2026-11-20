import Foundation
import Testing

@testable import ClaudetteCore

private func tempDir() -> URL {
  let url = FileManager.default.temporaryDirectory.appendingPathComponent(
    "claudette-test-\(UUID().uuidString)")
  return url
}

@Test func appendWritesOneJSONLinePerCall() throws {
  let dir = tempDir()
  defer { try? FileManager.default.removeItem(at: dir) }
  try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
  let log = EventLog(url: dir.appendingPathComponent("events.jsonl"))
  log.append(Data(#"{"a":1}"#.utf8))
  log.append(Data(#"{"b":2}"#.utf8))
  let text = try String(contentsOf: dir.appendingPathComponent("events.jsonl"), encoding: .utf8)
  #expect(text == "{\"a\":1}\n{\"b\":2}\n")
}

@Test func appendCreatesMissingDirectory() throws {
  let dir = tempDir()
  defer { try? FileManager.default.removeItem(at: dir) }
  let file = dir.appendingPathComponent("deep/er/events.jsonl")
  EventLog(url: file).append(Data("x".utf8))
  #expect(FileManager.default.fileExists(atPath: file.path))
}

@Test func logLineWrapsHookAndStatusAsValidJSON() throws {
  let hook = try HookEvent.decode(Data(#"{"hook_event_name":"Stop","session_id":"s1"}"#.utf8))
  let at = Date(timeIntervalSince1970: 1_700_000_000)
  let h = try #require(
    try JSONSerialization.jsonObject(with: FeedMessage.hook(hook).logLine(at: at)) as? [String: Any]
  )
  #expect(h["kind"] as? String == "hook")
  #expect(h["at"] as? Double == 1_700_000_000)
  #expect((h["payload"] as? [String: Any])?["session_id"] as? String == "s1")

  let s = try #require(
    try JSONSerialization.jsonObject(
      with: FeedMessage.status(Data(#"{"session_id":"s2"}"#.utf8)).logLine(at: at))
      as? [String: Any])
  #expect(s["kind"] as? String == "status")
  #expect((s["payload"] as? [String: Any])?["session_id"] as? String == "s2")
}

@Test func appendNeverThrowsOnUnwritablePath() {
  let log = EventLog(url: URL(fileURLWithPath: "/proc/definitely/not/writable/events.jsonl"))
  log.append(Data("x".utf8))  // must not crash
}
