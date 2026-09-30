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
      leftMain: magnitude(left),
      rightMain: magnitude(right),
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

struct ConsumerOutputCodecTests {
  @Test
  func allZeroConsumerReportsStopRumble() throws {
    // Every motor activated at zero, with a nonzero duration.
    #expect(
      try consumerOutput(3, [0x03, 0x0F, 0, 0, 0, 0, 5, 0, 0], in: XboxGeckoHIDReportFormat())
        == .stopRumble
    )
    // Nonzero intensities whose activation bits are clear.
    #expect(
      try consumerOutput(3, [0x03, 0x00, 10, 20, 30, 40, 5, 0, 0], in: XboxGeckoHIDReportFormat())
        == .stopRumble
    )
  }

  @Test
  func rumbleDurationComesFromTheReport() throws {
    // Magnitudes span 0...100; 255 clamps to full strength.
    let intensities = RumbleIntensities(
      leftMain: UnipolarValue(unitInterval: 0.01),
      rightMain: .max,
      leftTrigger: .min,
      rightTrigger: .min
    )
    #expect(intensities.leftMain.rawValue == 655)
    // A duration byte of 0 is an immediate rumble, not a stop.
    #expect(
      try consumerOutput(3, [0x03, 0x0C, 0, 0, 1, 255, 0, 0, 0], in: XboxGeckoHIDReportFormat())
        == .setRumble(intensities, duration: .milliseconds(0))
    )
    // The duration byte counts 10 ms units.
    #expect(
      try consumerOutput(3, [0x03, 0x0C, 0, 0, 1, 255, 50, 0, 0], in: XboxGeckoHIDReportFormat())
        == .setRumble(intensities, duration: .milliseconds(500))
    )
  }

  /// SDL's HIDAPI Xbox One driver scales Bluetooth rumble to `0...100` (`SDL_hidapi_xboxone.c`
  /// `HIDAPI_DriverXboxOne_RumbleJoystick`, `/ 655`) and sends
  /// `03 0F lt rt low high FF 00 EB`; the descriptor declares Magnitude `0...100` too.
  @Test
  func sdlRumbleMagnitudesSpanZeroToOneHundred() throws {
    // SDL_RumbleJoystick(0xFFFF, 0x8000): low = 100, high = 50.
    let intensities = RumbleIntensities(
      leftMain: .max,
      rightMain: UnipolarValue(unitInterval: 0.5),
      leftTrigger: .min,
      rightTrigger: .min
    )
    #expect(
      try consumerOutput(
        3,
        [0x03, 0x0F, 0, 0, 100, 50, 0xFF, 0x00, 0xEB],
        in: XboxGeckoHIDReportFormat()
      ) == .setRumble(intensities, duration: .milliseconds(2_550))
    )
  }

  @Test
  func shortReportsAreRejectedByTheCodec() throws {
    let xboxOne = try XboxGeckoHIDReportFormat()
    #expect(throws: VirtualHostReportError.malformed) {
      try consumerOutput(3, [0x03, 0x0F, 10, 20, 30, 40], in: xboxOne)
    }
  }

  @Test
  func oversizedAndUndeclaredReportsAreRejectedByTheCodec() throws {
    #expect(throws: VirtualHostReportError.tooLarge) {
      try consumerOutput(3, [0x03, 0x0F, 0, 0, 10, 20, 5, 0, 0, 0], in: XboxGeckoHIDReportFormat())
    }
    #expect(throws: VirtualHostReportError.unsupported) {
      try consumerOutput(9, [0x09, 0x0F, 0, 0, 10, 20, 5, 0, 0], in: XboxGeckoHIDReportFormat())
    }
  }

  @Test
  func theInputOnlyGenericFormatRejectsEveryOutputReport() {
    // The former OJD vendor report, the short Xbox 360 forms, and a numbered Xbox One report.
    let reports: [(UInt32, [UInt8])] = [
      (0, [0x4F, 1, 2, 3, 4, 0xF4, 0x01]), (0, [0x4F, 1, 2, 3, 4]), (0, [0x08, 0x00, 10, 20]),
      (0, [0x08, 0x00, 10, 20, 0, 0, 0]), (3, [0x03, 0x0F, 0, 0, 10, 20, 5, 0, 0]),
    ]
    for (reportID, bytes) in reports {
      #expect(throws: VirtualHostReportError.unsupported) {
        try consumerOutput(reportID, bytes, in: OJDGenericGamepadFormat())
      }
    }
  }
}
