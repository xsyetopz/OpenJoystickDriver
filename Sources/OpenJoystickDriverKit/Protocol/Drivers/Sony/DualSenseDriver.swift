import Foundation

let dualSenseAxisCenter: Float = 128
let dualSenseAxisPositiveMax: Float = 127
let dualSenseAxisNegativeMax: Float = 128
let dualSenseTriggerMax: Float = 255
let dualSenseUSBInputReportID: UInt8 = 0x01
let dualSenseUSBInputReportLength = 64
let dualSenseBluetoothInputReportID: UInt8 = 0x31
let dualSenseBluetoothInputReportLength = 78
let dualSenseBluetoothHIDInputTransaction: UInt8 = 0xA1
let dualSenseInputCRC32Seed: UInt8 = 0xA1
let dualSenseOutputCRC32Seed: UInt8 = 0xA2
let dualSenseUSBOutputReportID: UInt8 = 0x02
let dualSenseUSBOutputReportLength = 63
let dualSenseBluetoothOutputReportID: UInt8 = 0x31
let dualSenseBluetoothOutputReportLength = 78
let dualSenseOutputTag: UInt8 = 0x10
let dualSenseCompatibleVibrationFlags: UInt8 = 0x03
let dualSensePlayerIndicatorFlag: UInt8 = 0x10
let dualSenseLightbarFlag: UInt8 = 0x04
let dualSenseRightTriggerEffectFlag: UInt8 = 0x04
let dualSenseLeftTriggerEffectFlag: UInt8 = 0x08

enum DualSenseConnectionMode {
  case usb
  case bluetooth
}

public enum DualSenseDriverError: Error, Equatable { case invalidBluetoothCRC }

/// Driver for Sony DualSense controllers.
///
/// USB report ID `0x01` follows Linux `hid-playstation.c`'s
/// `struct dualsense_input_report`: four stick axes, two trigger axes,
/// sequence number, then button bytes, including the microphone mute button.
/// Bluetooth report `0x31` carries the same
/// common input report after its two-byte header and is accepted only when
/// its Linux-compatible CRC32 validates.
///
/// A controller with a non-Sony vendor ID runs in SDL's third-party mode; see
/// `DualSenseThirdPartyModel`.
public final class DualSenseDriver: PhysicalProtocolDriver {

  public let hasEdgeButtons: Bool
  /// The bound variant; a feature reply carries the Bluetooth CRC whenever this or the observed
  /// reports say Bluetooth.
  let isBluetoothVariant: Bool

  var motionCalibration = SonyMotionCalibration.nominal
  var sensorClock = SonySensorClock(mask: .max, tickNumerator: 1000)
  var state = ControllerState.neutral
  var connectionMode: DualSenseConnectionMode
  var outputSequence: UInt8 = 0

  /// Set for a non-Sony controller.
  let thirdParty: DualSenseThirdPartyModel?
  var features: DualSenseFeatures
  var usesAlternateReport = false
  var lastPacketSequence: UInt32?
  var lastLiveReportAt: UInt64?
  var dongleConnected = false
  var pendingConnectionState: ControllerInputConnectionState?

  /// Creates a new DualSense parser for the controller with `vendorID` and `productID`.
  public init(
    prefersBluetooth: Bool = false,
    hasEdgeButtons: Bool = false,
    vendorID: UInt16 = 0x054C,
    productID: UInt16 = 0
  ) {
    self.hasEdgeButtons = hasEdgeButtons
    isBluetoothVariant = prefersBluetooth
    connectionMode = prefersBluetooth ? .bluetooth : .usb
    let model =
      vendorID == dualSenseSonyVendorID
      ? nil : DualSenseThirdPartyModel(vendorID: vendorID, productID: productID)
    thirdParty = model
    features = model?.unprobedFeatures ?? .all
    if model?.usesAlternateReportUnprobed == true { useAlternateReport() }
  }

  /// A new transport session starts from neutral input and re-anchors motion time. The probe
  /// result describes the device, so it survives.
  public func resetProtocolState() {
    state = .neutral
    sensorClock.reset()
    resetDonglePresence()
  }
}
