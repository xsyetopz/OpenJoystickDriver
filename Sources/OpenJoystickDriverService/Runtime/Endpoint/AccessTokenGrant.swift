import CryptoKit
import Foundation
import OpenJoystickDriverKit
import Security

/// A named secret that lets a client use the endpoint without a signature check, such as a
/// script or a browser overlay; `AccessGrants.json` keeps only its SHA-256.
struct AccessTokenGrant: Codable, Equatable, Sendable {
  let name: String
  /// Lowercase hex.
  let tokenSHA256: String
  /// The web origins, as `scheme://host[:port]`, whose pages may use the token on the WebSocket;
  /// empty for a token that works only on the Unix socket.
  let origins: [String]
  /// Sorted, without repeats.
  let scopes: [EndpointScope]
  let grantedAt: String
  /// Set whenever the grant holds `control`, marking it as granted after the scope worked; a file
  /// with a `control` scope but no mark is damaged.
  let controlGrantedAt: String?

  init(
    name: String,
    tokenSHA256: String,
    origins: [String],
    scopes: [EndpointScope],
    grantedAt: String
  ) {
    self.name = name
    self.tokenSHA256 = tokenSHA256
    self.origins = origins
    self.scopes = scopes
    self.grantedAt = grantedAt
    controlGrantedAt = scopes.contains(.control) ? grantedAt : nil
  }

  var id: String { "token:\(name)" }

  var summary: AccessTokenSummary {
    AccessTokenSummary(name: name, origins: origins, scopes: scopes, grantTime: grantedAt)
  }

  /// `ojd_` and 32 random bytes in unpadded base64url.
  static func makeToken() -> String { "ojd_" + randomBase64URL() }

  /// 32 random bytes in unpadded base64url.
  static func randomBase64URL() -> String {
    var bytes = [UInt8](repeating: 0, count: 32)
    precondition(SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess)
    return Data(bytes).base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }

  static func hash(_ token: String) -> String {
    SHA256.hash(data: Data(token.utf8)).map { String(format: "%02x", $0) }.joined()
  }

  /// 1 to 64 ASCII letters, digits, `.`, `_`, or `-`.
  static func isValidName(_ name: String) -> Bool {
    (1...64).contains(name.utf8.count)
      && name.utf8.allSatisfy { $0.isASCIIAlphanumeric || "._-".utf8.contains($0) }
  }

  static func isValidHash(_ hash: String) -> Bool {
    hash.utf8.count == 64 && hash.utf8.allSatisfy { "0123456789abcdef".utf8.contains($0) }
  }

  /// `origin` as `scheme://host[:port]` with a lowercase http or https scheme and host and no
  /// default port; nil for anything else, such as `null`, a file URL, or a URL with a path.
  static func normalizedOrigin(_ origin: String) -> String? {
    guard let components = URLComponents(string: origin),
      let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
      let host = components.host?.lowercased(), !host.isEmpty,
      components.user == nil, components.password == nil, components.query == nil,
      components.fragment == nil, ["", "/"].contains(components.path)
    else { return nil }
    let bracketed = host.contains(":") ? "[\(host)]" : host
    let defaultPort = scheme == "http" ? 80 : 443
    guard let port = components.port, port != defaultPort else { return "\(scheme)://\(bracketed)" }
    return "\(scheme)://\(bracketed):\(port)"
  }

  /// Whether `proof` is the lowercase hex HMAC-SHA256 of the hello message, keyed with the
  /// token's SHA-256; compared in constant time. `origin` and `port` are empty on the socket.
  func accepts(proof: String, nonce: String, origin: String, port: String) -> Bool {
    guard let key = Self.bytes(hex: tokenSHA256), let code = Self.bytes(hex: proof),
      code.count == 32
    else { return false }
    let message = ["OpenJoystickDriver endpoint hello 1", nonce, origin, port]
      .map { $0 + "\n" }.joined()
    return HMAC<SHA256>.isValidAuthenticationCode(
      code,
      authenticating: Data(message.utf8),
      using: SymmetricKey(data: key)
    )
  }

  /// The bytes of lowercase hex; nil for anything else.
  private static func bytes(hex: String) -> Data? {
    let digits = Array(hex.utf8)
    guard digits.count.isMultiple(of: 2) else { return nil }
    var data = Data(capacity: digits.count / 2)
    for index in stride(from: 0, to: digits.count, by: 2) {
      guard let high = hexValue(digits[index]), let low = hexValue(digits[index + 1]) else {
        return nil
      }
      data.append(high << 4 | low)
    }
    return data
  }

  private static func hexValue(_ digit: UInt8) -> UInt8? {
    switch digit {
    case 0x30...0x39: digit - 0x30
    case 0x61...0x66: digit - 0x61 + 10
    default: nil
    }
  }

  /// Whether the file could have written this grant.
  var isValid: Bool {
    Self.isValidName(name) && Self.isValidHash(tokenSHA256) && !scopes.isEmpty
      && origins.allSatisfy { Self.normalizedOrigin($0) == $0 }
  }
}

/// The WebSocket's switch and port; off by default.
package struct AccessWebSettings: Codable, Equatable, Sendable {
  package static let ports = 1_024...65_535

  var enabled = false
  /// Nil until the first enable, which saves the port the system picked unless one was given.
  var port: Int?
}

extension AccessGrantFile {
  /// Adds a token grant; returns its token, which is not stored, and the grant.
  @discardableResult
  mutating func grantToken(
    name: String,
    origins: [String],
    scopes: [EndpointScope],
    at date: Date
  ) throws -> (token: String, grant: AccessTokenGrant) {
    guard AccessTokenGrant.isValidName(name) else {
      throw AccessGrantStoreError.invalidTokenName(name)
    }
    guard !tokens.contains(where: { $0.name == name }) else {
      throw AccessGrantStoreError.duplicateToken(name)
    }
    guard !scopes.isEmpty else { throw AccessGrantStoreError.noScope }
    guard origins.isEmpty || !scopes.contains(.control) else {
      throw AccessGrantStoreError.originsWithControl
    }
    var normalized: [String] = []
    for origin in origins {
      guard let value = AccessTokenGrant.normalizedOrigin(origin) else {
        throw AccessGrantStoreError.invalidOrigin(origin)
      }
      if !normalized.contains(value) { normalized.append(value) }
    }
    let token = AccessTokenGrant.makeToken()
    let grant = AccessTokenGrant(
      name: name,
      tokenSHA256: AccessTokenGrant.hash(token),
      origins: normalized,
      scopes: Array(Set(scopes)).sorted(),
      grantedAt: ISO8601DateFormatter().string(from: date)
    )
    tokens.append(grant)
    return (token, grant)
  }

  /// Removes `scopes`, or every scope when nil; returns the grant left, or nil when none is.
  mutating func revokeToken(id: String, scopes: [EndpointScope]?) throws -> AccessTokenGrant? {
    guard let index = tokens.firstIndex(where: { $0.id == id }) else {
      throw AccessGrantStoreError.unknownClient(id)
    }
    let grant = tokens[index]
    let remaining = scopes.map { revoked in grant.scopes.filter { !revoked.contains($0) } } ?? []
    guard !remaining.isEmpty else {
      tokens.remove(at: index)
      return nil
    }
    tokens[index] = AccessTokenGrant(
      name: grant.name,
      tokenSHA256: grant.tokenSHA256,
      origins: grant.origins,
      scopes: remaining,
      grantedAt: grant.grantedAt
    )
    return tokens[index]
  }

  /// Whether the token grants and the web settings could have been written by the service.
  var hasValidTokensAndWeb: Bool {
    tokens.allSatisfy(\.isValid) && Set(tokens.map(\.name)).count == tokens.count
      && web.port.map(AccessWebSettings.ports.contains) ?? !web.enabled
  }
}

extension UInt8 {
  var isASCIIAlphanumeric: Bool {
    (0x30...0x39).contains(self) || (0x41...0x5A).contains(self) || (0x61...0x7A).contains(self)
  }
}
