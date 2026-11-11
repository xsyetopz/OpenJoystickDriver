public import Foundation

/// A family that a description document names and OJD does not build in.
public struct DocumentedProtocolFamily: Sendable {
  /// The family name, such as `VendorAcmePad`.
  public let name: String
  /// The name as the document gives it.
  public let displayName: String
  /// The description file.
  public let file: URL
  /// The package that holds the file; nil for the user's `Protocols` folder.
  public let package: String?
  /// The decoded document.
  let description: ProtocolDescription
}

/// The families that description documents name and OJD does not build in.
///
/// Each owner, such as the user's folder, holds the families it loaded; registering again for the
/// same owner replaces them. A family is documented while any owner holds it.
public enum DocumentedProtocolFamilies {
  /// The loaded families by owner.
  private static let owners = Locked<[URL: [DocumentedProtocolFamily]]>([:])

  /// Makes `families` the documented families of `owner`.
  static func register(_ families: [DocumentedProtocolFamily], owner: URL) {
    owners.withLock { $0[owner] = families }
  }

  /// The description of the documented family `name`, or nil.
  static func description(named name: String) -> ProtocolDescription? {
    families.first { $0.name == name }?.description
  }

  /// The descriptions of every documented family.
  static var all: [ProtocolDescription] { families.map(\.description) }

  /// Every documented family in family-name order.
  public static var families: [DocumentedProtocolFamily] {
    owners.withLock { $0.values.flatMap { $0 } }.sorted { $0.name < $1.name }
  }
}
