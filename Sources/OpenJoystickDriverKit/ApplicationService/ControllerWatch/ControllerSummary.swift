import Foundation

/// One controller in `ojd controller list --json` and in the object of watch lines.
///
/// The serial number is never printed; `hasSerialNumber` says whether the controller reports one.
public struct ControllerSummary: Encodable, Equatable, Sendable {
  /// The session token; see ``ControllerSessionToken``.
  public let id: String
  /// The port key; see ``ControllerPortKey``.
  public let unit: String?
  /// The controller's name.
  public let name: String
  /// The USB vendor ID.
  public let vendorID: Int
  /// The USB product ID.
  public let productID: Int
  /// The connection type, such as USB or Bluetooth.
  public let connection: String
  /// The protocol family bound to the controller.
  public let `protocol`: String
  /// The state of the controller's session.
  public let session: String
  /// Whether the controller reports a serial number.
  public let hasSerialNumber: Bool
  /// Whether another client holds the controller's USB interface exclusively.
  public let ownedByAnotherClient: Bool
  /// The client that holds it; absent when none does or the interface names none.
  public let owner: USBExclusiveOwner?
  /// Whether the system also lists the controller as a second pad that gives no input.
  public let alsoListedBySystem: Bool
  /// Whether the controller has sent no input since its session started and waits for a press of
  /// its home button (``ControllerInputHealthFailureReason/guideNotPressed``).
  public let waitsForGuidePress: Bool
  /// Absent when the service reports no power state.
  public let power: ControllerConnectionState.Power?

  /// Creates the summary of the controller `device` describes.
  public init(_ device: ApplicationServiceDeviceDescription) {
    id = device.sessionToken.rawValue
    unit = device.portKey?.rawValue
    name = device.name
    vendorID = Int(device.vendorID)
    productID = Int(device.productID)
    connection = device.connection
    self.protocol = device.protocolBinding.rawValue
    session = device.sessionState.rawValue
    hasSerialNumber = device.serialNumber.map { !$0.isEmpty } ?? false
    ownedByAnotherClient = device.hidInputOwnership == .ownedByAnotherClient
    owner = device.inputOwner
    alsoListedBySystem = device.duplicateExposureRisk == .systemGameController
    waitsForGuidePress = device.inputHealth.failureReason == .guideNotPressed
    power = device.connectionState?.power
  }
}
