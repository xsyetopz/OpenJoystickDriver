import Foundation

/// One attachment of a controller: issued when the controller attaches and never reused.
///
/// A session token is `E-` and 16 base64url characters of random bytes. It says nothing about the
/// controller's model, serial number or port, and a reconnect gets a different token even on the
/// same port. Tokens are not persisted.
public struct ControllerSessionToken: Hashable, Sendable {
  /// The prefix of every session token.
  static let prefix = "E-"

  /// The text form: `E-` and 16 base64url characters.
  public let rawValue: String

  /// The session token written as `text`, or nil when `text` is not `E-` and 16 base64url
  /// characters.
  public init?(rawValue text: String) {
    guard PrefixedIdentifierText.isWellFormed(text, prefix: Self.prefix) else { return nil }
    rawValue = text
  }

  /// Issues a token from 12 random bytes.
  public static func issue() -> Self {
    var generator = SystemRandomNumberGenerator()
    let bytes = (0..<PrefixedIdentifierText.byteCount).map { _ in
      UInt8.random(in: .min ... .max, using: &generator)
    }
    guard
      let token = Self(
        rawValue: PrefixedIdentifierText.make(prefix: prefix, bytes: bytes)
      )
    else { preconditionFailure("12 bytes always encode as 16 base64url characters") }
    return token
  }
}

extension ControllerSessionToken: Codable {
  /// Decodes the text form; text that is not a session token fails to decode.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    let text = try container.decode(String.self)
    guard let token = ControllerSessionToken(rawValue: text) else {
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "A session token is E- and 16 base64url characters."
      )
    }
    self = token
  }

  /// Encodes the text form.
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

extension ControllerSessionToken: CustomStringConvertible {
  /// The text form.
  public var description: String { rawValue }
}
