public import Foundation

/// A family that a description document names and OJD does not build in.
public struct DocumentedProtocolFamily: Sendable {
  /// The family name, such as `VendorAcmePad`.
  public let name: String
  /// The name as the document gives it.
  public let displayName: String
  /// The description file.
  public let file: URL
  /// The package that holds the file; nil for the user's `Protocols` folder and for a bundled
  /// family.
  public let package: String?
  /// Whether the file is bundled with the app.
  public let isBundled: Bool
  /// The decoded document.
  let description: ProtocolDescription
}

/// The families that description documents name and OJD does not build in.
///
/// Each owner, such as the user's folder, holds the families it loaded; registering again for the
/// same owner replaces them. The app bundles some families too. A family is documented while an
/// owner or the bundle holds it, and an owner's family of a name replaces the bundled one.
public enum DocumentedProtocolFamilies {
  /// The loaded families by owner.
  private static let owners = Locked<[URL: [DocumentedProtocolFamily]]>([:])

  /// The families bundled with the app: the `Resources/Protocols` files that are named like a
  /// family, because a built-in description's file name is kebab-case.
  private static let bundled: [DocumentedProtocolFamily] = {
    let urls = Bundle.module.urls(forResourcesWithExtension: "plist", subdirectory: nil) ?? []
    return urls.filter { isFamilyFileName($0) }.sorted {
      $0.lastPathComponent < $1.lastPathComponent
    }
    .map {
      do { return try read($0, isBundled: true) } catch {
        fatalError("[ProtocolDescription] Invalid bundled documented family: \(error)")
      }
    }
  }()

  /// Whether the stem of `file` has the shape of a family name.
  private static func isFamilyFileName(_ file: URL) -> Bool {
    file.deletingPathExtension().lastPathComponent
      .range(of: "\\A[A-Z][A-Za-z0-9]*\\z", options: .regularExpression) != nil
  }

  /// The bundled families that no family of `held` replaces.
  static func bundled(besides held: [DocumentedProtocolFamily]) -> [DocumentedProtocolFamily] {
    let names = Set(held.map(\.name))
    return bundled.filter { !names.contains($0.name) }
  }

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
    let held = owners.withLock { $0.values.flatMap { $0 } }
    return (held + bundled(besides: held)).sorted { $0.name < $1.name }
  }
}
