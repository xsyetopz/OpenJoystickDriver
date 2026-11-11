import Foundation

/// The signing identifier and signer of a piece of code.
public struct CodeSigningIdentity: Codable, Equatable, Hashable, Sendable {
  /// Who signed the code.
  public enum Kind: String, Codable, Sendable {
    /// Signed with a developer certificate of the publisher `publisherID`.
    case signed = "Signed"
    /// Signed by the platform vendor, such as a system tool.
    case platform = "Platform"
    /// Ad-hoc signed or not signed; any local process can claim this identity.
    case adHoc = "AdHoc"
  }

  /// The keys of the JSON encoding.
  private enum CodingKeys: String, CodingKey {
    /// The `publisher` key.
    case publisher
    /// The `identifier` key.
    case identifier
  }

  /// The `publisher` object of the encoding.
  private struct Publisher: Codable {
    /// Who signed the code.
    let kind: Kind
    /// The publisher's ID; nil when the kind has none.
    let id: String?
  }

  /// Decodes the value from `decoder`.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let publisher = try container.decode(Publisher.self, forKey: .publisher)
    self.init(
      kind: publisher.kind,
      identifier: try container.decode(String.self, forKey: .identifier),
      publisherID: publisher.id
    )
  }

  /// Encodes the value into `encoder`.
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(Publisher(kind: kind, id: publisherID), forKey: .publisher)
    try container.encode(identifier, forKey: .identifier)
  }

  /// Who signed the code.
  public let kind: Kind
  /// The code's signing identifier.
  public let identifier: String
  /// The publisher's ID: the signing team's identifier for a signed identity.
  public let publisherID: String?

  /// Creates an identity from its values.
  public init(kind: Kind, identifier: String, publisherID: String?) {
    self.kind = kind
    self.identifier = identifier
    self.publisherID = publisherID
  }

  /// The requirement that code with this identity satisfies; nil for ad-hoc code.
  public var requirementText: String? {
    let identifierClause = "identifier \(Self.quoted(identifier))"
    switch kind {
    case .signed:
      guard let publisherID else { return nil }
      return "\(identifierClause) and anchor apple generic and certificate leaf[subject.OU] = "
        + Self.quoted(publisherID)
    case .platform: return "\(identifierClause) and anchor apple"
    case .adHoc: return nil
    }
  }

  /// Wraps `value` in double quotes and escapes backslashes and quotes for a code requirement.
  private static func quoted(_ value: String) -> String {
    let escaped = value.replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")
    return "\"\(escaped)\""
  }
}
