import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct NativePassThroughTests {
  @Test
  func nativeGamepadBindsObserveOnlyWithoutDeviceWrites() async throws {
    let backend = ScriptedHIDAccessBackend()
    await backend.enableOutputReports()
    await backend.enableFeatureReports()
    let dispatcher = NativeEventRecorder()
    let manager = DeviceManager(dispatcher: dispatcher, hidManager: HIDManager(backend: backend))
    await manager.markStartedForTest()
    let connection = Self.dualShock4Bluetooth(locationID: 70)
    await backend.setConnectionSnapshots([
      HIDDeviceConnectionSnapshot(connection: connection, ownership: .unknown)
    ])

    await manager.handleHIDEvent(.connected(connection: connection, ownership: .unknown))

    let device = try #require(await manager.connectedDeviceDescriptions().first)
    #expect(device.protocolBinding.protocolID == .sonyDualShock4)
    #expect(device.physicalOwnership == .nativeGamepad)
    #expect(device.duplicateExposureRisk == DuplicateExposureRisk.none)
    #expect(device.physicalOutputCapabilities == .none)
    #expect(await manager.passThroughDeviceDescriptions().isEmpty)
    let identifier = try #require(await manager.pipelines.keys.first)
    #expect(await manager.pipelines[identifier]?.observesOnly == true)
    #expect(await manager.ownershipObservation(for: identifier) == .nativeGamepad)

    // A neutral report first, so a slow run that trips input liveness recovers before the press.
    for (buttons, timestamp) in [(UInt8(0x08), UInt16(1)), (0x28, 2)] {
      let report = makeDS4BluetoothReport(buttons0: buttons, sensorTimestamp: timestamp)
      await manager.handleHIDEvent(
        .inputReport(
          locationID: 70,
          connectionID: connection.connectionID,
          reportID: 0x11,
          data: report
        )
      )
    }
    #expect(dispatcher.states.contains { $0.pressed.contains(.faceSouth) })

    #expect(
      !(await manager.sendManualRumble(
        for: identifier,
        left: 255,
        right: 255,
        lt: 0,
        rt: 0,
        durationMs: 100
      ))
    )
    await manager.handleHIDEvent(.ownershipChanged(locationID: 70, ownership: .exclusive))
    #expect(await manager.ownershipObservation(for: identifier) == .nativeGamepad)
    await manager.handleHIDEvent(.disconnected(connection: connection))
    #expect(await manager.connectedDeviceDescriptions().isEmpty)
    #expect(await backend.recordedOutputReports().isEmpty)
    #expect(await backend.recordedFeatureReports().isEmpty)
    // Only the calibration read that switches Bluetooth to report 0x11, on the exact connection,
    // retried while the scripted backend has no reply.
    #expect(await backend.recordedFeatureReadReportIDs() == [5, 5, 5])
    let readTargets = await backend.recordedFeatureReadTargets()
    #expect(readTargets == Array(repeating: connection.connectionID, count: 3))
    await manager.stop()
  }

  @Test
  func unboundNativeDeviceIsLeftToMacOSWithoutClaimReconciliation() async {
    let backend = ClaimRecordingHIDAccessBackend()
    let manager = DeviceManager(
      dispatcher: LoggingOutputDispatcher(),
      hidManager: HIDManager(backend: backend)
    )
    let connection = Self.connection(locationID: 71, nativePassThrough: true, binds: false)

    await manager.handleHIDEvent(.connected(connection: connection, ownership: .unknown))

    #expect(await manager.connectedDeviceDescriptions().isEmpty)
    #expect(await manager.unboundDeviceDescriptions().isEmpty)
    #expect(
      await manager.passThroughDeviceDescriptions() == [
        PassThroughDeviceSnapshot(vendorID: 0x1234, productID: 0x5678, connection: "USB")
      ]
    )
    #expect(await manager.unboundHIDClaims.isEmpty)
    #expect(await backend.releasedLocations().isEmpty)
    #expect(await backend.reacquiredLocations().isEmpty)

    await manager.handleHIDEvent(.disconnected(connection: connection))
    #expect(await manager.passThroughDeviceDescriptions().isEmpty)
    await manager.stop()
  }

  @Test
  func nativeConnectionReplacesAHIDDeviceBoundAtItsLocation() async throws {
    let backend = ClaimRecordingHIDAccessBackend()
    let manager = DeviceManager(
      dispatcher: LoggingOutputDispatcher(),
      hidManager: HIDManager(backend: backend)
    )
    let bound = Self.connection(locationID: 74, nativePassThrough: false)
    await manager.handleHIDEvent(.connected(connection: bound, ownership: .exclusive))
    try #require(await manager.connectedDeviceDescriptions().count == 1)

    let native = Self.connection(locationID: 74, nativePassThrough: true)
    await manager.handleHIDEvent(.connected(connection: native, ownership: .unknown))

    let devices = await manager.connectedDeviceDescriptions()
    #expect(devices.map(\.physicalOwnership) == [.nativeGamepad])
    #expect(await manager.passThroughDeviceDescriptions().isEmpty)
    #expect(await backend.releasedLocations() == [74])
    #expect(await backend.reacquiredLocations().isEmpty)
    await manager.stop()
  }

  @Test
  func siblingInterfaceOfANativeControllerIsLeftToMacOS() async {
    let backend = ClaimRecordingHIDAccessBackend()
    let manager = DeviceManager(
      dispatcher: LoggingOutputDispatcher(),
      hidManager: HIDManager(backend: backend)
    )
    let native = Self.connection(locationID: 75, nativePassThrough: true)
    await manager.handleHIDEvent(.connected(connection: native, ownership: .unknown))
    let sibling = Self.connection(locationID: 75, nativePassThrough: false)
    await manager.handleHIDEvent(.connected(connection: sibling, ownership: .exclusive))

    let owners = await manager.connectedDeviceDescriptions().map(\.physicalOwnership)
    #expect(owners == [.nativeGamepad])
    #expect(await manager.passThroughDeviceDescriptions().count == 1)
    #expect(await backend.releasedLocations() == [75])
    #expect(await backend.reacquiredLocations().isEmpty)

    await manager.handleHIDEvent(.disconnected(connection: sibling))
    await manager.handleHIDEvent(.disconnected(connection: native))
    #expect(await manager.passThroughDeviceDescriptions().isEmpty)
    #expect(await manager.connectedDeviceDescriptions().isEmpty)
    await manager.stop()
  }

  @Test
  func nativeBindsWhenItCancelsASiblingInitializationAtItsLocation() async throws {
    let manager = DeviceManager(
      dispatcher: LoggingOutputDispatcher(),
      hidManager: HIDManager(backend: ClaimRecordingHIDAccessBackend())
    )
    let sibling = Self.connection(locationID: 79, nativePassThrough: false)
    let native = Self.connection(locationID: 79, nativePassThrough: true)

    await manager.scheduleSiblingThenConnectNative(sibling, native)

    let identifier = try #require(await manager.pipelines.keys.first)
    #expect(await manager.deviceInfos[identifier]?.hidConnectionID == native.connectionID)
    #expect(await manager.pipelines[identifier]?.observesOnly == true)
    await manager.stop()
  }

  @Test
  func rejectedSiblingIsNotReclaimedWhenTheNativeControllerBinds() async {
    let backend = ClaimRecordingHIDAccessBackend()
    let manager = DeviceManager(
      dispatcher: LoggingOutputDispatcher(),
      hidManager: HIDManager(backend: backend)
    )
    let sibling = Self.connection(locationID: 78, nativePassThrough: false, binds: false)
    await manager.handleHIDEvent(.connected(connection: sibling, ownership: .exclusive))
    #expect(await backend.releasedLocations() == [78])

    let native = Self.connection(locationID: 78, nativePassThrough: true)
    await manager.handleHIDEvent(.connected(connection: native, ownership: .unknown))

    let owners = await manager.connectedDeviceDescriptions().map(\.physicalOwnership)
    #expect(owners == [.nativeGamepad])
    #expect(await backend.reacquiredLocations().isEmpty)
    await manager.stop()
  }

  @Test
  func nativeDeviceStaysOutOfItsLocationStateAndSilencesSiblingInput() {
    var tracking = PhysicalHIDTrackingStateMachine()
    tracking.register(deviceID: 1, locationID: 76, syntheticProperty: nil, ownership: .exclusive)
    #expect(tracking.acceptsInput(deviceID: 1))
    tracking.register(deviceID: 2, locationID: 76, syntheticProperty: nil, nativePassThrough: true)
    #expect(tracking.ownership(locationID: 76) == .exclusive)
    #expect(tracking.acceptsInput(deviceID: 2))
    #expect(!tracking.acceptsInput(deviceID: 1))

    let nativeDisconnected = tracking.remove(deviceID: 2)
    #expect(nativeDisconnected)
    #expect(tracking.acceptsInput(deviceID: 1))
    #expect(tracking.acceptsInput(locationID: 76))
    let locationDisconnected = tracking.remove(deviceID: 1)
    #expect(locationDisconnected)
  }

  @Test
  func stopClearsPassThroughDevices() async {
    let manager = DeviceManager(
      dispatcher: LoggingOutputDispatcher(),
      hidManager: HIDManager(backend: ClaimRecordingHIDAccessBackend())
    )
    let connection = Self.connection(locationID: 72, nativePassThrough: true, binds: false)
    await manager.handleHIDEvent(.connected(connection: connection, ownership: .unknown))
    #expect(await manager.passThroughDeviceDescriptions().count == 1)

    await manager.stop()

    #expect(await manager.passThroughDeviceDescriptions().isEmpty)
  }

  @Test
  func hidAccessFailureClearsPassThroughDevices() async {
    let manager = DeviceManager(
      dispatcher: LoggingOutputDispatcher(),
      hidManager: HIDManager(backend: ClaimRecordingHIDAccessBackend())
    )
    let connection = Self.connection(locationID: 73, nativePassThrough: true, binds: false)
    await manager.handleHIDEvent(.connected(connection: connection, ownership: .unknown))
    #expect(await manager.passThroughDeviceDescriptions().count == 1)

    await manager.handleHIDEvent(.accessFailure(.ioReturn(kIOReturnNotPermitted)))

    #expect(await manager.passThroughDeviceDescriptions().isEmpty)
    await manager.stop()
  }

  @Test
  func passThroughDevicesRoundTripThroughTheStatusPayload() throws {
    let device = ApplicationServicePassThroughDevice(
      vendorID: 0x054C,
      productID: 0x0268,
      connection: "Bluetooth"
    )
    let payload = ApplicationServiceStatusPayload(
      inputMonitoring: "granted",
      accessibility: "granted",
      connectedDevices: [],
      passThroughDevices: [device]
    )
    let decoded = try JSONDecoder().decode(
      ApplicationServiceStatusPayload.self,
      from: JSONEncoder().encode(payload)
    )
    #expect(decoded.passThroughDevices == [device])
  }

  @Test
  func nativeGamepadIsNeverEligibleForPublication() {
    let decision = ControllerExposureDecision.decide(
      ownership: .nativeGamepad,
      intent: .profile(.generic)
    )
    #expect(decision.eligibility == .suppressedNativeHIDPassThrough)
  }

  static func dualShock4Bluetooth(locationID: UInt32) -> HIDDeviceConnection {
    HIDDeviceConnection(
      physicalDevice: PhysicalDevice(
        vendorID: 0x054C,
        productID: 0x09CC,
        productName: "Wireless Controller",
        transportProperty: "Bluetooth",
        physicalLocationIdentifier: locationID,
        interfaces: [gamepadHIDInterface(host: .bluetoothClassic)],
        nativePassThrough: true
      ),
      routingLocationID: locationID
    )
  }

  private static func connection(
    locationID: UInt32,
    nativePassThrough: Bool,
    binds: Bool = true
  ) -> HIDDeviceConnection {
    HIDDeviceConnection(
      physicalDevice: PhysicalDevice(
        vendorID: 0x1234,
        productID: 0x5678,
        productName: "Test pad",
        transportProperty: "USB",
        physicalLocationIdentifier: locationID,
        interfaces: [binds ? gamepadHIDInterface(host: .usb) : hostHIDInterface(.usb)],
        nativePassThrough: nativePassThrough
      ),
      routingLocationID: locationID
    )
  }
}
