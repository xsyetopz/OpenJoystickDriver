import Foundation
import Security

extension XPCService {
  static func authorizedClientDescription(_ connection: NSXPCConnection) -> String? {
    guard connection.effectiveUserIdentifier == geteuid() else { return nil }

    let pid = connection.processIdentifier
    var guest: SecCode?
    let attributes = [kSecGuestAttributePid as String: pid] as CFDictionary
    guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &guest) == errSecSuccess,
      let guest
    else {
      return nil
    }

    var staticCode: SecStaticCode?
    var signingInfo: CFDictionary?
    guard SecCodeCopyStaticCode(guest, SecCSFlags(), &staticCode) == errSecSuccess,
      let staticCode,
      SecCodeCopySigningInformation(staticCode, SecCSFlags(), &signingInfo) == errSecSuccess,
      let info = signingInfo as? [String: Any],
      let identifier = info[kSecCodeInfoIdentifier as String] as? String,
      allowedClientBundleIdentifiers.contains(identifier)
    else {
      return nil
    }

    return "\(identifier) pid=\(pid)"
  }

  private static let allowedClientBundleIdentifiers: Set<String> = [
    "com.openjoystickdriver"
  ]
}
