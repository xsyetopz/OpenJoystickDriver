import Testing

@testable import OpenJoystickDriverKit

/// The 8BitDo Ultimate 2C records, from sources only.
///
/// The sources are the HID usage tables and the Z/Rz layout of
/// `docs/testing/8bitdo-ultimate-2c.md`. No capture of `2DC8:301B`, `2DC8:301D` or `2DC8:3109`
/// backs them; a tester's capture replaces these usages.
struct EightBitDoUltimate2CTests {
  private static let bluetooth = ControllerModelID(vendorID: 0x2DC8, productID: 0x301B)
  private static let adapter = ControllerModelID(vendorID: 0x2DC8, productID: 0x3109)
  private static let receiver = ControllerModelID(vendorID: 0x2DC8, productID: 0x301C)
  private static let wired = ControllerModelID(vendorID: 0x2DC8, productID: 0x301D)

  /// The button table of `docs/testing/8bitdo-ultimate-2c.md`, written out from that document.
  static let buttonTable: [(usage: UInt32, button: Control)] = [
    (1, .south), (2, .east), (4, .west), (5, .north), (7, .leftShoulder), (8, .rightShoulder),
    (11, .back), (12, .start), (13, .guide), (14, .leftStickClick), (15, .rightStickClick),
  ]

  static func parse(
    _ parser: HIDDescriptorDriver,
    page: UInt32 = 1,
    usage: UInt32,
    _ integer: Int
  ) -> ControllerEvent? {
    parser.parse(
      elementValue: HIDElementValue(
        usagePage: page,
        usage: usage,
        logicalMinimum: 0,
        logicalMaximum: page == 9 ? 1 : 255,
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
    let right = Self.parse(parser, usage: 0x32, 255)
    #expect(right.contains(.rightStick(x: 1, y: 0)))
    let down = Self.parse(parser, usage: 0x35, 255)
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
    #expect(Self.parse(parser, usage: usage, 255) == nil)
  }

  @Test
  func adapterStaysXboxXUSBWired() throws {
    let record = try #require(ProtocolDriverRegistry().record(for: Self.adapter))
    #expect(record.physicalProtocolID == .xboxXUSB)
    #expect(record.hidUsageMap == nil)
  }

  @Test
  func receiverMapsNoControls() throws {
    let record = try #require(ProtocolDriverRegistry().record(for: Self.receiver))
    #expect(record.isIdle)
    #expect(record.hidUsageMap == nil)
  }

  @Test
  func wiredDInputReplaysTheBluetoothUsages() throws {
    let parser = HIDDescriptorDriver(
      model: Self.wired,
      usageMap: try catalogUsageMap(0x2DC8, 0x301D)
    )
    for (usage, button) in Self.buttonTable {
      let press = Self.parse(parser, page: 9, usage: usage, 1)
      #expect(press.contains(.press(button)), "usage \(usage)")
    }
    #expect(Self.parse(parser, usage: 0x32, 255).contains(.rightStick(x: 1, y: 0)))
    #expect(Self.parse(parser, usage: 0x33, 255) == nil)
  }
}
