import Foundation
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit

private final class DisconnectProbe: WirelessControllerDisconnecting, @unchecked Sendable {
  private let lock = NSLock()
  private var addresses: [String] = []

  func disconnect(
    address: String,
    timeoutNanoseconds _: UInt64
  ) async -> WirelessControllerDisconnectOutcome {  // swiftlint:disable:this async_without_await
    lock.withLock { addresses.append(address) }
    return .disconnected
  }

  var calls: [String] { lock.withLock { addresses } }
}

@Suite
struct IdleDisconnectManagerTests {
  private func connect(_ manager: DeviceManager, link: String, location: UInt32) async {
    await manager.handleHIDEvent(
      .connected(
        connection: HIDDeviceConnection(
          physicalDevice: PhysicalDevice(
            vendorID: 0x054C,
            productID: 0x09CC,
            productName: "Wireless Controller",
            serialNumber: "aa-bb-cc-dd-ee-ff",
            transportProperty: link,
            physicalLocationIdentifier: location,
            interfaces: [hostHIDInterface(testHostTransport(link))]
          ),
          routingAddress: .ioKit(locationID: location, interfaceNumber: nil)
        ),
        ownership: .exclusive
      )
    )
  }

  @Test
  func idleBluetoothControllerDisconnectsThroughMenusPath() async {
    let probe = DisconnectProbe()
    let manager = DeviceManager(
      dispatcher: ControllerSessionOutputProbe(),
      installationKey: testPortKeyInstallationKey,
      wirelessControllerDisconnector: probe
    )
    await connect(manager, link: "Bluetooth", location: 81)

    let disconnected = await manager.disconnectIdleWirelessControllers(afterMinutes: 0)

    #expect(disconnected.count == 1)
    #expect(probe.calls == ["AA:BB:CC:DD:EE:FF"])
    await manager.stop()
  }

  @Test
  func cableConnectionLeftAlone() async {
    let probe = DisconnectProbe()
    let manager = DeviceManager(
      dispatcher: ControllerSessionOutputProbe(),
      installationKey: testPortKeyInstallationKey,
      wirelessControllerDisconnector: probe
    )
    await connect(manager, link: "USB", location: 82)

    let disconnected = await manager.disconnectIdleWirelessControllers(afterMinutes: 0)

    #expect(disconnected.isEmpty)
    #expect(probe.calls.isEmpty)
    await manager.stop()
  }
}
