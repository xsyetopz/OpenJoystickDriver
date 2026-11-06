import Foundation

/// How a person or a client names a controller: by one attachment, by the port it is plugged
/// into, or by its model.
///
/// The text form is the session token (`E-…`), the port key (`U-…`), or the model as `VVVV:PPPP`.
/// A model reference names every connected unit of that model.
public enum ControllerReference: Hashable, Sendable {
  /// Names one attachment of a controller by its session token.
  case session(ControllerSessionToken)
  /// Names the controller on one port by its port key.
  case port(ControllerPortKey)
  /// Names every connected unit of one model.
  case model(ControllerModelID)

  /// The reference written as `text`, or nil when `text` is none of the three forms.
  public init?(_ text: String) {
    if let token = ControllerSessionToken(rawValue: text) {
      self = .session(token)
    } else if let portKey = ControllerPortKey(rawValue: text) {
      self = .port(portKey)
    } else if let model = ControllerModelID(text) {
      self = .model(model)
    } else {
      return nil
    }
  }

  /// The text form: the token, the port key, or `VVVV:PPPP`.
  public var text: String {
    switch self {
    case .session(let token): token.rawValue
    case .port(let portKey): portKey.rawValue
    case .model(let model): model.description
    }
  }
}

extension ControllerReference: Codable {
  /// Decodes the text form; text that is none of the three forms fails to decode.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    let text = try container.decode(String.self)
    guard let reference = ControllerReference(text) else {
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "A controller reference is E-…, U-… or VVVV:PPPP."
      )
    }
    self = reference
  }

  /// Encodes the text form.
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(text)
  }
}

extension ControllerReference: CustomStringConvertible {
  /// The text form.
  public var description: String { text }
}

extension ControllerModelID {
  /// The model written as `VVVV:PPPP`, four hex digits each, case-insensitive; nil otherwise.
  public init?(_ text: String) {
    let parts = text.split(separator: ":", omittingEmptySubsequences: false)
    guard parts.count == 2, parts.allSatisfy({ $0.count == 4 && $0.allSatisfy(\.isHexDigit) }),
      let vendorID = UInt16(parts[0], radix: 16), let productID = UInt16(parts[1], radix: 16)
    else { return nil }
    self.init(vendorID: vendorID, productID: productID)
  }
}
