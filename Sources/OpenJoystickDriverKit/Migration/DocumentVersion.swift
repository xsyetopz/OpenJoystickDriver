/// Every `apiVersion` that OJD has written, oldest first; the last is the one it reads.
///
/// A version bump adds a case here and gives the case before it an ``upgrade`` when the bump
/// renames or reshapes a key. ``DocumentMigrator`` walks the cases from a document's version to
/// ``current``, applies each upgrade, and writes each next `apiVersion` itself, so a bump that
/// only adds keys needs no upgrade.
enum DocumentVersion: String, CaseIterable, Sendable {
  case v1alpha1 = "openjoystickdriver/v1alpha1"
  case v1alpha2 = "openjoystickdriver/v1alpha2"
  case v1alpha3 = "openjoystickdriver/v1alpha3"
  case v1alpha4 = "openjoystickdriver/v1alpha4"

  /// The version OJD reads and writes.
  static let current = Self.v1alpha4

  /// The start of every `apiVersion` of OpenJoystickDriver.
  static let prefix = "openjoystickdriver/"

  /// The version without ``prefix``, such as `v1alpha4`, which names its schema folder.
  var name: String { String(rawValue.dropFirst(Self.prefix.count)) }

  /// The conversion of a document of this version to the body of the next, or nil when the next
  /// version keeps every key of this one.
  var upgrade: (any DocumentUpgrade.Type)? {
    switch self {
    case .v1alpha1: V1Alpha1ToV1Alpha2.self
    case .v1alpha2: V1Alpha2ToV1Alpha3.self
    // `v1alpha4` adds keys only: the `unit` patch selector, `launchSettings`, and new values.
    case .v1alpha3: nil
    case .v1alpha4: nil
    }
  }

  /// `document`, of `kind` and this version, converted to ``current``.
  ///
  /// - Throws: ``DocumentMigrationProblem`` for a field that an upgrade cannot map.
  func migrate(_ document: OrderedJSON, kind: DocumentKind) throws -> OrderedJSON {
    let chain = Self.allCases.drop { $0 != self }
    var converted = document
    for (source, target) in zip(chain, chain.dropFirst()) {
      if let step = source.upgrade { converted = try step.convert(converted, kind: kind) }
      converted = try Self.stamped(converted, target)
    }
    return converted
  }

  /// `document` with `version` as its `apiVersion`.
  private static func stamped(_ document: OrderedJSON, _ version: Self) throws -> OrderedJSON {
    guard case .object(let members) = document else {
      throw DocumentMigrationProblem("the file is not a JSON object")
    }
    return .object(
      members.map { member in
        member.key == "apiVersion"
          ? .init(key: member.key, value: .string(version.rawValue))
          : member
      }
    )
  }
}

/// The conversion of a document's body from one ``DocumentVersion`` to the next.
///
/// An upgrade is a pure transform: it reads no file, holds no state, and leaves the `apiVersion`
/// to ``DocumentVersion/migrate(_:kind:)``. The readers stay single-version; only
/// ``DocumentMigrator`` applies upgrades.
protocol DocumentUpgrade {
  /// Converts `document` of `kind`.
  ///
  /// - Throws: ``DocumentMigrationProblem`` for a field that has no mechanical mapping.
  static func convert(_ document: OrderedJSON, kind: DocumentKind) throws -> OrderedJSON
}
