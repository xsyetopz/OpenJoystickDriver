import Foundation
import ProtocolPacketFixtures
import Testing

@testable import OpenJoystickDriverKit

/// Steam Controller HID roles. The interface layouts follow Linux `hid-steam.c`
/// (hid-steam.c:1098–1108) through ``steamHIDInterface(number:gamepad:)``; they are not a macOS
/// capture.
struct SteamHIDRoleTests {
  static let dongleLocation: UInt32 = 0x0031_0000

  @Test
  func dongleRunsOneRolePerSlotAndRoutesEachConnection() async throws {
    let backend = ScriptedHIDAccessBackend()
    await backend.enableFeatureReports()
    let recorder = HIDRoleEventRecorder()
    let manager = DeviceManager(dispatcher: recorder, hidManager: HIDManager(backend: backend))
    await manager.markStartedForTest()
    let connections = (0...4).map { Self.dongle(interface: $0) }
    await backend.setConnectionSnapshots(
      connections.map { HIDDeviceConnectionSnapshot(connection: $0, ownership: .exclusive) }
    )
    // Back-to-back arrivals, as the detection loop schedules them: a slot's initialization is
    // keyed by its connection, so a later sibling does not cancel it.
    await manager.scheduleHIDInitializationsForTest(connections)
    try await Self.waitForInitializations(of: manager)

    // Interface 0 has no feature report, so it is no role; slots 1–4 each run a pipeline.
    let slots = (1...4).map { Self.slot($0) }
    #expect(Set(await manager.pipelines.keys) == Set(slots))
    #expect(await manager.unboundDeviceDescriptions().map(\.reason) == [.interfaceContractMismatch])
    // Each slot asks its own connection for the wireless state.
    let startupTargets = await backend.recordedFeatureReportTargets()
    #expect(Set(startupTargets) == Set(connections.dropFirst().map(\.connectionID)))

    // Presence is per slot: only slot 2's connection reports a connected controller.
    let startupCount = startupTargets.count
    await Self.send(
      ProtocolPacketFixtures.Steam.wirelessReport(status: 0x02),
      on: connections[2],
      to: manager
    )
    let activationTargets = await backend.recordedFeatureReportTargets().dropFirst(startupCount)
    #expect(!activationTargets.isEmpty)
    #expect(activationTargets.allSatisfy { $0 == connections[2].connectionID })

    // State reports reach only the slot whose connection sent them; interface 0 feeds none.
    let aPressed = ProtocolPacketFixtures.Steam.inputReport(buttons: (0x80, 0, 0))
    await Self.send(aPressed, on: connections[2], to: manager)
    await Self.send(aPressed, on: connections[0], to: manager)
    #expect(recorder.pressed(from: slots[1]).contains(.faceSouth))
    for slot in [slots[0], slots[2], slots[3]] {
      #expect(!recorder.pressed(from: slot).contains(.faceSouth))
    }

    // The keyboard interface leaving first stops no slot.
    await manager.handleHIDEvent(.disconnected(connection: connections[0]))
    #expect(Set(await manager.pipelines.keys) == Set(slots))
    #expect(await manager.unboundDeviceDescriptions().isEmpty)

    // One slot's disconnect leaves the other slots running.
    await manager.handleHIDEvent(.disconnected(connection: connections[2]))
    #expect(Set(await manager.pipelines.keys) == Set([slots[0], slots[2], slots[3]]))

    // Unplugging the dongle removes the remaining interfaces one by one.
    for connection in [connections[1], connections[3], connections[4]] {
      await manager.handleHIDEvent(.disconnected(connection: connection))
    }
    #expect(await manager.pipelines.isEmpty)
    #expect(await manager.deviceInfos.isEmpty)
    #expect(await manager.hidRoleConnections.isEmpty)
    await manager.stop()
  }

  static func waitForInitializations(of manager: DeviceManager) async throws {
    for _ in 0..<400 where await !manager.hidInitializationTasks.isEmpty {
      try await Task.sleep(for: .milliseconds(5))
    }
    #expect(await manager.hidInitializationTasks.isEmpty)
  }

  @Test
  func wiredControllerBindsOnlyInterfaceTwoAndHoldsItsSiblingsClaim() async throws {
    let backend = ClaimRecordingHIDAccessBackend()
    let manager = DeviceManager(
      dispatcher: LoggingOutputDispatcher(),
      hidManager: HIDManager(backend: backend)
    )
    let location: UInt32 = 0x0032_0000
    let connections = (0...2).map { number in
      HIDDeviceConnection(
        physicalDevice: PhysicalDevice(
          vendorID: 0x28DE,
          productID: 0x1102,
          productName: "Steam Controller",
          transportProperty: "USB",
          physicalLocationIdentifier: location,
          interfaces: [steamHIDInterface(number: number, gamepad: number == 2)]
        ),
        routingLocationID: location
      )
    }

    await manager.handleHIDEvent(.connected(connection: connections[0], ownership: .exclusive))
    #expect(await backend.releasedLocations() == [location])
    for connection in connections.dropFirst() {
      await manager.handleHIDEvent(.connected(connection: connection, ownership: .exclusive))
    }

    let role = DeviceIdentifier(
      vendorID: 0x28DE,
      productID: 0x1102,
      locationID: location,
      interfaceNumber: 2
    )
    #expect(Array(await manager.pipelines.keys) == [role])
    #expect(await manager.unboundDeviceDescriptions().count == 2)
    // The mouse and keyboard claims are held while the gamepad role is bound.
    #expect(await !backend.reacquiredLocations().isEmpty)
    let claims = await manager.unboundHIDClaims.values
    #expect(claims.count == 2 && claims.allSatisfy { !$0.isReleased })
    await manager.stop()
  }

  @Test
  func removingOneRoleInterfaceDisconnectsItAlone() {
    var adapter = PhysicalHIDBackendEventAdapter()
    for deviceID in [UInt64(1), 2] {
      adapter.add(
        deviceID: deviceID,
        locationID: 5,
        syntheticProperty: nil,
        disconnectsIndividually: true
      )
    }
    for deviceID in [UInt64(3), 4] {
      adapter.add(deviceID: deviceID, locationID: 6, syntheticProperty: nil)
    }

    let role = adapter.remove(deviceID: 1)
    #expect(role.shouldEmitDisconnect && !role.locationRemoved)
    let lastRole = adapter.remove(deviceID: 2)
    #expect(lastRole.shouldEmitDisconnect && lastRole.locationRemoved)
    // Without roles a location still disconnects once, when it empties.
    #expect(!adapter.remove(deviceID: 3).shouldEmitDisconnect)
    #expect(adapter.remove(deviceID: 4).shouldEmitDisconnect)
  }

  @Test
  func onlyTheSteamFamilyDeclaresRoles() throws {
    let registry = ProtocolDriverRegistry()
    #expect(
      Set(registry.hidRoleIdentifiers)
        == Set(
          [
            0x1101, 0x1102, 0x1105, 0x1106, 0x1142, 0x1201, 0x1202, 0x1205, 0x1302, 0x1303, 0x1304,
            0x1305,
          ].map { DeviceIdentifier(vendorID: 0x28DE, productID: $0) }
        )
    )
    let slot = Self.dongle(interface: 1).physicalDevice
    #expect(registry.hidConnectionRole(of: slot) == .interface(1))
    #expect(registry.hidConnectionRole(of: Self.dongle(interface: 0).physicalDevice) == .notARole)
    // A gamepad interface whose USB interface number was not observed fails closed.
    let unnumbered = PhysicalDevice(
      vendorID: 0x28DE,
      productID: 0x1142,
      interfaces: [
        PhysicalInterfaceSignature(
          hostTransport: .usb,
          accessBackend: .ioHID,
          hidLayout: steamHIDInterface(number: 1).hidLayout
        )
      ]
    )
    #expect(registry.hidConnectionRole(of: unnumbered) == .notARole)
    let gameSir = PhysicalDevice(
      vendorID: 0x3537,
      productID: 0x100B,
      interfaces: [steamHIDInterface(number: 1)]
    )
    #expect(registry.hidConnectionRole(of: gameSir) == .location)
  }

  /// SDL `HIDAPI_DriverSteamTriton_IsSupportedDevice`: dongle controllers live on interfaces
  /// 2–5; the Bluetooth LE controller has no USB interface number.
  @Test
  func tritonDongleSlotsAreInterfacesTwoToFiveAndBluetoothIsItsLocation() {
    let registry = ProtocolDriverRegistry()
    for number: UInt8 in 0...6 {
      let dongle = PhysicalDevice(
        vendorID: 0x28DE,
        productID: 0x1304,
        interfaces: [steamHIDInterface(number: number)]
      )
      let expected: HIDConnectionRole = (2...5).contains(number) ? .interface(number) : .notARole
      #expect(registry.hidConnectionRole(of: dongle) == expected)
    }
    let bluetooth = PhysicalDevice(
      vendorID: 0x28DE,
      productID: 0x1303,
      interfaces: [
        PhysicalInterfaceSignature(
          hostTransport: .bluetoothLE,
          accessBackend: .ioHID,
          hidLayout: steamHIDInterface(number: 0).hidLayout
        )
      ]
    )
    #expect(registry.hidConnectionRole(of: bluetooth) == .location)
  }

  static func slot(_ number: UInt8) -> DeviceIdentifier {
    DeviceIdentifier(
      vendorID: 0x28DE,
      productID: 0x1142,
      locationID: dongleLocation,
      interfaceNumber: number
    )
  }

  static func dongle(interface number: UInt8) -> HIDDeviceConnection {
    HIDDeviceConnection(
      physicalDevice: PhysicalDevice(
        vendorID: 0x28DE,
        productID: 0x1142,
        productName: "Steam Controller Dongle",
        transportProperty: "USB",
        physicalLocationIdentifier: dongleLocation,
        interfaces: [steamHIDInterface(number: number, gamepad: number != 0)]
      ),
      routingLocationID: dongleLocation
    )
  }

  static func send(
    _ report: Data,
    on connection: HIDDeviceConnection,
    to manager: DeviceManager
  ) async {
    await manager.handleHIDEvent(
      .inputReport(
        locationID: connection.routingLocationID,
        connectionID: connection.connectionID,
        reportID: 1,
        data: report
      )
    )
  }
}
