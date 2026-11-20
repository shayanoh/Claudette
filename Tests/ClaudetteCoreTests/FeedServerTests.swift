import Foundation
import Testing

@testable import ClaudetteCore

private final class Inbox: @unchecked Sendable {
  private let lock = NSLock()
  private var items: [FeedMessage] = []
  func add(_ m: FeedMessage) {
    lock.lock()
    items.append(m)
    lock.unlock()
  }
  var all: [FeedMessage] {
    lock.lock()
    defer { lock.unlock() }
    return items
  }
}

private func makeServer() throws -> (FeedServer, Inbox, UInt16) {
  let inbox = Inbox()
  let server = FeedServer(port: 0) { inbox.add($0) }
  try server.start()
  let port = try #require(server.boundPort)
  return (server, inbox, port)
}

private func post(_ port: UInt16, path: String, body: Data, method: String = "POST") async throws
  -> Int
{
  var req = URLRequest(url: URL(string: "http://127.0.0.1:\(port)\(path)")!)
  req.httpMethod = method
  req.httpBody = method == "POST" ? body : nil
  req.setValue("application/json", forHTTPHeaderField: "Content-Type")
  req.timeoutInterval = 5
  let (_, resp) = try await URLSession.shared.data(for: req)
  return (resp as! HTTPURLResponse).statusCode
}

private let goodHook = Data(#"{"hook_event_name":"Stop","session_id":"s1"}"#.utf8)

@Test func postHookDeliversEvent() async throws {
  let (server, inbox, port) = try makeServer()
  defer { server.stop() }
  let status = try await post(port, path: "/hook", body: goodHook)
  #expect(status == 200)
  guard case .hook(let e)? = inbox.all.first else {
    Issue.record("no hook message delivered")
    return
  }
  #expect(e.name == "Stop")
  #expect(e.sessionID == "s1")
}

@Test func postStatusDeliversRawJSON() async throws {
  let (server, inbox, port) = try makeServer()
  defer { server.stop() }
  let body = Data(#"{"session_id":"s1","rate_limits":{}}"#.utf8)
  #expect(try await post(port, path: "/status", body: body) == 200)
  guard case .status(let d)? = inbox.all.first else {
    Issue.record("no status message delivered")
    return
  }
  #expect(d == body)
}

@Test func malformedJSONReturns400AndNoMessage() async throws {
  let (server, inbox, port) = try makeServer()
  defer { server.stop() }
  #expect(try await post(port, path: "/hook", body: Data("{not json".utf8)) == 400)
  #expect(try await post(port, path: "/hook", body: Data(#"{"a":1}"#.utf8)) == 400)
  #expect(try await post(port, path: "/status", body: Data("[1]".utf8)) == 400)
  #expect(inbox.all.isEmpty)
}

@Test func bodyOver1MiBIsRejectedAndServerSurvives() async throws {
  let (server, inbox, port) = try makeServer()
  defer { server.stop() }
  let big = Data(repeating: 0x20, count: 1_048_577)
  do {
    let status = try await post(port, path: "/hook", body: big)
    #expect(status == 413)
  } catch {
    // The server may close the socket while the client is still uploading; that is also a rejection.
  }
  #expect(inbox.all.isEmpty)
  #expect(try await post(port, path: "/hook", body: goodHook) == 200)
}

@Test func getReturns405() async throws {
  let (server, _, port) = try makeServer()
  defer { server.stop() }
  #expect(try await post(port, path: "/hook", body: Data(), method: "GET") == 405)
}

@Test func unknownPathReturns404() async throws {
  let (server, inbox, port) = try makeServer()
  defer { server.stop() }
  #expect(try await post(port, path: "/nope", body: goodHook) == 404)
  #expect(inbox.all.isEmpty)
}

@Test func serverStaysUpAfterGarbageOnTheSocket() async throws {
  let (server, inbox, port) = try makeServer()
  defer { server.stop() }
  // Raw garbage that is not HTTP at all.
  let fd = socket(AF_INET, SOCK_STREAM, 0)
  var addr = sockaddr_in()
  addr.sin_family = sa_family_t(AF_INET)
  addr.sin_port = port.bigEndian
  addr.sin_addr.s_addr = inet_addr("127.0.0.1")
  let rc = withUnsafePointer(to: &addr) {
    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
      connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
    }
  }
  #expect(rc == 0)
  let junk: [UInt8] = [0x00, 0xFF, 0x13, 0x37, 0x0D, 0x0A, 0x0D, 0x0A]
  _ = junk.withUnsafeBytes { send(fd, $0.baseAddress, junk.count, 0) }
  close(fd)
  #expect(try await post(port, path: "/hook", body: goodHook) == 200)
  #expect(inbox.all.count == 1)
}

@Test func bindsLoopbackOnly() async throws {
  let (server, _, port) = try makeServer()
  defer { server.stop() }
  // Find a non-loopback IPv4 address of this machine; if there is none the claim is vacuously true.
  var ifaddr: UnsafeMutablePointer<ifaddrs>?
  guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return }
  defer { freeifaddrs(ifaddr) }
  var lan: String?
  for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
    let sa = ptr.pointee.ifa_addr.pointee
    guard sa.sa_family == UInt8(AF_INET) else { continue }
    var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
    getnameinfo(
      ptr.pointee.ifa_addr, socklen_t(sa.sa_len), &host, socklen_t(host.count), nil, 0,
      NI_NUMERICHOST)
    let ip = String(cString: host)
    if !ip.hasPrefix("127.") && !ip.hasPrefix("169.254.") { lan = ip }
  }
  guard let lan else { return }
  var req = URLRequest(url: URL(string: "http://\(lan):\(port)/hook")!)
  req.httpMethod = "POST"
  req.httpBody = goodHook
  req.timeoutInterval = 2
  await #expect(throws: (any Error).self) {
    _ = try await URLSession.shared.data(for: req)
  }
}
