import Testing

@testable import OpenJoystickDriverKit

struct DualShock4USBHIDReportFormatTests {
  private let format = DualShock4USBHIDReportFormat()

  /// Report 1 at rest: sticks at `0x80`, hat null, no button, full battery on wired power, and
  /// one touch packet with both fingers lifted.
  private static let neutral: [UInt8] = {
    var report = [UInt8](repeating: 0, count: 64)
    report[0] = 0x01
    report[1...4] = [0x80, 0x80, 0x80, 0x80]
    report[5] = 0x08
    report[30] = 0x1B
    report[33] = 0x01
    report[35] = 0x80
    report[39] = 0x80
    return report
  }()

  private func report(buttonBit: GamepadHIDDescriptor.ButtonBit) -> [UInt8] {
    format.buildInputReport(from: VirtualGamepadState(buttons: 1 << UInt32(buttonBit.rawValue)))
  }

  @Test
  func neutralReportIsSixtyFourBytes() {
    #expect(format.buildInputReport(from: VirtualGamepadState()) == Self.neutral)
    #expect(format.inputReportID == 0x01)
    #expect(format.outputReportID == 0x05)
    #expect(format.outputReportPayloadSize == 31)
  }

  @Test
  func everyDigitalControlSetsOnlyItsBit() {
    let controls: [(GamepadHIDDescriptor.ButtonBit, Int, UInt8)] = [
      (.x, 5, 0x18), (.a, 5, 0x28), (.b, 5, 0x48), (.y, 5, 0x88), (.leftBumper, 6, 0x01),
      (.rightBumper, 6, 0x02), (.back, 6, 0x10), (.start, 6, 0x20), (.leftStick, 6, 0x40),
      (.rightStick, 6, 0x80), (.guide, 7, 0x01),
    ]
    for (button, byte, value) in controls {
      let built = report(buttonBit: button)
      #expect(built[byte] == value, "\(button)")
      #expect(
        built.enumerated().allSatisfy {
          $0.offset == byte || $0.element == Self.neutral[$0.offset]
        },
        "\(button)"
      )
    }
  }

  @Test
  func hatCarriesDpadClockwiseFromNorth() {
    let hats: [(GamepadHIDDescriptor.Hat, UInt8)] = [
      (.north, 0), (.northEast, 1), (.east, 2), (.southEast, 3), (.south, 4), (.southWest, 5),
      (.west, 6), (.northWest, 7), (.neutral, 8),
    ]
    for (hat, nibble) in hats {
      #expect(format.buildInputReport(from: VirtualGamepadState(hat: hat))[5] == nibble, "\(hat)")
    }
  }

  @Test
  func sticksAndTriggersPackIntoBytes() {
    let built = format.buildInputReport(
      from: VirtualGamepadState(
        leftStickX: 32_767,
        leftStickY: -32_768,
        rightStickX: -16_384,
        rightStickY: 16_384,
        leftTrigger: 32_767,
        rightTrigger: 16_384
      )
    )
    #expect(Array(built[1...4]) == [0xFF, 0x00, 0x40, 0xC0])
    #expect(Array(built[8...9]) == [0xFF, 0x7F])
    #expect(built[6] == 0x0C)
  }

  @Test
  func pressedTriggerWithoutPressureReadsFull() {
    let built = format.buildInputReport(from: VirtualGamepadState(leftTriggerPressed: true))
    #expect(built[8] == 0xFF)
    #expect(built[6] == 0x04)
  }

  @Test
  func descriptorDeclaresReportOneAndTheFeatureReports() throws {
    let parsed = try #require(
      HIDReportDescriptorParser.parse(descriptor: DualShock4USBHIDDescriptor.descriptor)
    )
    #expect(parsed.payloadSizeBytesByReportID[1] == 63)
    #expect(parsed.inputReportIDs == [1])
    #expect(parsed.containsFeatureItem)
    let buttons = parsed.fields.filter { $0.reportID == 1 && $0.usagePage == 0x09 }
      .sorted { $0.bitOffset < $1.bitOffset }.map(\.usage)
    #expect(buttons == Array(1...14))
    let axes = parsed.fields.filter { $0.reportID == 1 && $0.usagePage == 0x01 }
      .sorted { $0.bitOffset < $1.bitOffset }.map(\.usage)
    #expect(axes == [0x30, 0x31, 0x32, 0x35, 0x39, 0x33, 0x34])
  }

  /// Each feature report is as long as the descriptor declares, plus its ID byte.
  @Test
  func featureReportsMatchTheirDeclaredSizes() {
    let sizes: [UInt8: Int] = [0x02: 37, 0x12: 16, 0x81: 7, 0xA3: 49]
    #expect(format.featureReports.mapValues(\.count) == sizes)
    for (identifier, report) in format.featureReports { #expect(report.first == identifier) }
  }

  @Test
  func calibrationReportParsesAsUSBFactoryCalibration() {
    let report = format.featureReports[0x02] ?? []
    #expect(
      SonyMotionCalibration.dualShock4Factory(report, bluetooth: false, groupsGyroEndpoints: false)
        != nil
    )
  }

  @Test
  func pairingAndMACReportsCarryTheSameAddress() {
    let mac = Array(format.featureReports[0x81]?.dropFirst() ?? [])
    #expect(mac == [0x01, 0x34, 0x44, 0x4A, 0x4F, 0x02])
    #expect(Array(format.featureReports[0x12]?[1...6] ?? []) == mac)
  }

  @Test
  func personaPublishesDualShock4USBIdentity() {
    let profile = VirtualHIDProfileID.inControlCompatible.makeProfile()
    #expect(profile.identity.vendorID == 0x054C)
    #expect(profile.identity.productID == 0x09CC)
    #expect(profile.identity.productName == "Wireless Controller")
    #expect(profile.identity.manufacturer == "Sony Interactive Entertainment")
    #expect(profile.identity.transport == "USB")
    #expect(profile.identity.glyphFamily == .playStation)
    #expect(profile.descriptor == DualShock4USBHIDDescriptor.descriptor)
    #expect(VirtualHIDProfileID.inControlCompatible.commandLineName == "in-control-compatible")
  }
}
