import Foundation
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit

/// The Wii U GameCube adapter, 057E:0337, as one HID connection that serves four pads.
///
/// Reports follow Dolphin `GCAdapter.cpp`: report `0x21` carries nine bytes per port at
/// `1 + 9 * port`, and the start report is `0x13`. They are not a macOS capture.
struct GameCubeAdapterHIDPortTests {
  static let location: UInt32 = 0x0041_0000
  static let model = ControllerModelID(vendorID: 0x057E, productID: 0x0337)

  static let connection = HIDDeviceConnection(
    physicalDevice: PhysicalDevice(
      vendorID: 0x057E,
      productID: 0x0337,
      productName: "WUP-028",
      transportProperty: "USB",
      physicalLocationIdentifier: location,
      interfaces: [
        PhysicalInterfaceSignature(interfaceNumber: 0, hostTransport: .usb, accessBackend: .hid)
      ]
    ),
    routingAddress: .ioKit(locationID: location, interfaceNumber: nil)
  )

  static func port(_ number: UInt8) -> LogicalControllerID {
    LogicalControllerID(
      hardware: ControllerHardwareIdentity(model: model),
      address: .adapterPort(locationID: location, port: number)
    )
  }

  /// A report with port 2 wired and powered, and its A button held.
  static let port2PressesA: Data = {
    var report = [UInt8](repeating: 0, count: 37)
    report[0] = 0x21
    let base = 1 + 9 * 2
    report[base] = 0x14
    report[base + 1] = 0x01
    for offset in 3...6 { report[base + offset] = 128 }
    return Data(report)
  }()

  @Test
  func oneConnectionRunsAPipelinePerPortAndRoutesEachPortsBytes() async {
    let backend = ScriptedHIDAccessBackend()
    await backend.enableOutputReports()
    let recorder = HIDRoleEventRecorder()
    let manager = DeviceManager(
      dispatcher: recorder,
      installationKey: testPortKeyInstallationKey,
      hidManager: HIDManager(backend: backend)
    )
    await manager.markStartedForTest()
    await backend.setConnectionSnapshots([
      HIDDeviceConnectionSnapshot(connection: Self.connection, ownership: .exclusive)
    ])

    await manager.handleHIDEvent(.connected(connection: Self.connection, ownership: .exclusive))
    await SteamHIDRoleTests.waitForInitializations(of: manager)

    let ports = (0...3).map { Self.port(UInt8($0)) }
    #expect(Set(await manager.pipelines.keys) == Set(ports))
    // Only port 0 sends the start report, so the adapter receives it once.
    #expect(await backend.recordedOutputReports().map(\.bytes).filter { $0 == [0x13] }.count == 1)

    await manager.handleHIDEvent(
      .inputReport(
        address: Self.connection.routingAddress,
        connectionID: Self.connection.connectionID,
        reportID: 0x21,
        data: Self.port2PressesA
      )
    )
    #expect(recorder.pressed(from: ports[2]).contains(.south))
    for port in [ports[0], ports[1], ports[3]] {
      #expect(!recorder.pressed(from: port).contains(.south))
    }

    // Unplugging the adapter retires every port.
    await manager.handleHIDEvent(.disconnected(connection: Self.connection))
    #expect(await manager.pipelines.isEmpty)
    #expect(await manager.deviceInfos.isEmpty)
    await manager.stop()
  }

  @Test
  func registryGivesTheAdapterFourPorts() {
    #expect(
      ProtocolDriverRegistry().hidConnectionRole(of: Self.connection.physicalDevice)
        == .ports(4)
    )
  }

  @Test
  func adapterPortsHaveDistinctKeysAndSortByPort() {
    let addresses = (0...3).map {
      ControllerConnectionAddress.adapterPort(locationID: Self.location, port: UInt8($0))
    }
    #expect(addresses.shuffled().sorted() == addresses)
    #expect(addresses.allSatisfy { $0.locationID == Self.location && $0.interfaceNumber == nil })
    #expect(addresses.map(\.adapterPort) == [0, 1, 2, 3])
    let keys = Set(
      (0...3).map {
        ControllerPortKey.of(Self.port(UInt8($0)), installationKey: testPortKeyInstallationKey)
      }
    )
    #expect(keys.count == 4 && !keys.contains(nil))
  }
}
