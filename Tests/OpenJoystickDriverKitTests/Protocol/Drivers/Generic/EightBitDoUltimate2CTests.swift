import Testing

@testable import OpenJoystickDriverKit

/// The 8BitDo Ultimate 2C records, from sources only: the HID usage tables and the Z/Rz layout of
/// `docs/testing/8bitdo-ultimate-2c.md`. No capture of `2DC8:301B` or `2DC8:3109` backs them; a
/// tester's capture replaces these usages.
struct EightBitDoUltimate2CTests {
  private static let bluetooth = ControllerModelID(vendorID: 0x2DC8, productID: 0x301B)
  private static let adapter = ControllerModelID(vendorID: 0x2DC8, productID: 0x3109)

  private func parse(_ parser: HIDDescriptorDriver, usage: UInt32, _ integer: Int)
    -> ControllerEvent?
  {
    parser.parse(
      elementValue: HIDElementValue(
        usagePage: 1,
        usage: usage,
        logicalMinimum: 0,
        logicalMaximum: 255,
        integerValue: integer,
        reportID: 5
      ),
      receivedAt: MonotonicTimestamp(nanoseconds: 0)
    )
  }

  @Test
  func rightStickSweepMovesBothAxesAndLeavesTriggersAtRest() throws {
    let parser = HIDDescriptorDriver(
      model: Self.bluetooth,
      usageMap: try catalogUsageMap(0x2DC8, 0x301B)
    )
    let right = parse(parser, usage: 0x32, 255)
    #expect(right.contains(.rightStick(x: 1, y: 0)))
    let down = parse(parser, usage: 0x35, 255)
    #expect(down.contains(.rightStick(x: 1, y: 1)))
    #expect(down?.state.leftTrigger == UnipolarValue(normalized: 0))
    #expect(down?.state.rightTrigger == UnipolarValue(normalized: 0))
  }

  @Test(arguments: [UInt32(0x33), 0x34])
  func rxAndRyMapToNothing(usage: UInt32) throws {
    let parser = HIDDescriptorDriver(
      model: Self.bluetooth,
      usageMap: try catalogUsageMap(0x2DC8, 0x301B)
    )
    #expect(parse(parser, usage: usage, 255) == nil)
  }

  @Test
  func adapterStaysXboxXUSBWired() throws {
    let record = try #require(ProtocolDriverRegistry().record(for: Self.adapter))
    #expect(record.physicalProtocolID == .xboxXUSB)
    #expect(record.hidUsageMap == nil)
  }
}
