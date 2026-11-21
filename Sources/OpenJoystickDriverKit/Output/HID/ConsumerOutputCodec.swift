import Foundation

/// Decodes the output reports a consumer sends to a virtual format into the output command it
/// requests.
///
/// The Xbox One GIP rumble report (report ID 9), the Xbox Series Bluetooth rumble report (report
/// ID 3) and the DualShock 4 USB rumble and lightbar report (report ID 5) are the only output
/// reports any format declares; the generic format is input-only.
enum ConsumerOutputCodec {
  /// The report ID of the Xbox One GIP rumble report.
  static let xboxOneReportID = XboxOneGIPHIDDescriptor.rumbleReportID
  /// The size of the Xbox One GIP rumble report after its ID.
  static let xboxOneReportPayloadSize = XboxOneGIPHIDDescriptor.rumbleReportPayloadSize
  /// The report ID of the Xbox Series Bluetooth rumble report.
  static let xboxSeriesReportID = XboxSeriesBluetoothHIDDescriptor.rumbleReportID
  /// The size of the Xbox Series Bluetooth rumble report after its ID.
  static let xboxSeriesReportPayloadSize = XboxSeriesBluetoothHIDDescriptor.rumbleReportPayloadSize
  /// The report ID of the DualShock 4 USB rumble and lightbar report.
  static let dualShock4ReportID = DualShock4USBHIDDescriptor.outputReportID

  /// The valid flag of the DualShock 4 motor bytes.
  private static let dualShock4MotorFlag: UInt8 = 0x01
  /// The valid flag of the DualShock 4 lightbar color bytes.
  private static let dualShock4ColorFlag: UInt8 = 0x02
  /// The DualShock 4 report bytes up to the end of the lightbar color.
  private static let dualShock4MinimumPayloadSize = 8
  /// The largest DualShock 4 motor byte.
  private static let dualShock4MotorMax = 255.0

  /// The GIP rumble packet's length field and sub-command, which follow its options and sequence.
  private static let gipRumbleLength: UInt8 = 9
  /// The sub-command of the GIP rumble packet.
  private static let gipRumbleSubCommand: UInt8 = 0
  /// The index in the GIP rumble report where the rumble body starts.
  private static let gipRumbleBodyOffset = 4

  /// Duration of a rumble report that carries none.
  static let defaultRumbleDurationMs = 250

  /// Motor bits of the GIP Direct Motor Command ([MS-GIPUSB] Table 56), which the Xbox Series
  /// Bluetooth report shares (xpadneo `enum xpadneo_rumble_motors`).
  private static let rumbleActivationAllMotors: UInt8 = 0x0F
  /// The activation bit of the right motor.
  private static let rumbleActivationRight: UInt8 = 0x01
  /// The activation bit of the left motor.
  private static let rumbleActivationLeft: UInt8 = 0x02
  /// The activation bit of the right trigger motor.
  private static let rumbleActivationRightTrigger: UInt8 = 0x04
  /// The activation bit of the left trigger motor.
  private static let rumbleActivationLeftTrigger: UInt8 = 0x08
  /// The milliseconds that one unit of the duration byte stands for.
  private static let rumbleDurationByteMultiplier = 10

  /// The command that an output report requests, read in the output report format of `format`.
  ///
  /// A report `format` does not declare is unsupported; one whose length or header does not match
  /// its report ID is malformed.
  static func decode(
    _ request: VirtualHostReportRequest,
    in format: some VirtualGamepadReportFormat
  ) throws(VirtualHostReportError) -> ControllerOutputCommand {
    guard let maximum = format.outputReportPayloadSize,
      request.reportID == format.outputReportID ?? 0
    else { throw .unsupported }
    let payload = request.payload
    guard payload.count <= maximum else { throw .tooLarge }
    switch request.reportID {
    case xboxOneReportID:
      guard payload.count == xboxOneReportPayloadSize,
        payload[2] == gipRumbleLength, payload[3] == gipRumbleSubCommand
      else { throw .malformed }
      return activatedRumble(Array(payload[gipRumbleBodyOffset...]))
    case xboxSeriesReportID:
      guard payload.count == xboxSeriesReportPayloadSize else { throw .malformed }
      return activatedRumble(payload)
    case dualShock4ReportID:
      return try dualShock4Output(payload)
    default: throw .unsupported
    }
  }

  /// The largest rumble magnitude: SDL scales a 16-bit strength to `0...100`
  /// (`SDL_hidapi_xboxone.c` `HIDAPI_DriverXboxOne_RumbleJoystick`, division by 655), and the
  /// Xbox Series Bluetooth descriptor's Magnitude logical maximum is `0x64`.
  private static let rumbleMagnitudeMax = 100.0

  /// A rumble command from report magnitudes in `0...magnitudeMax` (larger values clamp to full
  /// strength); all four channels at zero stop rumble.
  static func rumble(
    left: UInt8,
    right: UInt8,
    leftTrigger: UInt8 = 0,
    rightTrigger: UInt8 = 0,
    duration: RumbleDuration = .milliseconds(defaultRumbleDurationMs),
    magnitudeMax: Double = rumbleMagnitudeMax
  ) -> ControllerOutputCommand {
    func magnitude(_ value: UInt8) -> UnipolarValue {
      UnipolarValue(unitInterval: Double(value) / magnitudeMax)
    }
    let intensities = RumbleIntensities(
      lowFrequency: magnitude(left),
      highFrequency: magnitude(right),
      leftTrigger: magnitude(leftTrigger),
      rightTrigger: magnitude(rightTrigger)
    )
    guard intensities != .off else { return .stopRumble }
    return .setRumble(intensities, duration: duration)
  }

  /// The rumble body of both Xbox layouts (the GIP one after its sub-command): an activation mask,
  /// then left trigger, right trigger, left, right and a duration in 10 ms units.
  private static func activatedRumble(_ bytes: [UInt8]) -> ControllerOutputCommand {
    let activation = bytes[0] & rumbleActivationAllMotors
    func channel(_ mask: UInt8, _ offset: Int) -> UInt8 {
      activation & mask != 0 ? bytes[offset] : 0
    }
    return rumble(
      left: channel(rumbleActivationLeft, 3),
      right: channel(rumbleActivationRight, 4),
      leftTrigger: channel(rumbleActivationLeftTrigger, 1),
      rightTrigger: channel(rumbleActivationRightTrigger, 2),
      duration: .milliseconds(Int(bytes[5]) * rumbleDurationByteMultiplier)
    )
  }

  /// The DualShock 4 output report after its ID: valid flags, two reserved bytes, the right
  /// (weak) and left (strong) motor `0...255`, then the lightbar red, green and blue.
  ///
  /// A report whose motor flag is set requests rumble that holds until the next report, as the
  /// genuine controller does; otherwise a report whose color flag is set requests the color.
  private static func dualShock4Output(
    _ bytes: [UInt8]
  ) throws(VirtualHostReportError) -> ControllerOutputCommand {
    guard bytes.count >= dualShock4MinimumPayloadSize else { throw .malformed }
    if bytes[0] & dualShock4MotorFlag != 0 {
      return rumble(
        left: bytes[4],
        right: bytes[3],
        duration: .held,
        magnitudeMax: dualShock4MotorMax
      )
    }
    guard bytes[0] & dualShock4ColorFlag != 0 else { throw .malformed }
    return .setRGB(ControllerColor(red: bytes[5], green: bytes[6], blue: bytes[7]))
  }
}
