public import CryptoKit
import Foundation

/// The stable, user-facing slot of one controller: its model, the USB port it is plugged into,
/// and the interface it is reached through; or, for a Bluetooth LE controller, its model and the
/// peripheral identifier this Mac gave it.
///
/// A port key is `U-` and an HMAC under the installation key, which the service loads from its
/// private file `PortKeyInstallation.key` in the application data directory (see
/// ``PortKeyInstallationStore``). The HMAC covers `vid:pid:locationID:interface`,
/// `vid:pid:locationID:Pport` for an adapter port, or `vid:pid:BLE:identifier` for a Bluetooth LE
/// peripheral. It stays the same across reconnects and
/// service restarts while the controller uses the same port, or is the same peripheral, and changes
/// when it moves to another port. It never includes the serial number. A controller reached through
/// a raw USB service with no location ID has no port key.
public struct ControllerPortKey: Hashable, Sendable {
  /// The prefix of every port key.
  static let prefix = "U-"

  /// The text form: `U-` and 16 base64url characters.
  public let rawValue: String

  /// The port key written as `text`, or nil when `text` is not `U-` and 16 base64url characters.
  public init?(rawValue text: String) {
    guard PrefixedIdentifierText.isWellFormed(text, prefix: Self.prefix) else { return nil }
    rawValue = text
  }

  /// The port key of `controller` under `installationKey`; nil without a location ID or a
  /// Bluetooth LE peripheral identifier.
  public static func of(
    _ controller: LogicalControllerID,
    installationKey: SymmetricKey
  ) -> Self? {
    let model = controller.hardware.model
    let slot: String
    switch controller.address {
    case .ioKit(let locationID, let interfaceNumber):
      let interface = interfaceNumber.map { unsafe String(format: "%02X", $0) } ?? "-"
      slot = unsafe String(format: "%08X:%@", locationID, interface)
    case .adapterPort(let locationID, let port):
      slot = unsafe String(format: "%08X:P%u", locationID, UInt32(port))
    case .gattPeripheral(let identifier):
      slot = "BLE:\(identifier.uuidString)"
    case .usbService, nil:
      return nil
    }
    let preimage = unsafe String(format: "%04X:%04X:", model.vendorID, model.productID) + slot
    let digest = HMAC<SHA256>.authenticationCode(for: Data(preimage.utf8), using: installationKey)
    return Self(rawValue: PrefixedIdentifierText.make(prefix: prefix, bytes: digest))
  }
}

extension ControllerPortKey: Codable {
  /// Decodes the text form; text that is not a port key fails to decode.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    let text = try container.decode(String.self)
    guard let portKey = ControllerPortKey(rawValue: text) else {
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "A port key is U- and 16 base64url characters."
      )
    }
    self = portKey
  }

  /// Encodes the text form.
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

extension ControllerPortKey: CustomStringConvertible {
  /// The text form.
  public var description: String { rawValue }
}
