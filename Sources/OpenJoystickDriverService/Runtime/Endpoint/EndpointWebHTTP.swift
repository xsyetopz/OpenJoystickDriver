import Darwin
import Foundation
import OpenJoystickDriverKit

/// The head of an HTTP/1.1 request on the WebSocket port.
struct EndpointWebRequest {
  enum ReadResult {
    /// `rest` holds the bytes that arrived after the head.
    case request(EndpointWebRequest, rest: Data)
    case malformed
    /// The peer closed or the deadline passed.
    case closed
  }

  let method: String
  /// The target without its query or fragment, still percent-encoded.
  let path: String
  /// Keyed by the lowercase name; a request that repeats a header is malformed.
  let headers: [String: String]

  /// Reads one request head of at most `EndpointServer.maximumRequestBytes`.
  static func read(_ descriptor: Int32, until deadline: Date) -> ReadResult {
    let end = Data("\r\n\r\n".utf8)
    var buffer = Data()
    var chunk = [UInt8](repeating: 0, count: 4_096)
    while true {
      if let range = buffer.range(of: end) {
        guard range.lowerBound <= EndpointServer.maximumRequestBytes,
          let head = String(bytes: buffer[..<range.lowerBound], encoding: .utf8),
          let request = parse(head)
        else { return .malformed }
        return .request(request, rest: Data(buffer[range.upperBound...]))
      }
      guard buffer.count <= EndpointServer.maximumRequestBytes else { return .malformed }
      let remaining = deadline.timeIntervalSinceNow
      guard remaining > 0,
        (try? LocalServiceRPCTransport.setTimeout(descriptor, seconds: remaining)) != nil
      else { return .closed }
      let count = Darwin.recv(descriptor, &chunk, chunk.count, 0)
      if count < 0, errno == EINTR { continue }
      guard count > 0 else { return .closed }
      buffer.append(contentsOf: chunk[0..<count])
    }
  }

  /// Whether `Host` names this port on `127.0.0.1`, which a page on a rebound DNS name cannot
  /// send. `localhost` is refused, because it can resolve to `::1`, where another user can
  /// listen on the same port.
  func isAddressed(toPort port: Int) -> Bool {
    guard let host = headers["host"]?.lowercased() else { return false }
    return host == "127.0.0.1:\(port)"
  }

  /// Whether the comma-separated header `name` lists `token`, ignoring case.
  func lists(_ token: String, in name: String) -> Bool {
    headers[name]?.split(separator: ",")
      .contains { $0.trimmingCharacters(in: .whitespaces).lowercased() == token } ?? false
  }

  private static func parse(_ head: String) -> Self? {
    let lines = head.components(separatedBy: "\r\n")
    let parts = lines[0].split(separator: " ", omittingEmptySubsequences: false)
    guard parts.count == 3, parts[2].hasPrefix("HTTP/1."), parts[1].hasPrefix("/") else {
      return nil
    }
    var headers: [String: String] = [:]
    for line in lines.dropFirst() {
      guard let colon = line.firstIndex(of: ":") else { return nil }
      let name = line[..<colon].lowercased()
      guard !name.isEmpty, !name.contains(where: \.isWhitespace), headers[name] == nil else {
        return nil
      }
      headers[name] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
    }
    return Self(
      method: String(parts[0]),
      path: String(parts[1].prefix { $0 != "?" && $0 != "#" }),
      headers: headers
    )
  }
}

enum EndpointWebResponse {
  private static let reasons = [
    101: "Switching Protocols", 200: "OK", 400: "Bad Request", 403: "Forbidden",
    404: "Not Found", 405: "Method Not Allowed", 426: "Upgrade Required",
  ]

  /// Writes a response; every status but 101 closes the connection after it.
  static func send(
    _ descriptor: Int32,
    status: Int,
    headers: [(String, String)] = [],
    body: Data = Data(),
    includeBody: Bool = true
  ) {
    let fields =
      status == 101
      ? headers
      : headers + [
        ("Content-Length", "\(body.count)"), ("X-Content-Type-Options", "nosniff"),
        ("Cache-Control", "no-store"), ("Connection", "close"),
      ]
    var head = "HTTP/1.1 \(status) \(reasons[status] ?? "Error")\r\n"
    for (name, value) in fields { head += "\(name): \(value)\r\n" }
    head += "\r\n"
    _ = endpointSendAll(descriptor, Data(head.utf8) + (includeBody ? body : Data()))
  }
}

/// Files in the overlay pages folder.
enum EndpointWebPages {
  /// The real path of the file that `path` names inside `root`; nil for a path with a dot
  /// component or an encoded slash, and for anything that resolves outside `root`.
  /// A folder serves its `index.html`.
  static func file(for path: String, root: String) -> String? {
    guard let base = resolved(root) else { return nil }
    var components = [base]
    for raw in path.split(separator: "/") {
      guard let part = String(raw).removingPercentEncoding, !part.hasPrefix("."),
        !part.contains("/"), !part.contains("\0")
      else { return nil }
      components.append(part)
    }
    if path.hasSuffix("/") { components.append("index.html") }
    guard var real = resolved(components.joined(separator: "/")) else { return nil }
    if kind(of: real) == S_IFDIR {
      guard let index = resolved(real + "/index.html") else { return nil }
      real = index
    }
    guard real.hasPrefix(base + "/"), kind(of: real) == S_IFREG else { return nil }
    return real
  }

  static func contentType(of path: String) -> String {
    switch URL(fileURLWithPath: path).pathExtension.lowercased() {
    case "html", "htm": "text/html; charset=utf-8"
    case "css": "text/css; charset=utf-8"
    case "js", "mjs": "text/javascript; charset=utf-8"
    case "json": "application/json"
    case "txt": "text/plain; charset=utf-8"
    case "png": "image/png"
    case "jpg", "jpeg": "image/jpeg"
    case "gif": "image/gif"
    case "webp": "image/webp"
    case "ico": "image/x-icon"
    case "woff2": "font/woff2"
    case "woff": "font/woff"
    default: "application/octet-stream"
    }
  }

  private static func resolved(_ path: String) -> String? {
    guard let pointer = realpath(path, nil) else { return nil }
    defer { free(pointer) }
    return String(cString: pointer)
  }

  private static func kind(of path: String) -> mode_t {
    var information = stat()
    guard stat(path, &information) == 0 else { return 0 }
    return information.st_mode & S_IFMT
  }
}
