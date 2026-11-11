import Foundation

/// The raw stick value at the center, and the largest distance from it.
let ds4AxisCenter: Float = 128
/// The maximum raw value of a trigger.
let ds4TriggerMax: Float = 255
/// The report ID of the USB input report.
let ds4USBInputReportID: UInt8 = 0x01
/// The report ID of the complete Bluetooth input report.
let ds4BluetoothInputReportID: UInt8 = 0x11
/// The HID transaction byte that may precede a Bluetooth input report.
let ds4BluetoothHIDInputTransaction: UInt8 = 0xA1
/// The CRC seed of a Bluetooth output report.
let ds4BluetoothHIDOutputHeader: UInt8 = 0xA2
/// The report ID of the USB output report.
let ds4USBOutputReportID: UInt8 = 0x05
/// The length of the USB output report in bytes.
let ds4USBOutputReportLength = 32
/// The report ID of the Bluetooth output report.
let ds4BluetoothOutputReportID: UInt8 = 0x11
/// The length of the Bluetooth output report in bytes.
let ds4BluetoothOutputReportLength = 78
/// The valid flag of the rumble motors.
let ds4OutputValidFlagMotor: UInt8 = 0x01
/// The valid flag of the lightbar color.
let ds4OutputValidFlagColor: UInt8 = 0x02
/// The flags of a Bluetooth output report that enable HID data and the CRC.
let ds4BluetoothOutputHIDAndCRCFlag: UInt8 = 0xC0
/// The poll interval bits of a Bluetooth output report.
let ds4BluetoothOutputPollInterval: UInt8 = 0x04

/// The transport a DualShock 4 is connected over.
public enum DS4Transport: String, Codable, Equatable, Sendable {
  /// The USB transport.
  case usb
  /// The Bluetooth transport.
  case bluetooth
}

/// The failure of a DualShock 4 report.
public enum DualShock4DriverError: Error, Equatable, Sendable {
  /// The report has the wrong framing.
  case invalidReportFraming
  /// The Bluetooth report failed its CRC32 check.
  case invalidBluetoothCRC
}

/// Driver for Sony DualShock 4 controllers.
///
/// DS4 sends input reports automatically over USB, with no handshake.
/// IOKit reports the DS4 report ID separately, so wired HID input can arrive
/// with or without the leading `0x01` report ID byte.
/// Bluetooth input report `0x11` carries the same controller state after its
/// transport/control prefix.
public final class DualShock4Driver: PhysicalProtocolDriver {

  /// The clock that converts sensor timestamps to time.
  var sensorClock = SonySensorClock(mask: 0xFFFF, tickNumerator: 16_000)
  /// The motion calibration; nominal until a factory calibration report is installed.
  var motionCalibration = SonyMotionCalibration.nominal
  /// The state after the latest report.
  var state = ControllerState.neutral
  /// The sensor timestamp of the latest report.
  var previousSensorTimestamp: UInt16?
  /// The transport of the latest input report.
  public internal(set) var transport: DS4Transport = .usb
  /// The battery state of the latest report.
  public internal(set) var power: ControllerConnectionState.Power?
  /// The session plan of the driver.
  public let sessionPlan: DriverSessionPlan
  /// The name of the layout of the latest input report.
  public internal(set) var latestInputReportFormat: String?
  /// Whether a validated factory calibration report is installed.
  ///
  /// SDL ignores the report on controllers without Sony's vendor ID, so only records with the
  /// `motionCalibration: Factory` parameter install it and third-party pads keep the nominal scale.
  let usesFactoryCalibration: Bool
  /// The bound variant; startup follows Bluetooth whenever this or the observed reports say so.
  let isBluetoothVariant: Bool
  /// The model of the controller.
  let model: DualShock4Model
  /// How long flagged adapter reports may follow the last live one before the pad counts as
  /// disconnected (`adapterDisconnectDelayMs`).
  let adapterDisconnectNanoseconds: UInt64
  /// Whether the adapter has a paired pad that sends live reports.
  var adapterPadConnected = false
  /// The time of the latest live report of the adapter's pad.
  var lastAdapterPadReportAt: UInt64?
  /// The connection change that the next call to `consumeInputConnectionStateChange` returns.
  var pendingConnectionState: ControllerInputConnectionState?

  /// Creates the driver for a DualShock 4 of `model` on the transport it is bound to.
  public init(
    prefersBluetooth: Bool = false,
    usesFactoryCalibration: Bool = true,
    model: DualShock4Model = .standard,
    tuning: ControllerTuning? = nil
  ) {
    transport = prefersBluetooth ? .bluetooth : .usb
    isBluetoothVariant = prefersBluetooth
    self.usesFactoryCalibration = usesFactoryCalibration
    self.model = model
    adapterDisconnectNanoseconds =
      UInt64(
        PhysicalProtocolID.sonyDualShock4.described(
          \.adapterDisconnectDelayMilliseconds,
          in: tuning
        )
      ) * DeviceTransportProfile.nanosecondsPerMillisecond
    motionCalibration = model.scaled(.nominal)
    // Startup output is required only for the bound Bluetooth variant; Bluetooth-shaped reports
    // on a USB binding change the startup writes, not this requirement.
    sessionPlan = DriverSessionPlan(
      requiresInputConnectionBeforeOutput: model == .wirelessAdapter,
      outputPrecedesFeatureReads: true,
      requiresStartupOutput: prefersBluetooth,
      validatesFeatureReplies: true
    ).withDefaults(of: .sonyDualShock4)
  }

  /// Clears the state of the session: neutral input, motion time re-anchored and adapter presence
  /// forgotten.
  public func resetProtocolState() {
    state = .neutral
    sensorClock.reset()
    resetAdapterPresence()
  }
}
