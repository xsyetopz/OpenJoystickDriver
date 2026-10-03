import Foundation

/// One controller in `ojd controller list --json` and on `connected` watch lines.
///
/// The serial number is never printed; `hasSerialNumber` says whether the controller reports one.
public struct ControllerSummary: Encodable, Equatable, Sendable {
  public let id: String
  /// The persistent unit ID; see ``UnitIdentity``.
  public let unit: String?
  public let name: String
  public let vendorID: Int
  public let productID: Int
  public let connection: String
  public let `protocol`: String
  public let session: String
  public let hasSerialNumber: Bool
  /// Absent when the service reports no power state.
  public let power: ControllerConnectionState.Power?

  public init(_ device: ApplicationServiceDeviceDescription) {
    id = device.runtimeIdentifier
    unit = device.unitIdentifier
    name = device.name
    vendorID = Int(device.vendorID)
    productID = Int(device.productID)
    connection = device.connection
    self.protocol = device.protocolBinding.rawValue
    session = device.sessionState.rawValue
    hasSerialNumber = device.serialNumber.map { !$0.isEmpty } ?? false
    power = device.connectionState?.power
  }
}
