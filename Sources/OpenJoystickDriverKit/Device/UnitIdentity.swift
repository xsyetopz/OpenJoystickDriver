import CryptoKit
import Foundation

/// Persistent selectors for one controller unit: the model, the USB port it is plugged into, and
/// the interface it is reached through.
///
/// A unit ID is `U-` and an HMAC of `vid:pid:locationID:interface` under a key that is created
/// once per installation and kept in the service's defaults. It stays the same across reconnects
/// and service restarts while the controller uses the same port, and changes when it moves to
/// another port. It never includes the serial number. A controller with no location ID has no
/// unit ID.
public enum UnitIdentity {
  /// The defaults key that holds the installation's 32-byte key.
  public static let defaultsKey = "UnitIdentityKey"

  /// Swift initializes a static `let` once, on first use, so concurrent first calls share it.
  private static let installationKey = key(in: .standard)
  // Output routing and profile selection ask for unit IDs repeatedly, and each is an HMAC.
  private static let identifiers = Locked<[DeviceIdentifier: String?]>([:])

  /// Whether `text` has the form of a unit ID: `U-` and 16 base64url characters.
  public static func isWellFormed(_ text: String) -> Bool {
    let body = text.utf8.dropFirst(2)
    return text.hasPrefix("U-") && body.count == 16
      && body.allSatisfy {
        (0x30...0x39).contains($0) || (0x41...0x5A).contains($0) || (0x61...0x7A).contains($0)
          || $0 == 0x2D || $0 == 0x5F
      }
  }

  /// The unit ID of `identifier` under the installation key; nil without a location ID.
  public static func identifier(for identifier: DeviceIdentifier) -> String? {
    if let cached = identifiers.withLock({ $0[identifier] }) { return cached }
    let unit = self.identifier(for: identifier, key: installationKey)
    identifiers.withLock { $0[identifier] = unit }
    return unit
  }

  /// The unit ID of `identifier` under `key`; nil without a location ID.
  public static func identifier(for identifier: DeviceIdentifier, key: SymmetricKey) -> String? {
    guard let locationID = identifier.locationID else { return nil }
    let identity = identifier.controllerIdentity
    let interface = identifier.interfaceNumber.map { String(format: "%02X", $0) } ?? "-"
    let preimage = String(
      format: "%04X:%04X:%08X:%@",
      identity.vendorID,
      identity.productID,
      locationID,
      interface
    )
    let digest = Data(HMAC<SHA256>.authenticationCode(for: Data(preimage.utf8), using: key))
    // 12 bytes are 16 base64url characters, short enough to type.
    return "U-"
      + digest.prefix(12).base64EncodedString().replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
  }

  /// The key stored in `defaults`, created and stored there when it is absent or malformed.
  public static func key(in defaults: UserDefaults) -> SymmetricKey {
    if let data = defaults.data(forKey: defaultsKey), data.count == 32 {
      return SymmetricKey(data: data)
    }
    let key = SymmetricKey(size: .bits256)
    defaults.set(key.withUnsafeBytes { Data($0) }, forKey: defaultsKey)
    return key
  }
}

extension DeviceIdentifier {
  /// The persistent unit ID of this controller; nil without a location ID. See ``UnitIdentity``.
  public var unitIdentifier: String? { UnitIdentity.identifier(for: self) }
}
