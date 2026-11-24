import Foundation
import Testing

@testable import OpenJoystickDriverKit

extension ControllerOutputCommand {
  /// The bounded set-rumble a consumer report requests, from its channel magnitudes in `0...100`.
  static func consumerRumble(
    left: UInt8,
    right: UInt8,
    leftTrigger: UInt8 = 0,
    rightTrigger: UInt8 = 0,
    durationMs: Int = 250
  ) -> Self {
    func magnitude(_ value: UInt8) -> UnipolarValue {
      UnipolarValue(unitInterval: Double(value) / 100)
    }
    let intensities = RumbleIntensities(
      lowFrequency: magnitude(left),
      highFrequency: magnitude(right),
      leftTrigger: magnitude(leftTrigger),
      rightTrigger: magnitude(rightTrigger)
    )
    return .setRumble(intensities, duration: .milliseconds(durationMs))
  }
}

/// Decodes one output report through the consumer output codec.
func consumerOutput(
  _ reportID: UInt32,
  _ bytes: [UInt8],
  in format: some VirtualGamepadReportFormat
) throws -> ControllerOutputCommand {
  let request = try VirtualHostReportRequest(type: .output, reportID: reportID, bytes: bytes)
  return try ConsumerOutputCodec.decode(request, in: format)
}

/// One GIP rumble output report as SDL writes it (`SDL_hidapi_xboxone.c`
/// `HIDAPI_DriverXboxOne_UpdateRumble`): command 0x09, options, sequence, length 9, sub-command,
/// then the activation mask, trigger and motor magnitudes, duration, delay and repeat.
func gipRumbleReport(
  activation: UInt8,
  leftTrigger: UInt8 = 0,
  rightTrigger: UInt8 = 0,
  left: UInt8 = 0,
  right: UInt8 = 0,
  duration: UInt8 = 0xFF
) -> [UInt8] {
  [
    0x09, 0x00, 0x00, 0x09, 0x00, activation, leftTrigger, rightTrigger, left, right, duration,
    0x00, 0xEB,
  ]
}

struct ConsumerOutputCodecTests {
  @Test
  func allZeroConsumerReportsStopRumble() throws {
    let format = XboxOneGIPHIDReportFormat()
    // Every motor activated at zero, with a nonzero duration.
    #expect(
      try consumerOutput(9, gipRumbleReport(activation: 0x0F, duration: 5), in: format)
        == .stopRumble
    )
    // Nonzero intensities whose activation bits are clear.
    #expect(
      try consumerOutput(
        9,
        gipRumbleReport(
          activation: 0,
          leftTrigger: 10,
          rightTrigger: 20,
          left: 30,
          right: 40,
          duration: 5
        ),
        in: format
      ) == .stopRumble
    )
  }

  @Test
  func rumbleDurationComesFromReport() throws {
    let format = XboxOneGIPHIDReportFormat()
    // Magnitudes span 0...100; 255 clamps to full strength.
    let intensities = RumbleIntensities(
      lowFrequency: UnipolarValue(unitInterval: 0.01),
      highFrequency: .max,
      leftTrigger: .min,
      rightTrigger: .min
    )
    #expect(intensities.lowFrequency.rawValue == 655)
    // A duration byte of 0 is an immediate rumble, not a stop.
    #expect(
      try consumerOutput(
        9,
        gipRumbleReport(activation: 0x03, left: 1, right: 255, duration: 0),
        in: format
      ) == .setRumble(intensities, duration: .milliseconds(0))
    )
    // The duration byte counts 10 ms units.
    #expect(
      try consumerOutput(
        9,
        gipRumbleReport(activation: 0x03, left: 1, right: 255, duration: 50),
        in: format
      ) == .setRumble(intensities, duration: .milliseconds(500))
    )
  }

  /// The motor bits of [MS-GIPUSB] Table 56, also the Xbox Series Bluetooth enable bits
  /// (xpadneo `enum xpadneo_rumble_motors`): bit 0 right vibration, bit 1 left vibration,
  /// bit 2 right impulse trigger, bit 3 left impulse trigger.
  @Test
  func eachActivationBitEnablesOnlyItsMotor() throws {
    func only(_ motor: WritableKeyPath<RumbleIntensities, UnipolarValue>) -> RumbleIntensities {
      var intensities = RumbleIntensities.off
      intensities[keyPath: motor] = .max
      return intensities
    }
    let bits: [(UInt8, WritableKeyPath<RumbleIntensities, UnipolarValue>)] = [
      (0x01, \.highFrequency), (0x02, \.lowFrequency), (0x04, \.rightTrigger),
      (0x08, \.leftTrigger),
    ]
    for (bit, motor) in bits {
      let gip = gipRumbleReport(
        activation: bit,
        leftTrigger: 100,
        rightTrigger: 100,
        left: 100,
        right: 100,
        duration: 1
      )
      #expect(
        try consumerOutput(9, gip, in: XboxOneGIPHIDReportFormat())
          == .setRumble(only(motor), duration: .milliseconds(10))
      )
      #expect(
        try consumerOutput(
          3,
          [0x03, bit, 100, 100, 100, 100, 1, 0, 0],
          in: XboxSeriesBluetoothHIDReportFormat()
        ) == .setRumble(only(motor), duration: .milliseconds(10))
      )
    }
  }

  /// SDL's HIDAPI Xbox One driver scales rumble to `0...100` (`SDL_hidapi_xboxone.c`
  /// `HIDAPI_DriverXboxOne_RumbleJoystick`, `/ 655`) and, for a device it does not read as
  /// Bluetooth, sends `09 00 seq 09 00 0F lt rt low high FF 00 EB`
  /// (`HIDAPI_DriverXboxOne_UpdateRumble`).
  @Test
  func sdlRumbleMagnitudesSpanZeroToOneHundred() throws {
    // SDL_RumbleJoystick(0xFFFF, 0x8000): low = 100, high = 50.
    let intensities = RumbleIntensities(
      lowFrequency: .max,
      highFrequency: UnipolarValue(unitInterval: 0.5),
      leftTrigger: .min,
      rightTrigger: .min
    )
    #expect(
      try consumerOutput(
        9,
        [0x09, 0x00, 0x00, 0x09, 0x00, 0x0F, 0x00, 0x00, 100, 50, 0xFF, 0x00, 0xEB],
        in: XboxOneGIPHIDReportFormat()
      ) == .setRumble(intensities, duration: .milliseconds(2_550))
    )
  }

  @Test
  func shortAndMisframedReportsAreRejectedByCodec() throws {
    let xboxOne = XboxOneGIPHIDReportFormat()
    #expect(throws: VirtualHostReportError.malformed) {
      try consumerOutput(9, [0x09, 0x00, 0x00, 0x09, 0x00, 0x0F, 10, 20], in: xboxOne)
    }
    // The GIP length field and sub-command must be those of a rumble packet.
    var wrongLength = gipRumbleReport(activation: 0x0F)
    wrongLength[3] = 0x08
    #expect(throws: VirtualHostReportError.malformed) {
      try consumerOutput(9, wrongLength, in: xboxOne)
    }
    var wrongSubCommand = gipRumbleReport(activation: 0x0F)
    wrongSubCommand[4] = 0x01
    #expect(throws: VirtualHostReportError.malformed) {
      try consumerOutput(9, wrongSubCommand, in: xboxOne)
    }
  }

  @Test
  func oversizedAndUndeclaredReportsAreRejectedByCodec() throws {
    let xboxOne = XboxOneGIPHIDReportFormat()
    #expect(throws: VirtualHostReportError.tooLarge) {
      try consumerOutput(9, gipRumbleReport(activation: 0x0F) + [0], in: xboxOne)
    }
    // The DualShock 4 output report is not one the format declares.
    #expect(throws: VirtualHostReportError.unsupported) {
      try consumerOutput(5, [0x05, 0x01, 0, 0, 10, 20, 0, 0, 0], in: xboxOne)
    }
  }

  /// The Xbox Series Bluetooth rumble report: ID 3, the enable mask, trigger and motor magnitudes
  /// `0...100`, duration in 10 ms units, start delay and loop count.
  @Test
  func xboxSeriesBluetoothFormatDecodesReportThreeAndOnlyIt() throws {
    let series = XboxSeriesBluetoothHIDReportFormat()
    let intensities = RumbleIntensities(
      lowFrequency: .max,
      highFrequency: UnipolarValue(unitInterval: 0.5),
      leftTrigger: UnipolarValue(unitInterval: 0.1),
      rightTrigger: .min
    )
    #expect(
      try consumerOutput(3, [0x03, 0x0F, 10, 0, 100, 50, 20, 0, 0], in: series)
        == .setRumble(intensities, duration: .milliseconds(200))
    )
    #expect(try consumerOutput(3, [0x03, 0x0F, 0, 0, 0, 0, 20, 0, 0], in: series) == .stopRumble)
    #expect(throws: VirtualHostReportError.malformed) {
      try consumerOutput(3, [0x03, 0x0F, 0, 0, 100, 50], in: series)
    }
    #expect(throws: VirtualHostReportError.unsupported) {
      try consumerOutput(9, gipRumbleReport(activation: 0x0F, left: 10), in: series)
    }
  }

  /// The DualShock 4 USB output report: ID 5, the valid flags, two unused bytes, the right (weak)
  /// and left (strong) motor `0...255`, then the lightbar color.
  @Test
  func dualShock4FormatDecodesMotorsHeldUntilTheNextReport() throws {
    let ds4 = DualShock4USBHIDReportFormat()
    let intensities = RumbleIntensities(
      lowFrequency: .max,
      highFrequency: UnipolarValue(unitInterval: 128.0 / 255.0),
      leftTrigger: .min,
      rightTrigger: .min
    )
    #expect(
      try consumerOutput(5, Self.ds4Report(flags: 0x07, right: 0x80, left: 0xFF), in: ds4)
        == .setRumble(intensities, duration: .held)
    )
    #expect(try consumerOutput(5, Self.ds4Report(flags: 0x01), in: ds4) == .stopRumble)
  }

  @Test
  func dualShock4FormatDecodesLightbarWithoutMotorFlag() throws {
    #expect(
      try consumerOutput(
        5,
        Self.ds4Report(flags: 0x02, color: (0x10, 0x20, 0x30)),
        in: DualShock4USBHIDReportFormat()
      ) == .setRGB(ControllerColor(red: 0x10, green: 0x20, blue: 0x30))
    )
  }

  @Test
  func dualShock4FormatRejectsShortFlaglessAndForeignReports() {
    let ds4 = DualShock4USBHIDReportFormat()
    #expect(throws: VirtualHostReportError.malformed) {
      try consumerOutput(5, [0x05, 0x01, 0x04, 0x00, 0x10], in: ds4)
    }
    #expect(throws: VirtualHostReportError.malformed) {
      try consumerOutput(5, Self.ds4Report(flags: 0x04), in: ds4)
    }
    #expect(throws: VirtualHostReportError.unsupported) {
      try consumerOutput(3, [0x03, 0x0F, 0, 0, 100, 50, 20, 0, 0], in: ds4)
    }
  }

  /// A 32-byte DualShock 4 USB output report.
  private static func ds4Report(
    flags: UInt8,
    right: UInt8 = 0,
    left: UInt8 = 0,
    color: (UInt8, UInt8, UInt8) = (0, 0, 0)
  ) -> [UInt8] {
    var report = [UInt8](repeating: 0, count: 32)
    report[0...8] = [0x05, flags, 0x04, 0x00, right, left, color.0, color.1, color.2]
    return report
  }

  @Test
  func inputOnlyGenericFormatRejectsEveryOutputReport() {
    // An unnumbered vendor report (marker `0x4F`), the short Xbox 360 forms, and a numbered Xbox
    // One report.
    let reports: [(UInt32, [UInt8])] = [
      (0, [0x4F, 1, 2, 3, 4, 0xF4, 0x01]), (0, [0x4F, 1, 2, 3, 4]), (0, [0x08, 0x00, 10, 20]),
      (0, [0x08, 0x00, 10, 20, 0, 0, 0]),
      (9, gipRumbleReport(activation: 0x0F, left: 10, right: 20)),
    ]
    for (reportID, bytes) in reports {
      #expect(throws: VirtualHostReportError.unsupported) {
        try consumerOutput(reportID, bytes, in: OJDGenericGamepadFormat())
      }
    }
  }
}
