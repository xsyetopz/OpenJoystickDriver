import Foundation
import Security

/// The signing identifier and signer of a piece of code.
public struct CodeSigningIdentity: Codable, Equatable, Hashable, Sendable {
  /// Who signed the code.
  public enum Kind: String, Codable, Sendable {
    /// Signed with an Apple-issued developer certificate of `teamIdentifier`.
    case team
    /// Signed by Apple, such as a system tool.
    case apple
    /// Ad-hoc signed or not signed; any local process can claim this identity.
    case adHoc = "ad-hoc"
  }

  public let kind: Kind
  public let identifier: String
  public let teamIdentifier: String?

  public init(kind: Kind, identifier: String, teamIdentifier: String?) {
    self.kind = kind
    self.identifier = identifier
    self.teamIdentifier = teamIdentifier
  }

  /// The requirement that code with this identity satisfies; nil for ad-hoc code.
  public var requirementText: String? {
    let identifierClause = "identifier \(Self.quoted(identifier))"
    switch kind {
    case .team:
      guard let teamIdentifier else { return nil }
      return "\(identifierClause) and anchor apple generic and certificate leaf[subject.OU] = "
        + Self.quoted(teamIdentifier)
    case .apple: return "\(identifierClause) and anchor apple"
    case .adHoc: return nil
    }
  }

  /// The compiled `requirementText`; nil for ad-hoc code or a requirement that does not compile.
  public var requirement: SecRequirement? {
    guard let requirementText else { return nil }
    var requirement: SecRequirement?
    guard
      SecRequirementCreateWithString(requirementText as CFString, SecCSFlags(), &requirement)
        == errSecSuccess
    else { return nil }
    return requirement
  }

  /// The identity of this process; it does not change while the process runs.
  public static let current: Self? = {
    var code: SecCode?
    guard SecCodeCopySelf(SecCSFlags(), &code) == errSecSuccess, let code else { return nil }
    return of(code)
  }()

  /// The identity of running code.
  public static func of(_ code: SecCode) -> Self? {
    var staticCode: SecStaticCode?
    guard SecCodeCopyStaticCode(code, SecCSFlags(), &staticCode) == errSecSuccess, let staticCode
    else { return nil }
    return of(staticCode)
  }

  /// The identity of code on disk, such as an app bundle or a tool at a path.
  public static func of(_ staticCode: SecStaticCode) -> Self? {
    var information: CFDictionary?
    let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
    guard SecCodeCopySigningInformation(staticCode, flags, &information) == errSecSuccess,
      let values = information as? [String: Any],
      let identifier = values[kSecCodeInfoIdentifier as String] as? String
    else { return nil }
    let teamIdentifier = values[kSecCodeInfoTeamIdentifier as String] as? String
    for kind in [Kind.team, .apple] {
      let candidate = Self(
        kind: kind,
        identifier: identifier,
        teamIdentifier: teamIdentifier
      )
      if let requirement = candidate.requirement,
        SecStaticCodeCheckValidity(staticCode, SecCSFlags(), requirement) == errSecSuccess
      {
        return candidate
      }
    }
    return Self(kind: .adHoc, identifier: identifier, teamIdentifier: teamIdentifier)
  }

  /// The identity of the code at `url`; nil when the path holds no signed code.
  public static func of(path url: URL) -> Self? {
    var staticCode: SecStaticCode?
    guard SecStaticCodeCreateWithPath(url as CFURL, SecCSFlags(), &staticCode) == errSecSuccess,
      let staticCode
    else { return nil }
    return of(staticCode)
  }

  private static func quoted(_ value: String) -> String {
    let escaped = value.replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")
    return "\"\(escaped)\""
  }
}
