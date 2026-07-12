import Darwin
import Foundation

final class BrowserGamepadLocalServer: @unchecked Sendable {
  private static let maximumRequestBytes = 262_144
  private static let maximumSnapshotBytes = 131_072
  private static let maximumSnapshots = 12

  private let listeningSocket: Int32
  private let page: Data
  private let stateLock = NSLock()
  private var running = true
  private var submittedSnapshots: [Data] = []

  init(page: Data, port: UInt16) throws {
    self.page = page
    let socketDescriptor = socket(AF_INET, SOCK_STREAM, 0)
    guard socketDescriptor >= 0 else { throw Self.posixError(operation: "socket") }

    var reuseAddress: Int32 = 1
    guard setsockopt(
      socketDescriptor,
      SOL_SOCKET,
      SO_REUSEADDR,
      &reuseAddress,
      socklen_t(MemoryLayout.size(ofValue: reuseAddress))
    ) == 0 else {
      Darwin.close(socketDescriptor)
      throw Self.posixError(operation: "setsockopt")
    }

    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = in_port_t(port).bigEndian
    address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
    let bindResult = withUnsafePointer(to: &address) { pointer in
      pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        Darwin.bind(socketDescriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
      }
    }
    guard bindResult == 0 else {
      Darwin.close(socketDescriptor)
      throw Self.posixError(operation: "bind")
    }
    guard Darwin.listen(socketDescriptor, 8) == 0 else {
      Darwin.close(socketDescriptor)
      throw Self.posixError(operation: "listen")
    }
    listeningSocket = socketDescriptor
  }

  deinit { stop() }

  var snapshotCount: Int { stateLock.withLock { submittedSnapshots.count } }

  func encodedSnapshots() throws -> Data {
    let objects = try stateLock.withLock {
      try submittedSnapshots.map { try JSONSerialization.jsonObject(with: $0) }
    }
    return try JSONSerialization.data(
      withJSONObject: ["schemaVersion": 1, "snapshots": objects],
      options: [.prettyPrinted, .sortedKeys]
    )
  }

  func start() {
    Thread.detachNewThread { [weak self] in self?.acceptLoop() }
  }

  func stop() {
    let shouldClose = stateLock.withLock {
      guard running else { return false }
      running = false
      return true
    }
    if shouldClose {
      Darwin.shutdown(listeningSocket, SHUT_RDWR)
      Darwin.close(listeningSocket)
    }
  }

  private func acceptLoop() {
    while stateLock.withLock({ running }) {
      let client = Darwin.accept(listeningSocket, nil, nil)
      guard client >= 0 else {
        if errno == EINTR { continue }
        return
      }
      respond(to: client)
      Darwin.close(client)
    }
  }

  private func respond(to client: Int32) {
    var noSignal: Int32 = 1
    setsockopt(
      client,
      SOL_SOCKET,
      SO_NOSIGPIPE,
      &noSignal,
      socklen_t(MemoryLayout.size(ofValue: noSignal))
    )
    guard let request = receiveRequest(from: client) else { return }
    let response: Data
    if request.method == "GET"
      && (request.path == "/" || request.path == "/browser-gamepad.html")
    {
      response = Self.response(
        status: "200 OK",
        contentType: "text/html; charset=utf-8",
        body: page
      )
    } else if request.method == "POST", request.path == "/snapshot" {
      response = snapshotResponse(body: request.body)
    } else {
      response = Self.response(
        status: "404 Not Found",
        contentType: "text/plain; charset=utf-8",
        body: Data("Not found\n".utf8)
      )
    }
    send(response, to: client)
  }

  private func snapshotResponse(body: Data) -> Data {
    guard body.count <= Self.maximumSnapshotBytes,
      let object = try? JSONSerialization.jsonObject(with: body),
      let dictionary = object as? [String: Any],
      dictionary["schemaVersion"] as? Int == 1
    else {
      return Self.response(
        status: "400 Bad Request",
        contentType: "application/json",
        body: Data(#"{"accepted":false,"error":"invalid snapshot"}"#.utf8)
      )
    }

    let count = stateLock.withLock { () -> Int in
      if submittedSnapshots.count == Self.maximumSnapshots {
        submittedSnapshots.removeFirst()
      }
      submittedSnapshots.append(body)
      return submittedSnapshots.count
    }
    let body = Data(#"{"accepted":true,"count":\#(count)}"#.utf8)
    return Self.response(status: "202 Accepted", contentType: "application/json", body: body)
  }

  private struct Request {
    let method: String
    let path: String
    let body: Data
  }

  private func receiveRequest(from client: Int32) -> Request? {
    var data = Data()
    var headerEnd: Data.Index?
    var contentLength = 0

    while data.count < Self.maximumRequestBytes {
      var chunk = [UInt8](repeating: 0, count: 8_192)
      let received = chunk.withUnsafeMutableBytes {
        Darwin.recv(client, $0.baseAddress, $0.count, 0)
      }
      guard received > 0 else { break }
      data.append(contentsOf: chunk.prefix(received))

      if headerEnd == nil,
        let range = data.range(of: Data([13, 10, 13, 10]))
      {
        headerEnd = range.upperBound
        let headers = String(bytes: data[..<range.lowerBound], encoding: .utf8) ?? ""
        contentLength = Self.contentLength(in: headers)
      }
      if let headerEnd, data.count >= headerEnd + contentLength { break }
    }

    guard let headerEnd, data.count >= headerEnd + contentLength else { return nil }
    let headers = String(bytes: data[..<(headerEnd - 4)], encoding: .utf8) ?? ""
    guard let firstLine = headers.split(whereSeparator: \.isNewline).first else {
      return nil
    }
    let pieces = firstLine.split(separator: " ")
    guard pieces.count >= 2 else { return nil }
    return Request(
      method: String(pieces[0]),
      path: String(pieces[1]),
      body: data.subdata(in: headerEnd..<(headerEnd + contentLength))
    )
  }

  private static func contentLength(in headers: String) -> Int {
    for line in headers.split(whereSeparator: \.isNewline) {
      let parts = line.split(separator: ":", maxSplits: 1)
      if parts.count == 2,
        parts[0].trimmingCharacters(in: .whitespaces).lowercased() == "content-length"
      {
        return min(
          maximumSnapshotBytes,
          max(0, Int(parts[1].trimmingCharacters(in: .whitespaces)) ?? 0)
        )
      }
    }
    return 0
  }

  private func send(_ data: Data, to client: Int32) {
    data.withUnsafeBytes { bytes in
      guard let baseAddress = bytes.baseAddress else { return }
      var offset = 0
      while offset < bytes.count {
        let sent = Darwin.send(
          client,
          baseAddress.advanced(by: offset),
          bytes.count - offset,
          0
        )
        guard sent > 0 else { return }
        offset += sent
      }
    }
  }

  private static func response(status: String, contentType: String, body: Data) -> Data {
    let headers = [
      "HTTP/1.1 \(status)",
      "Content-Type: \(contentType)",
      "Content-Length: \(body.count)",
      "Cache-Control: no-store",
      "Content-Security-Policy: default-src 'self'; script-src 'self' 'unsafe-inline'; "
        + "style-src 'self' 'unsafe-inline'; connect-src 'self'; img-src 'none'; "
        + "object-src 'none'; base-uri 'none'; frame-ancestors 'none'",
      "X-Content-Type-Options: nosniff",
      "Connection: close", "", "",
    ].joined(separator: String(UnicodeScalar(13)) + String(UnicodeScalar(10)))
    var response = Data(headers.utf8)
    response.append(body)
    return response
  }

  private static func posixError(operation: String) -> NSError {
    let code = errno
    return NSError(
      domain: NSPOSIXErrorDomain,
      code: Int(code),
      userInfo: [
        NSLocalizedDescriptionKey:
          "\(operation) failed: \(String(cString: strerror(code)))",
      ]
    )
  }
}
