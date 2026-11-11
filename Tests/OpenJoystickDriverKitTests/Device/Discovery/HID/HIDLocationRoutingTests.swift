import Foundation
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit

/// A family without a HID role predicate keeps one controller per routing location, whatever
/// interfaces the location exposes.
///
/// The two GameSir connections here are synthetic: no GameSir enhanced-HID interface capture
/// exists.
struct HIDLocationRoutingTests {
  @Test
  func twoGameSirConnectionsAtOneLocationKeepOneLocationController() async throws {
    let backend = ScriptedHIDAccessBackend()
    await backend.enableOutputReports()
    await backend.enableFeatureReports()
    let recorder = HIDRoleEventRecorder()
    let manager = DeviceManager(
      dispatcher: recorder,
      installationKey: testPortKeyInstallationKey,
      hidManager: HIDManager(backend: backend)
    )
    await manager.markStartedForTest()
    let first = Self.gameSir(interfaceNumber: 0)
    let second = Self.gameSir(interfaceNumber: 1)
    await backend.setConnectionSnapshots(
      [first, second].map { HIDDeviceConnectionSnapshot(connection: $0, ownership: .exclusive) }
    )

    await manager.handleHIDEvent(.connected(connection: first, ownership: .exclusive))
    await manager.handleHIDEvent(.connected(connection: second, ownership: .exclusive))

    // The later connection replaces the earlier one under the one location key.
    let identifier = LogicalControllerID(
      vendorID: 0x3537,
      productID: 0x100B,
      locationID: Self.locationID
    )
    #expect(Array(await manager.pipelines.keys) == [identifier])
    #expect(await manager.deviceInfos[identifier]?.hidConnectionID == second.connectionID)
    // The key names no interface, but the description shows the observed one.
    #expect(await manager.connectedDeviceDescriptions().map(\.interfaceNumber) == [1])

    // Input from either interface reaches the location's controller, here the replaced one's.
    await manager.handleHIDEvent(
      .inputReport(
        address: .ioKit(locationID: Self.locationID, interfaceNumber: nil),
        connectionID: first.connectionID,
        reportID: 0x12,
        data: Self.aPressed
      )
    )
    #expect(recorder.pressed(from: identifier).contains(.south))

    // Removing the replaced interface tears nothing down.
    await manager.handleHIDEvent(.disconnected(connection: first))
    #expect(Array(await manager.pipelines.keys) == [identifier])

    await manager.handleHIDEvent(.disconnected(connection: second))
    #expect(await manager.pipelines.isEmpty)
    await manager.stop()
  }

  static let locationID: UInt32 = 0x0021_0000

  /// A GameSir enhanced-HID report with A pressed.
  static let aPressed: Data = {
    var report = [UInt8](repeating: 0, count: 64)
    report.replaceSubrange(0..<6, with: [0x12, 0x80, 0x80, 0x80, 0x80, 0x20])
    return Data(report)
  }()

  private static func gameSir(interfaceNumber: UInt8) -> HIDDeviceConnection {
    HIDDeviceConnection(
      physicalDevice: PhysicalDevice(
        vendorID: 0x3537,
        productID: 0x100B,
        productName: "GameSir",
        transportProperty: "USB",
        physicalLocationIdentifier: locationID,
        interfaces: [
          PhysicalInterfaceSignature(
            interfaceNumber: interfaceNumber,
            hostTransport: .usb,
            accessBackend: .hid,
            hidLayout: HIDLayoutSummary(reportDescriptor: Data(GamepadHIDDescriptor.descriptor))
          )
        ]
      ),
      routingAddress: .ioKit(locationID: locationID, interfaceNumber: nil)
    )
  }
}
