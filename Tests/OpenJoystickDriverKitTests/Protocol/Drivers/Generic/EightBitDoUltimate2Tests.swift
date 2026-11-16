import Testing

@testable import OpenJoystickDriverKit

/// The Ultimate 2 and Ultimate 3-mode records, from sources only.
///
/// No capture of an Ultimate 2 backs them, and no source
/// gives its rear-button usages, so the records map no paddle: paddles wait for a hardware capture.
struct EightBitDoUltimate2Tests {
  private typealias Base = EightBitDoUltimate2CTests
  private static let cable = ControllerModelID(vendorID: 0x2DC8, productID: 0x6012)

  private func parser() throws -> HIDDescriptorDriver {
    HIDDescriptorDriver(model: Self.cable, usageMap: try catalogUsageMap(0x2DC8, 0x6012))
  }

  @Test
  func replaysUltimate2CUsages() throws {
    let parser = try parser()
    for (usage, button) in Base.buttonTable {
      let press = Base.parse(parser, page: 9, usage: usage, 1)
      #expect(press.contains(.press(button)), "usage \(usage)")
    }
    #expect(Base.parse(parser, usage: 0x32, 255).contains(.rightStick(x: 1, y: 0)))
    #expect(Base.parse(parser, usage: 0x33, 255) == nil)
  }

  @Test(arguments: [UInt32(3), 6, 9, 10, 16, 17, 18, 19])
  func mapsNoRearButton(usage: UInt32) throws {
    #expect(Base.parse(try parser(), page: 9, usage: usage, 1) == nil)
  }

  @Test
  func cableAndDongleShareOneUsageMap() throws {
    let record = try #require(ProtocolDriverRegistry().record(for: Self.cable))
    #expect(record.modes.isEmpty)
    #expect(record.hasDefaultMode)
  }

  /// The Ultimate 2 and the Pro 3 may both present `2DC8:310B`; one default mode serves either.
  @Test
  func sharedIdentitySelectsOneModeForBothModels() throws {
    let model = ControllerModelID(vendorID: 0x2DC8, productID: 0x310B)
    let record = try #require(ProtocolDriverRegistry().record(for: model))
    #expect(record.modes.isEmpty)
    #expect(record.hasDefaultMode)
    #expect(!record.isIdle)
    #expect(record.physicalProtocolID == .xboxXUSB)
    #expect(record.hidUsageMap == nil)
  }

  @Test(arguments: [UInt16(0x6013), 0x3107])
  func receiverAndDongleMapNoControls(productID: UInt16) throws {
    let model = ControllerModelID(vendorID: 0x2DC8, productID: productID)
    let record = try #require(ProtocolDriverRegistry().record(for: model))
    #expect(record.isIdle)
    #expect(record.hidUsageMap == nil)
  }

  @Test
  func ultimate3ModeReplaysXboxButtonOrder() throws {
    let model = ControllerModelID(vendorID: 0x2DC8, productID: 0x901B)
    let parser = HIDDescriptorDriver(model: model, usageMap: try catalogUsageMap(0x2DC8, 0x901B))
    let order: [Control] = [
      .south, .east, .west, .north, .leftShoulder, .rightShoulder, .back, .start,
      .leftStickClick, .rightStickClick,
    ]
    for (index, button) in order.enumerated() {
      let press = Base.parse(parser, page: 9, usage: UInt32(index + 1), 1)
      #expect(press.contains(.press(button)), "usage \(index + 1)")
    }
    #expect(Base.parse(parser, page: 12, usage: 547, 1).contains(.press(.guide)))
    #expect(Base.parse(parser, usage: 0x32, 255).contains(.rightStick(x: 1, y: 0)))
  }

  @Test(arguments: [UInt16(0x6012), 0x6013, 0x3107, 0x901B])
  func recordsHaveNoKeepAlive(productID: UInt16) throws {
    let model = ControllerModelID(vendorID: 0x2DC8, productID: productID)
    let record = try #require(ProtocolDriverRegistry().record(for: model))
    #expect(record.session.keepAlive == nil)
  }
}
