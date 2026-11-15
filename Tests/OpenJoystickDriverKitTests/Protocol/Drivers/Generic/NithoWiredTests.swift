import Foundation
import Testing

@testable import OpenJoystickDriverKit

/// The NITHO MLT-KRMA-K by cable with the slider left, `2563:0526` `Android GamePad`.
///
/// A raw capture of report 7 put A on button 4, X on 5, Y on 1 and Home on 13, which the SDL line
/// for this ID maps to West, North, South and nothing. The record's `nitho` mode reads them by
/// label, and its default keeps SDL's layout for another pad on this ID.
struct NithoWiredTests {
  private static let model = ControllerModelID(vendorID: 0x2563, productID: 0x0526)

  /// The descriptor the pad publishes: report 7 with X, Y, Z and Rz, a hat, buttons 1 to 15,
  /// then Accelerator and Brake.
  private static let descriptor: [UInt8] = [
    0x05, 0x01, 0x09, 0x05, 0xA1, 0x01, 0x85, 0x07, 0x09, 0x01, 0xA1, 0x00,
    0x09, 0x30, 0x09, 0x31, 0x09, 0x32, 0x09, 0x35, 0x15, 0x00, 0x26, 0xFF, 0x00,
    0x75, 0x08, 0x95, 0x04, 0x81, 0x02, 0xC0,
    0x09, 0x39, 0x15, 0x00, 0x25, 0x07, 0x35, 0x00, 0x46, 0x3B, 0x01, 0x65, 0x14,
    0x75, 0x04, 0x95, 0x01, 0x81, 0x42, 0x75, 0x04, 0x95, 0x01, 0x81, 0x01,
    0x05, 0x09, 0x19, 0x01, 0x29, 0x0F, 0x15, 0x00, 0x25, 0x01, 0x75, 0x01, 0x95, 0x10,
    0x81, 0x02,
    0x05, 0x02, 0x15, 0x00, 0x26, 0xFF, 0x00, 0x09, 0xC4, 0x09, 0xC5, 0x95, 0x02,
    0x75, 0x08, 0x81, 0x02, 0x75, 0x08, 0x95, 0x01, 0x81, 0x01, 0xC0,
  ]

  private func select(
    manufacturer: String,
    product: String
  ) async throws
    -> ControllerModeSelection
  {
    let profile = try #require(ProtocolDriverRegistry().record(for: Self.model))
    let device = PhysicalDevice(
      vendorID: Self.model.vendorID,
      productID: Self.model.productID,
      manufacturer: manufacturer,
      productName: product,
      interfaces: [PhysicalInterfaceSignature(interfaceNumber: 0, hostTransport: .usb)]
    )
    return await ControllerModeSelector.select(
      from: profile,
      model: Self.model,
      backend: .hid,
      reader: UnreadableModeProbeReader(),
      device: device
    ) { _ in }
  }

  private func parse(
    modeID: String? = "nitho",
    page: UInt32,
    usage: UInt32,
    _ integer: Int,
    range: ClosedRange<Int> = 0...1
  )
    throws -> ControllerEvent?
  {
    HIDDescriptorDriver(
      model: Self.model,
      reportDescriptor: Data(Self.descriptor),
      usageMap: try #require(
        ProtocolDriverRegistry().record(for: Self.model)?.applying(modeID: modeID)?.hidUsageMap
      )
    ).parse(
      elementValue: HIDElementValue(
        usagePage: page,
        usage: usage,
        logicalMinimum: range.lowerBound,
        logicalMaximum: range.upperBound,
        integerValue: integer,
        reportID: 7
      ),
      receivedAt: MonotonicTimestamp(nanoseconds: 0)
    )
  }

  @Test
  func onlyNithoStringsSelectNithoMode() async throws {
    #expect(
      try await select(manufacturer: "shanwan", product: "Android GamePad") == .matched("nitho")
    )
    #expect(
      try await select(manufacturer: "Uberwith", product: "Controller") != .matched("nitho")
    )
  }

  @Test(arguments: [(UInt32(1), Control.south), (4, .west), (5, .north)])
  func defaultModeKeepsSdlLayout(usage: UInt32, control: Control) throws {
    #expect(try parse(modeID: nil, page: 9, usage: usage, 1).contains(.press(control)))
  }

  @Test(arguments: [
    (UInt32(4), Control.south), (2, .east), (5, .west), (1, .north), (7, .leftShoulder),
    (8, .rightShoulder), (11, .back), (12, .start), (13, .guide), (14, .leftStickClick),
    (15, .rightStickClick),
  ])
  func buttonReadsAsItsLabel(usage: UInt32, control: Control) throws {
    #expect(try parse(page: 9, usage: usage, 1).contains(.press(control)))
  }

  @Test
  func brakeIsLeftTriggerAndAcceleratorIsRight() throws {
    #expect(try parse(page: 2, usage: 0xC5, 255, range: 0...255)?.state.leftTrigger == .max)
    #expect(try parse(page: 2, usage: 0xC4, 255, range: 0...255)?.state.rightTrigger == .max)
  }

  @Test
  func stickUpReadsAsUp() throws {
    let up = try parse(page: 1, usage: 0x31, 0, range: 0...255)
    #expect(up?.state.leftStick.y == .min)
  }
}
