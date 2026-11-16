import Foundation
import ProtocolPacketFixtures
import Testing

@testable import OpenJoystickDriverKit

/// The NITHO MLT-KRMA-K by cable with the slider in the middle, `054C:0268` with the manufacturer
/// `Sony Computer Entertainment`.
///
/// The maintainer's capture put A on the Circle bit, B on Cross, X on Triangle and Y on Square, so
/// the Sixaxis family read A as East.
struct NithoPS3Tests {
  private static let model = ControllerModelID(vendorID: 0x054C, productID: 0x0268)

  private func select(manufacturer: String) async throws -> ControllerModeSelection {
    let profile = try #require(ProtocolDriverRegistry().record(for: Self.model))
    let device = PhysicalDevice(
      vendorID: Self.model.vendorID,
      productID: Self.model.productID,
      manufacturer: manufacturer,
      productName: "PLAYSTATION(R)3 Controller",
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

  /// A real DUALSHOCK 3 names its manufacturer `Sony`, per `docs/testing/sixaxis-vs-ds3.md`.
  @Test
  func onlyNithoManufacturerSelectsNithoMode() async throws {
    #expect(try await select(manufacturer: "Sony Computer Entertainment") == .matched("nitho"))
    #expect(try await select(manufacturer: "Sony") != .matched("nitho"))
  }

  @Test(arguments: [
    (UInt8(0x20), Control.south), (0x40, .east), (0x10, .west), (0x80, .north),
  ])
  func faceButtonReadsAsItsLabel(bit: UInt8, control: Control) throws {
    let driver = try catalogParser(Self.model, host: .usb, modeID: "nitho")
    _ = try driver.parseReport(ProtocolPacketFixtures.DS3.inputReport())
    let events = try driver.parseReport(
      ProtocolPacketFixtures.DS3.inputReport(buttons: (0, bit, false))
    )
    #expect(events?.state.pressed == [control])
  }

  @Test
  func defaultModeKeepsSixaxisFaceButtons() throws {
    let driver = try catalogParser(Self.model, host: .usb)
    _ = try driver.parseReport(ProtocolPacketFixtures.DS3.inputReport())
    let events = try driver.parseReport(
      ProtocolPacketFixtures.DS3.inputReport(buttons: (0, 0x40, false))
    )
    #expect(events?.state.pressed == [.south])
  }
}
