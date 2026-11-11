import Foundation

/// The raw stick value at the center.
let dualSenseAxisCenter: Float = 128
/// The largest distance above the center of a raw stick value.
let dualSenseAxisPositiveMax: Float = 127
/// The largest distance below the center of a raw stick value.
let dualSenseAxisNegativeMax: Float = 128
/// The maximum raw value of a trigger.
let dualSenseTriggerMax: Float = 255
/// The report ID of the USB input report.
let dualSenseUSBInputReportID: UInt8 = 0x01
/// The length of the USB input report in bytes.
let dualSenseUSBInputReportLength = 64
/// The report ID of the Bluetooth input report.
let dualSenseBluetoothInputReportID: UInt8 = 0x31
/// The length of the Bluetooth input report in bytes.
let dualSenseBluetoothInputReportLength = 78
/// The HID transaction byte that may precede a Bluetooth input report.
let dualSenseBluetoothHIDInputTransaction: UInt8 = 0xA1
/// The CRC seed of a Bluetooth input report.
let dualSenseInputCRC32Seed: UInt8 = 0xA1
/// The CRC seed of a Bluetooth output report.
let dualSenseOutputCRC32Seed: UInt8 = 0xA2
/// The report ID of the USB output report.
let dualSenseUSBOutputReportID: UInt8 = 0x02
/// The length of the USB output report in bytes.
let dualSenseUSBOutputReportLength = 63
/// The report ID of the Bluetooth output report.
let dualSenseBluetoothOutputReportID: UInt8 = 0x31
/// The length of the Bluetooth output report in bytes.
let dualSenseBluetoothOutputReportLength = 78
/// The tag byte that follows the sequence byte of a Bluetooth output report.
let dualSenseOutputTag: UInt8 = 0x10
/// The valid flag of the rumble motors in the first flag byte.
let dualSenseCompatibleVibrationFlags: UInt8 = 0x03
/// The valid flag of the player indicator in the second flag byte.
let dualSensePlayerIndicatorFlag: UInt8 = 0x10
/// The valid flag of the lightbar color in the second flag byte.
let dualSenseLightbarFlag: UInt8 = 0x04
/// The valid flag of the right trigger effect in the first flag byte.
let dualSenseRightTriggerEffectFlag: UInt8 = 0x04
/// The valid flag of the left trigger effect in the first flag byte.
let dualSenseLeftTriggerEffectFlag: UInt8 = 0x08

/// The transport of the latest input report; it selects the layout of output reports.
enum DualSenseConnectionMode {
  /// The USB report layout.
  case usb
  /// The Bluetooth report layout, with a header and a CRC trailer.
  case bluetooth
}

/// The failure of a DualSense report.
public enum DualSenseDriverError: Error, Equatable {
  /// The Bluetooth report failed its CRC32 check.
  case invalidBluetoothCRC
}

/// Driver for Sony DualSense controllers.
///
/// USB report ID `0x01` follows Linux `hid-playstation.c`'s
/// `struct dualsense_input_report`: four stick axes, two trigger axes,
/// sequence number, then button bytes, including the microphone mute button.
/// Bluetooth report `0x31` carries the same
/// common input report after its two-byte header and is accepted only when
/// its Linux-compatible CRC32 validates.
///
/// A controller whose record has the `maker: ThirdParty` parameter runs in SDL's third-party
/// mode; see `DualSenseThirdPartyModel`.
public final class DualSenseDriver: PhysicalProtocolDriver {

  /// Whether the controller is a DualSense Edge, which adds its extra controls.
  public let hasEdgeButtons: Bool
  /// The bound variant; a feature reply carries the Bluetooth CRC whenever this or the observed
  /// reports say Bluetooth.
  let isBluetoothVariant: Bool

  /// The motion calibration; nominal until a calibration report is installed.
  var motionCalibration = SonyMotionCalibration.nominal
  /// The clock that converts sensor timestamps to time.
  var sensorClock = SonySensorClock(mask: .max, tickNumerator: 1000)
  /// The state after the latest report.
  var state = ControllerState.neutral
  /// The transport of the latest input report.
  var connectionMode: DualSenseConnectionMode
  /// The rolling 4-bit sequence of the Bluetooth output reports.
  var outputSequence: UInt8 = 0

  /// Set for a non-Sony controller.
  let thirdParty: DualSenseThirdPartyModel?
  /// The features the controller has.
  var features: DualSenseFeatures
  /// Whether the controller sends the alternate 48-byte report of a third-party dongle.
  var usesAlternateReport = false
  /// The sequence of the latest alternate report.
  var lastPacketSequence: UInt32?
  /// How long repeated dongle reports may follow the last live one before the pad counts as
  /// disconnected (`adapterDisconnectDelayMs`).
  let dongleDisconnectNanoseconds: UInt64
  /// The time of the latest live dongle report.
  var lastLiveReportAt: UInt64?
  /// Whether the dongle has a connected pad.
  var dongleConnected = false
  /// The connection change that the next call to `consumeInputConnectionStateChange` returns.
  var pendingConnectionState: ControllerInputConnectionState?

  /// Creates the driver.
  ///
  /// A record with the `ThirdParty` maker selects third-party mode and takes its model from its
  /// other `parameters`.
  public init(
    prefersBluetooth: Bool = false,
    hasEdgeButtons: Bool = false,
    parameters: ProtocolParameters = .none,
    tuning: ControllerTuning? = nil
  ) {
    dongleDisconnectNanoseconds =
      UInt64(
        PhysicalProtocolID.sonyDualSense.described(\.adapterDisconnectDelayMilliseconds, in: tuning)
      ) * DeviceTransportProfile.nanosecondsPerMillisecond
    self.hasEdgeButtons = hasEdgeButtons
    isBluetoothVariant = prefersBluetooth
    connectionMode = prefersBluetooth ? .bluetooth : .usb
    let model =
      parameters.maker == .thirdParty ? DualSenseThirdPartyModel(parameters: parameters) : nil
    thirdParty = model
    features = model?.unprobedFeatures ?? .all
    if model?.usesAlternateReportUnprobed == true { useAlternateReport() }
  }

  /// Clears the state of the session: neutral input, motion time re-anchored and dongle presence
  /// forgotten.
  ///
  /// The probe result describes the device, so it survives.
  public func resetProtocolState() {
    state = .neutral
    sensorClock.reset()
    resetDonglePresence()
  }
}
