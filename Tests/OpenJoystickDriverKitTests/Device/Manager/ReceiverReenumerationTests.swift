import Foundation
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit

/// The 8BitDo Ultimate 2C dongle `2DC8:301C` re-enumerates at the same location when its pad links
/// or unlinks; the binding of the earlier enumeration must not outlive it.
struct ReceiverReenumerationTests {
  enum Order: CaseIterable {
    case removedThenAdded
    case addedThenRemoved
  }

  private static let locationID: UInt32 = 0x0114_0000

  private static func dongle(
    product: String,
    serial: String?,
    native: Bool
  ) -> HIDDeviceConnection {
    HIDDeviceConnection(
      physicalDevice: PhysicalDevice(
        vendorID: 0x2DC8,
        productID: 0x301C,
        productName: product,
        serialNumber: serial,
        transportProperty: "USB",
        physicalLocationIdentifier: locationID,
        interfaces: [gamepadHIDInterface(host: .usb)],
        nativePassThrough: native
      ),
      routingAddress: .ioKit(locationID: locationID, interfaceNumber: nil)
    )
  }

  private func replay(
    order: Order,
    oldSerial: String?,
    newSerial: String?,
    oldNative: Bool
  ) async throws {
    let manager = DeviceManager(
      dispatcher: LoggingOutputDispatcher(),
      installationKey: testPortKeyInstallationKey,
      hidManager: HIDManager(backend: ClaimRecordingHIDAccessBackend())
    )
    let linked = Self.dongle(
      product: "8BitDo Ultimate 2C Wireless Controller",
      serial: oldSerial,
      native: oldNative
    )
    let idle = Self.dongle(product: "IDLE", serial: newSerial, native: false)
    await manager.handleHIDEvent(.connected(connection: linked, ownership: .exclusive))
    try #require(await manager.connectedDeviceDescriptions().count == 1)

    switch order {
    case .removedThenAdded:
      await manager.handleHIDEvent(.disconnected(connection: linked))
      await manager.handleHIDEvent(.connected(connection: idle, ownership: .exclusive))
    case .addedThenRemoved:
      await manager.handleHIDEvent(.connected(connection: idle, ownership: .exclusive))
      await manager.handleHIDEvent(.disconnected(connection: linked))
    }

    #expect(await manager.connectedDeviceDescriptions().isEmpty)
    #expect(await manager.passThroughDeviceDescriptions().isEmpty)
    let unbound = await manager.unboundDeviceDescriptions()
    #expect(unbound.count == 1)
    #expect(unbound.first?.reason == .noControllerLinked)
    await manager.stop()
  }

  @Test(arguments: Order.allCases, [false, true])
  func sameSerial(order: Order, oldNative: Bool) async throws {
    try await replay(order: order, oldSerial: "A1", newSerial: "A1", oldNative: oldNative)
  }

  @Test(arguments: Order.allCases, [false, true])
  func differentSerial(order: Order, oldNative: Bool) async throws {
    try await replay(order: order, oldSerial: "A1", newSerial: nil, oldNative: oldNative)
  }
}
