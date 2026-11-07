import Testing

@testable import OpenJoystickDriverKit

/// The Ultimate 2 records, from sources only.
///
/// No capture of an Ultimate 2 backs them, and no source
/// gives its rear-button usages, so the records map no paddle: paddles wait for tester check T5.
struct EightBitDoUltimate2Tests {
  private typealias Base = EightBitDoUltimate2CTests
  private static let cable = ControllerModelID(vendorID: 0x2DC8, productID: 0x6012)

  private func parser() throws -> HIDDescriptorDriver {
    HIDDescriptorDriver(model: Self.cable, usageMap: try catalogUsageMap(0x2DC8, 0x6012))
  }

  @Test
  func replaysTheUltimate2CUsages() throws {
    let parser = try parser()
    for (usage, button) in Base.buttonTable {
      let press = Base.parse(parser, page: 9, usage: usage, 1)
      #expect(press.contains(.press(button)), "usage \(usage)")
    }
    #expect(Base.parse(parser, usage: 0x32, 255).contains(.rightStick(x: 1, y: 0)))
    #expect(Base.parse(parser, usage: 0x33, 255) == nil)
  }

  @Test(arguments: [UInt32(3), 6, 9, 10])
  func mapsNoRearButton(usage: UInt32) throws {
    #expect(Base.parse(try parser(), page: 9, usage: usage, 1) == nil)
  }

  @Test(arguments: [UInt16(0x6013), 0x3107])
  func receiverAndDongleMapNoControls(productID: UInt16) throws {
    let model = ControllerModelID(vendorID: 0x2DC8, productID: productID)
    let record = try #require(ProtocolDriverRegistry().record(for: model))
    #expect(record.isIdle)
    #expect(record.hidUsageMap == nil)
  }
}
