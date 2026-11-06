import Foundation

/// State of the user-space virtual output backend as the service reports it.
///
/// `wireValue` is the only formatter and `init(wireValue:)` the only parser; payloads encode the
/// status as that single string.
public enum VirtualOutputBackendStatus: Sendable, Equatable, Codable {
  /// No backend is live.
  case off
  /// A backend is live and reports this status, for example `automatic, targets: xbox-one`.
  case backend(String)
  /// The backend failed with this message.
  case error(String)

  /// The wire value of `off`.
  private static let offValue = "off"
  /// The start of the wire value of the error status.
  private static let errorPrefix = "error:"

  /// The one string that carries the status in payloads: `off`, the backend's own text, or `error:`
  /// and a message.
  public var wireValue: String {
    switch self {
    case .off: Self.offValue
    case .backend(let status): status
    case .error(let message): "\(Self.errorPrefix) \(message)"
    }
  }

  /// Whether the status is an error.
  public var isError: Bool {
    if case .error = self { return true }
    return false
  }

  /// Parses `wireValue`; every string that is not `off` or an `error:` message is a backend status.
  public init(wireValue: String) {
    if wireValue == Self.offValue {
      self = .off
    } else if wireValue.hasPrefix(Self.errorPrefix) {
      let message = wireValue.dropFirst(Self.errorPrefix.count)
      self = .error(String(message.hasPrefix(" ") ? message.dropFirst() : message))
    } else {
      self = .backend(wireValue)
    }
  }

  /// Decodes the value from `decoder`.
  public init(from decoder: any Decoder) throws {
    self.init(wireValue: try decoder.singleValueContainer().decode(String.self))
  }

  /// Encodes the value into `encoder`.
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(wireValue)
  }
}
