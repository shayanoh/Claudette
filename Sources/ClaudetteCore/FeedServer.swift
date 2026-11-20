import Foundation
import Network

public enum FeedMessage: Equatable, Sendable {
  case hook(HookEvent)
  case status(Data)
}

public enum FeedServerError: Error {
  case invalidPort
  case failedToStart(String)
}

/// Loopback-only HTTP/1.1 listener. `POST /hook` takes a hook event, `POST /status` takes the
/// status line payload. Every reply has an empty body so Claude Code is never held up.
public final class FeedServer: @unchecked Sendable {
  static let maxBody = 1_048_576
  static let maxHeader = 16 * 1024
  static let readTimeout: TimeInterval = 5

  private let port: UInt16
  private let onMessage: @Sendable (FeedMessage) -> Void
  private let queue = DispatchQueue(label: "claudette.feed")
  private var listener: NWListener?
  public private(set) var boundPort: UInt16?

  public init(port: UInt16, onMessage: @escaping @Sendable (FeedMessage) -> Void) {
    self.port = port
    self.onMessage = onMessage
  }

  public func start() throws {
    guard let nwPort = NWEndpoint.Port(rawValue: port) else { throw FeedServerError.invalidPort }
    let params = NWParameters.tcp
    params.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: nwPort)
    let l = try NWListener(using: params)
    let ready = DispatchSemaphore(value: 0)
    var failure: String?
    l.stateUpdateHandler = { state in
      switch state {
      case .ready: ready.signal()
      case .failed(let e):
        failure = "\(e)"
        ready.signal()
      default: break
      }
    }
    l.newConnectionHandler = { [weak self] conn in self?.accept(conn) }
    l.start(queue: queue)
    guard ready.wait(timeout: .now() + 3) == .success, failure == nil else {
      l.cancel()
      throw FeedServerError.failedToStart(failure ?? "timeout")
    }
    listener = l
    boundPort = l.port?.rawValue
  }

  public func stop() {
    listener?.cancel()
    listener = nil
    boundPort = nil
  }

  // MARK: - Connection handling

  private func accept(_ conn: NWConnection) {
    let session = Exchange(conn: conn, queue: queue, onMessage: onMessage)
    session.run()
  }

  private final class Exchange {
    let conn: NWConnection
    let queue: DispatchQueue
    let onMessage: @Sendable (FeedMessage) -> Void
    var buffer = Data()
    var bodyStart: Int?
    var route: String?
    var contentLength = 0
    var finished = false

    init(
      conn: NWConnection, queue: DispatchQueue, onMessage: @escaping @Sendable (FeedMessage) -> Void
    ) {
      self.conn = conn
      self.queue = queue
      self.onMessage = onMessage
    }

    func run() {
      conn.start(queue: queue)
      queue.asyncAfter(deadline: .now() + FeedServer.readTimeout) { [self] in
        if !finished { finish(408) }
      }
      receive()
    }

    private func receive() {
      conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) {
        [self] data, _, isDone, error in
        if finished { return }
        if let data, !data.isEmpty {
          buffer.append(data)
          process()
          if finished { return }
        }
        if error != nil || isDone {
          conn.cancel()
          finished = true
          return
        }
        receive()
      }
    }

    private func process() {
      if bodyStart == nil {
        guard let end = buffer.range(of: Data("\r\n\r\n".utf8)) else {
          if buffer.count > FeedServer.maxHeader { finish(431) }
          return
        }
        let head = String(decoding: buffer[buffer.startIndex..<end.lowerBound], as: UTF8.self)
        guard let status = parseHead(head) else { return }
        if status != 0 {
          finish(status)
          return
        }
        bodyStart = end.upperBound
      }
      guard let start = bodyStart, buffer.count - start >= contentLength else { return }
      let body = buffer[start..<(start + contentLength)]
      deliver(Data(body))
    }

    /// Returns nil when the head is unusable (already answered), 0 when the request may proceed,
    /// or an HTTP status to answer with.
    private func parseHead(_ head: String) -> Int? {
      let lines = head.components(separatedBy: "\r\n")
      let parts = (lines.first ?? "").split(separator: " ")
      guard parts.count >= 2 else {
        finish(400)
        return nil
      }
      guard parts[0] == "POST" else { return 405 }
      let path = String(parts[1])
      guard path == "/hook" || path == "/status" else { return 404 }
      route = path
      var length: Int?
      for line in lines.dropFirst() {
        let kv = line.split(separator: ":", maxSplits: 1).map {
          $0.trimmingCharacters(in: .whitespaces)
        }
        guard kv.count == 2 else { continue }
        switch kv[0].lowercased() {
        case "content-length": length = Int(kv[1])
        case "transfer-encoding": return 411
        default: break
        }
      }
      guard let length, length >= 0 else { return 411 }
      guard length <= FeedServer.maxBody else { return 413 }
      contentLength = length
      return 0
    }

    private func deliver(_ body: Data) {
      switch route {
      case "/hook":
        guard let event = try? HookEvent.decode(body) else { return finish(400) }
        onMessage(.hook(event))
      case "/status":
        guard let json = try? JSONDecoder().decode(JSONValue.self, from: body),
          case .object = json
        else { return finish(400) }
        onMessage(.status(body))
      default:
        return finish(404)
      }
      finish(200)
    }

    private func finish(_ status: Int) {
      guard !finished else { return }
      finished = true
      let reason: String
      switch status {
      case 200: reason = "OK"
      case 400: reason = "Bad Request"
      case 404: reason = "Not Found"
      case 405: reason = "Method Not Allowed"
      case 408: reason = "Request Timeout"
      case 411: reason = "Length Required"
      case 413: reason = "Payload Too Large"
      default: reason = "Error"
      }
      let response =
        "HTTP/1.1 \(status) \(reason)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
      conn.send(
        content: Data(response.utf8),
        completion: .contentProcessed { [conn] _ in conn.cancel() })
    }
  }
}
