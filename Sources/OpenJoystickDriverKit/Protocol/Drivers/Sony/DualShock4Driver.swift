import Foundation

let ds4AxisCenter: Float = 128
let ds4TriggerMax: Float = 255
let ds4USBInputReportID: UInt8 = 0x01
let ds4BluetoothInputReportID: UInt8 = 0x11
let ds4BluetoothHIDInputTransaction: UInt8 = 0xA1
let ds4BluetoothHIDOutputHeader: UInt8 = 0xA2
let ds4USBOutputReportID: UInt8 = 0x05
let ds4USBOutputReportLength = 32
let ds4BluetoothOutputReportID: UInt8 = 0x11
let ds4BluetoothOutputReportLength = 78
let ds4OutputValidFlagMotor: UInt8 = 0x01
let ds4OutputValidFlagColor: UInt8 = 0x02
let ds4BluetoothOutputHIDAndCRCFlag: UInt8 = 0xC0
let ds4BluetoothOutputPollInterval: UInt8 = 0x04

public enum DS4Transport: String, Codable, Equatable, Sendable {
  case usb
  case bluetooth
}

public enum DualShock4DriverError: Error, Equatable, Sendable {
  case invalidReportFraming
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

  var sensorClock = SonySensorClock(mask: 0xFFFF, tickNumerator: 16_000)
  var motionCalibration = SonyMotionCalibration.nominal
  var state = ControllerState.neutral
  var previousSensorTimestamp: UInt16?
  public internal(set) var transport: DS4Transport = .usb
  public internal(set) var power: ControllerConnectionState.Power?
  public let sessionPlan: DriverSessionPlan
  public internal(set) var latestInputReportFormat: String?
  /// Whether a validated factory calibration report is installed. SDL ignores the report on
  /// controllers without Sony's vendor ID, so third-party pads keep the nominal scale.
  let usesFactoryCalibration: Bool
  /// The bound variant; startup follows Bluetooth whenever this or the observed reports say so.
  let isBluetoothVariant: Bool
  let model: DualShock4Model
  var adapterPadConnected = false
  var lastAdapterPadReportAt: UInt64?
  var pendingConnectionState: ControllerInputConnectionState?

  /// Creates a new DualShock4Driver.
  public init(
    prefersBluetooth: Bool = false,
    usesFactoryCalibration: Bool = true,
    model: DualShock4Model = .standard
  ) {
    transport = prefersBluetooth ? .bluetooth : .usb
    isBluetoothVariant = prefersBluetooth
    self.usesFactoryCalibration = usesFactoryCalibration
    self.model = model
    motionCalibration = model.scaled(.nominal)
    // Startup output is required only for the bound Bluetooth variant; Bluetooth-shaped reports
    // on a USB binding change the startup writes, not this requirement.
    sessionPlan = DriverSessionPlan(
      inputReportLivenessTimeoutNanoseconds: 1_000_000_000,
      requiresInputConnectionBeforeOutput: model == .wirelessAdapter,
      outputPrecedesFeatureReads: true,
      requiresStartupOutput: prefersBluetooth,
      validatesFeatureReplies: true
    )
  }

  /// A new transport session starts from neutral input and re-anchors motion time.
  public func resetProtocolState() {
    state = .neutral
    sensorClock.reset()
    resetAdapterPresence()
  }
}
