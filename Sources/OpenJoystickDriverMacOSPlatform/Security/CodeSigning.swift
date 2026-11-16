package import Foundation
package import OpenJoystickDriverKit
package import Security

extension CodeSigningIdentity {
  /// The compiled `requirementText`; nil for ad-hoc code or a requirement that does not compile.
  package var requirement: SecRequirement? {
    guard let requirementText else { return nil }
    var compiled: SecRequirement?
    guard
      unsafe SecRequirementCreateWithString(requirementText as CFString, SecCSFlags(), &compiled)
        == errSecSuccess
    else { return nil }
    return compiled
  }

  /// The identity of this process; it does not change while the process runs.
  package static let current: Self? = {
    var code: SecCode?
    guard unsafe SecCodeCopySelf(SecCSFlags(), &code) == errSecSuccess, let code else { return nil }
    return of(code)
  }()

  /// The identity of running code.
  package static func of(_ code: SecCode) -> Self? {
    var staticCode: SecStaticCode?
    guard unsafe SecCodeCopyStaticCode(code, SecCSFlags(), &staticCode) == errSecSuccess,
      let staticCode
    else { return nil }
    return of(staticCode)
  }

  /// The identity of code on disk, such as an app bundle or a tool at a path.
  package static func of(_ staticCode: SecStaticCode) -> Self? {
    var information: CFDictionary?
    let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
    guard unsafe SecCodeCopySigningInformation(staticCode, flags, &information) == errSecSuccess,
      let values = information as? [String: Any],
      let identifier = values[kSecCodeInfoIdentifier as String] as? String
    else { return nil }
    let publisherID = values[kSecCodeInfoTeamIdentifier as String] as? String
    for kind in [Kind.signed, .platform] {
      let candidate = Self(
        kind: kind,
        identifier: identifier,
        publisherID: publisherID
      )
      if let valid = candidate.requirement,
        SecStaticCodeCheckValidity(staticCode, SecCSFlags(), valid) == errSecSuccess
      {
        return candidate
      }
    }
    return Self(kind: .adHoc, identifier: identifier, publisherID: publisherID)
  }

  /// The identity of the code at `url`; nil when the path holds no signed code.
  package static func of(path url: URL) -> Self? {
    var staticCode: SecStaticCode?
    guard
      unsafe SecStaticCodeCreateWithPath(url as CFURL, SecCSFlags(), &staticCode) == errSecSuccess,
      let staticCode
    else { return nil }
    return of(staticCode)
  }
}

extension LocalSocketPeer {
  /// The running code of the peer, resolved by its audit token.
  package func code() -> SecCode? {
    let tokenData = withUnsafeBytes(of: auditToken) { unsafe Data($0) }
    let attributes = [kSecGuestAttributeAudit as String: tokenData] as CFDictionary
    var code: SecCode?
    guard
      unsafe SecCodeCopyGuestWithAttributes(nil, attributes, SecCSFlags(), &code) == errSecSuccess
    else { return nil }
    return code
  }

  /// True when the peer's code is valid and, if given, satisfies `requirement`.
  package func satisfies(_ requirement: SecRequirement?) -> Bool {
    guard let code = code() else { return false }
    return SecCodeCheckValidity(code, SecCSFlags(), requirement) == errSecSuccess
  }
}
