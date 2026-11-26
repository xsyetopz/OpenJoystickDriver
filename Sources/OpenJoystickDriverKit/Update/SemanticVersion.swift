import Foundation

/// A SemVer 2.0.0 version, ordered by precedence.
///
/// A prerelease ranks below its release. Build metadata does not take part in the order.
public struct SemanticVersion: Comparable, Equatable, Sendable {
  /// The major number.
  public let major: Int
  /// The minor number.
  public let minor: Int
  /// The patch number.
  public let patch: Int
  /// The dot-separated prerelease identifiers; empty for a release.
  public let prerelease: [String]

  /// Parses `value`, a SemVer version with an optional `v` prefix; build metadata is checked and
  /// dropped.
  ///
  /// Returns nil when `value` is not a valid version.
  public init?(_ value: String) {
    var version = value
    if version.first == "v" || version.first == "V" { version.removeFirst() }
    guard let withoutBuild = Self.removingBuildMetadata(version) else { return nil }

    let versionAndPrerelease = withoutBuild.split(
      separator: "-",
      maxSplits: 1,
      omittingEmptySubsequences: false
    )
    guard let core = versionAndPrerelease.first, let numbers = Self.parseCore(core) else {
      return nil
    }
    var identifiers: [String] = []
    if versionAndPrerelease.count == 2 {
      guard let parsed = Self.parsePrerelease(versionAndPrerelease[1]) else { return nil }
      identifiers = parsed
    }

    self.major = numbers.major
    self.minor = numbers.minor
    self.patch = numbers.patch
    self.prerelease = identifiers
  }

  /// Returns `version` without its `+` build metadata, or nil when the metadata is invalid.
  private static func removingBuildMetadata(_ version: String) -> String? {
    guard let buildStart = version.firstIndex(of: "+") else { return version }
    let build = String(version[version.index(after: buildStart)...])
    guard Self.isValidBuildMetadata(build) else { return nil }
    return String(version[..<buildStart])
  }

  /// Parses the `MAJOR.MINOR.PATCH` core, or returns nil when a number is not a valid identifier
  /// or does not fit an `Int`.
  private static func parseCore(
    _ core: Substring
  ) -> (major: Int, minor: Int, patch: Int)? {
    let numbers = core.split(separator: ".", omittingEmptySubsequences: false)
    guard numbers.count == 3, Self.isValidNumericIdentifier(String(numbers[0])),
      Self.isValidNumericIdentifier(String(numbers[1])),
      Self.isValidNumericIdentifier(String(numbers[2])), let majorNumber = Int(numbers[0]),
      let minorNumber = Int(numbers[1]), let patchNumber = Int(numbers[2]),
      majorNumber >= 0, minorNumber >= 0, patchNumber >= 0
    else { return nil }
    return (majorNumber, minorNumber, patchNumber)
  }

  /// Parses the dot-separated prerelease identifiers, or returns nil when one is invalid.
  private static func parsePrerelease(_ text: Substring) -> [String]? {
    let identifiers = text.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
    guard !identifiers.isEmpty, identifiers.allSatisfy(Self.isValidIdentifier) else { return nil }
    return identifiers
  }

  /// Whether `lhs` has lower precedence than `rhs`.
  public static func < (lhs: Self, rhs: Self) -> Bool {
    if lhs.major != rhs.major { return lhs.major < rhs.major }
    if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
    if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }
    return comparePrerelease(lhs.prerelease, rhs.prerelease) == .orderedAscending
  }

  /// Compares two lists of prerelease identifiers; an empty list is a release and ranks above any
  /// prerelease.
  private static func comparePrerelease(_ lhs: [String], _ rhs: [String]) -> ComparisonResult {
    if lhs.isEmpty, rhs.isEmpty { return .orderedSame }
    if lhs.isEmpty { return .orderedDescending }
    if rhs.isEmpty { return .orderedAscending }

    for index in 0..<min(lhs.count, rhs.count) {
      let comparison = compareIdentifier(lhs[index], rhs[index])
      if comparison != .orderedSame { return comparison }
    }

    if lhs.count == rhs.count { return .orderedSame }
    return lhs.count < rhs.count ? .orderedAscending : .orderedDescending
  }

  /// Compares two prerelease identifiers: numbers by value and below text, text by ASCII order.
  private static func compareIdentifier(_ lhs: String, _ rhs: String) -> ComparisonResult {
    let lhsIsNumber = Self.isNumericIdentifier(lhs)
    let rhsIsNumber = Self.isNumericIdentifier(rhs)

    switch (lhsIsNumber, rhsIsNumber) {
    case (true, true):
      if lhs.count != rhs.count {
        return lhs.count < rhs.count ? .orderedAscending : .orderedDescending
      }
      return Self.comparePOSIX(lhs, rhs)
    case (true, false): return .orderedAscending
    case (false, true): return .orderedDescending
    case (false, false): return Self.comparePOSIX(lhs, rhs)
    }
  }

  /// The ordering of `lhs` and `rhs` as text in the `en_US_POSIX` locale.
  private static func comparePOSIX(_ lhs: String, _ rhs: String) -> ComparisonResult {
    let comparison = lhs.compare(
      rhs,
      options: [],
      range: nil,
      locale: Locale(identifier: "en_US_POSIX")
    )
    if comparison == .orderedSame { return .orderedSame }
    return comparison == .orderedAscending ? .orderedAscending : .orderedDescending
  }

  /// Whether `identifier` is a valid prerelease identifier.
  private static func isValidIdentifier(_ identifier: String) -> Bool {
    guard !identifier.isEmpty else { return false }
    guard identifier.unicodeScalars.allSatisfy(Self.isValidIdentifierScalar) else { return false }
    return !Self.isNumericIdentifierWithLeadingZero(identifier)
  }

  /// Whether `buildMetadata` is a list of valid build identifiers.
  private static func isValidBuildMetadata(_ buildMetadata: String) -> Bool {
    let identifiers = buildMetadata.split(separator: ".", omittingEmptySubsequences: false).map(
      String.init
    )
    return !identifiers.isEmpty
      && identifiers.allSatisfy { identifier in
        !identifier.isEmpty && identifier.unicodeScalars.allSatisfy(Self.isValidIdentifierScalar)
      }
  }

  /// Whether `identifier` is a number without a leading zero.
  private static func isValidNumericIdentifier(_ identifier: String) -> Bool {
    Self.isNumericIdentifier(identifier) && !Self.isNumericIdentifierWithLeadingZero(identifier)
  }

  /// Whether `identifier` holds only digits.
  private static func isNumericIdentifier(_ identifier: String) -> Bool {
    !identifier.isEmpty
      && identifier.unicodeScalars.allSatisfy { scalar in ("0"..."9").contains(scalar) }
  }

  /// Whether `identifier` is a number with a leading zero.
  private static func isNumericIdentifierWithLeadingZero(_ identifier: String) -> Bool {
    identifier.count > 1 && identifier.first == "0" && Self.isNumericIdentifier(identifier)
  }

  /// Whether `scalar` is allowed in an identifier: a letter, a digit or a hyphen.
  private static func isValidIdentifierScalar(_ scalar: Unicode.Scalar) -> Bool {
    ("0"..."9").contains(scalar) || ("A"..."Z").contains(scalar) || ("a"..."z").contains(scalar)
      || scalar == "-"
  }
}
