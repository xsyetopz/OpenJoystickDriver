import Foundation
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit

/// A suspended controller holds no HID handle, whichever way the HID backend admits it again.
@Suite(.timeLimit(.minutes(2)))
struct SuspendedHIDHandleTests {
  private static let locationID: UInt32 = 76

  @Test
  func suspendedControllerAdmittedAgainKeepsHIDHandlesClosed() async throws {
    let (manager, backend, _) = try await Self.suspendedController()
    await backend.openHandle(at: Self.locationID)

    await manager.handleHIDEvent(.connected(connection: Self.connection(), ownership: .exclusive))

    #expect(await manager.suspendedControllerIdentities.count == 1)
    #expect(!(await backend.hasOpenHandle(at: Self.locationID)))
    let resumed = try #require(await manager.connectedDeviceDescriptions().first)
    #expect(await manager.resumeController(.session(resumed.sessionToken)).failure == nil)
    #expect(await backend.hasOpenHandle(at: Self.locationID))
    await manager.stop()
  }

  @Test
  func ownershipReevaluationWhileSuspendedKeepsHIDHandlesClosed() async throws {
    let (manager, backend, old) = try await Self.suspendedController()
    let new = Self.connection()
    await backend.admitOnReevaluation(new)

    await manager.reloadControllerRecords(changing: [Self.model])
    await manager.handleHIDEvent(.disconnected(connection: old))
    await manager.handleHIDEvent(.connected(connection: new, ownership: .exclusive))

    #expect(await manager.suspendedControllerIdentities.count == 1)
    #expect(!(await backend.hasOpenHandle(at: Self.locationID)))
    let resumed = try #require(await manager.connectedDeviceDescriptions().first)
    #expect(await manager.resumeController(.session(resumed.sessionToken)).failure == nil)
    #expect(await backend.hasOpenHandle(at: Self.locationID))
    await manager.stop()
  }

  private static let model = ControllerModelID(vendorID: 0x054C, productID: 0x09CC)

  /// A suspended controller on a started manager, its handle open before the suspension.
  private static func suspendedController() async throws -> (
    DeviceManager, ClaimRecordingHIDAccessBackend, HIDDeviceConnection
  ) {
    let backend = ClaimRecordingHIDAccessBackend()
    let manager = DeviceManager(
      dispatcher: ControllerSessionOutputProbe(),
      installationKey: testPortKeyInstallationKey,
      hidManager: HIDManager(backend: backend)
    )
    await manager.markStartedForTest()
    let old = connection()
    await manager.handleHIDEvent(.connected(connection: old, ownership: .exclusive))
    await backend.openHandle(at: locationID)
    let device = try #require(await manager.connectedDeviceDescriptions().first)
    #expect(await manager.suspendController(.session(device.sessionToken)).failure == nil)
    #expect(!(await backend.hasOpenHandle(at: locationID)))
    return (manager, backend, old)
  }

  private static func connection() -> HIDDeviceConnection {
    HIDDeviceConnection(
      physicalDevice: PhysicalDevice(
        vendorID: model.vendorID,
        productID: model.productID,
        productName: "Controller",
        transportProperty: "USB",
        physicalLocationIdentifier: locationID,
        interfaces: [hostHIDInterface(.usb)]
      ),
      routingAddress: .ioKit(locationID: locationID, interfaceNumber: nil)
    )
  }
}
