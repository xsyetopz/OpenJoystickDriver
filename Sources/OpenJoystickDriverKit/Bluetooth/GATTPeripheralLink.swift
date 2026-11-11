import Foundation

/// The `GATT` link of one Switch 2 controller: it carries notifications from a
/// ``GATTPeripheral`` into the hub as input and command-reply frames, and carries the hub's
/// writes back to the peripheral's command and vibration characteristics.
///
/// The owner of the peripheral calls ``admit()`` once the input and reply notifications are
/// enabled, ``notified(characteristic:value:)`` for each notification, and ``disconnected()``
/// when the peripheral goes.
public final class GATTPeripheralLink: Switch2BluetoothLEWriter, Sendable {
  /// The connected peripheral.
  public let peripheral: any GATTPeripheral
  /// The USB product ID of the controller model.
  public let productID: UInt16
  /// The name the peripheral advertises; nil when it advertises none.
  public let productName: String?
  /// The weak reference to the hub that this link feeds.
  private let hubReference: WeakHub
  /// The hub, while it exists.
  private var hub: Switch2BluetoothLEHub? { hubReference.hub }
  /// The UUID of the command characteristic.
  private let commandUUID: String
  /// The UUID of the model's vibration characteristic.
  private let vibrationUUID: String

  /// Returns nil when no controller record of `productID` declares a vibration characteristic.
  public init?(
    peripheral: any GATTPeripheral,
    productID: UInt16,
    productName: String?,
    hub: Switch2BluetoothLEHub
  ) {
    guard let characteristic = Switch2BluetoothLEProfile.vibrationUUID(productID: productID)
    else { return nil }
    self.peripheral = peripheral
    self.productID = productID
    self.productName = productName
    self.hubReference = WeakHub(hub: hub)
    self.commandUUID = Switch2BluetoothLEProfile.commandUUID
    self.vibrationUUID = characteristic
  }

  /// Presents the peripheral to the hub as a connected controller.
  public func admit() {
    hub?.linkConnected(
      peripheralID: peripheral.identifier,
      productID: productID,
      productName: productName,
      writer: self
    )
  }

  /// Delivers one notification.
  ///
  /// Input frames and command replies reach the hub; any other characteristic is ignored.
  public func notified(characteristic: String, value: [UInt8]) {
    switch characteristic.uppercased() {
    case Switch2BluetoothLEProfile.inputUUID:
      hub?.receivedInput(peripheralID: peripheral.identifier, bytes: value)
    case Switch2BluetoothLEProfile.commandReplyUUID:
      hub?.receivedReply(peripheralID: peripheral.identifier, bytes: value)
    default:
      break
    }
  }

  /// Tells the hub that the link is gone.
  public func disconnected() { hub?.linkDisconnected(peripheralID: peripheral.identifier) }

  /// Writes `bytes` to the command characteristic without a response; returns whether the write was
  /// accepted.
  public func writeCommand(_ bytes: [UInt8]) -> Bool {
    peripheral.writeWithoutResponse(bytes, to: commandUUID)
  }

  /// Writes `bytes` to the vibration characteristic without a response; returns whether the write
  /// was accepted.
  public func writeVibration(_ bytes: [UInt8]) -> Bool {
    peripheral.writeWithoutResponse(bytes, to: vibrationUUID)
  }
}

/// Holds the hub weakly, because the hub holds the link as the connection's writer.
///
/// The hub is itself `@unchecked Sendable`, and a weak reference only ever clears.
private struct WeakHub: @unchecked Sendable {
  /// The hub; clears when the hub is released.
  weak var hub: Switch2BluetoothLEHub?
}
