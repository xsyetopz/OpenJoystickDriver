import Testing

@testable import OpenJoystickDriverKit

struct HIDReportPackerTests {
  private let descriptor: [UInt8] = [
    0x05, 0x01,  // Generic Desktop
    0x09, 0x05,  // Game Pad
    0xA1, 0x01,  // Application
    0x05, 0x09,  // Button
    0x09, 0x01,  // Button 1
    0x15, 0x00, 0x25, 0x01, 0x75, 0x01, 0x95, 0x01, 0x81, 0x02, 0x75, 0x07, 0x95, 0x01, 0x81, 0x03,
    0x06, 0x00, 0xFF,  // Vendor page 0xFF00
    0x09, 0x01,  // Vendor usage 1
    0x15, 0x00, 0x25, 0x01, 0x75, 0x01, 0x95, 0x01, 0x81, 0x02, 0x75, 0x07, 0x95, 0x01, 0x81, 0x03,
    0xC0
  ]

  @Test func explicitDigitalUsageMapsARecognizedExtraButton() throws {
    let format = try HIDDescriptorReportFormat(
      descriptor: descriptor,
      digitalUsageMap: [16: HIDInputUsage(page: 0xFF00, usage: 0x01)]
    )

    let standard = format.buildInputReport(from: VirtualGamepadState(buttons: 1 << 0))
    let extra = format.buildInputReport(from: VirtualGamepadState(buttons: 1 << 16))

    #expect(standard == [0x01, 0x00])
    #expect(extra == [0x00, 0x01])
  }

  @Test func usagePageKeepsSameNumberedInputsDistinct() throws {
    let format = try HIDDescriptorReportFormat(
      descriptor: descriptor,
      digitalUsageMap: [0: HIDInputUsage(page: 0xFF00, usage: 0x01)]
    )

    #expect(format.buildInputReport(from: VirtualGamepadState(buttons: 1)) == [0x00, 0x01])
  }

  @Test func missingExplicitUsageFailsFormatConstruction() {
    #expect(
      throws: HIDDescriptorReportFormat.Error.missingExplicitInputUsage(
        HIDInputUsage(page: 0x0C, usage: 0xB2)
      )
    ) {
      try HIDDescriptorReportFormat(
        descriptor: descriptor,
        digitalUsageMap: [15: HIDInputUsage(page: 0x0C, usage: 0xB2)]
      )
    }
  }

  @Test func duplicateExplicitUsageFailsFormatConstruction() {
    let usage = HIDInputUsage(page: 0xFF00, usage: 0x01)
    #expect(throws: HIDDescriptorReportFormat.Error.duplicateExplicitInputUsage(usage)) {
      try HIDDescriptorReportFormat(descriptor: descriptor, digitalUsageMap: [16: usage, 17: usage])
    }
  }

  @Test func explicitUsageCannotReplaceAnotherNormalizedButton() {
    let usage = HIDInputUsage(page: 0x09, usage: 0x01)
    #expect(throws: HIDDescriptorReportFormat.Error.duplicateExplicitInputUsage(usage)) {
      try HIDDescriptorReportFormat(descriptor: descriptor, digitalUsageMap: [16: usage])
    }
  }

  @Test func explicitUsageInMoreThanOneReportFailsFormatConstruction() {
    let usage = HIDInputUsage(page: 0xFF00, usage: 0x01)
    let descriptorWithRepeatedUsage =
      descriptor.dropLast() + [
        0x85, 0x02,  // Report ID 2
        0x06, 0x00, 0xFF,  // Vendor page 0xFF00
        0x09, 0x01,  // Vendor usage 1
        0x15, 0x00, 0x25, 0x01, 0x75, 0x01, 0x95, 0x01, 0x81, 0x02, 0xC0
      ]

    #expect(throws: HIDDescriptorReportFormat.Error.ambiguousExplicitInputUsage(usage)) {
      try HIDDescriptorReportFormat(
        descriptor: Array(descriptorWithRepeatedUsage),
        digitalUsageMap: [16: usage]
      )
    }
  }
}
