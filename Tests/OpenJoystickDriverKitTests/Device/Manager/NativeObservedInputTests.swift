import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct NativeObservedInputTests {
  @Test
  func nativeSixaxisSendsOnlyItsPlayerLED() async throws {
    let backend = ScriptedHIDAccessBackend()
    await backend.enableOutputReports()
    await backend.enableFeatureReports()
    let manager = DeviceManager(
      dispatcher: LoggingOutputDispatcher(),
      hidManager: HIDManager(backend: backend)
    )
    await manager.markStartedForTest()
    let connection = Self.connection(0x054C, 0x0268, locationID: 90, native: true)
    await backend.setConnectionSnapshots([
      HIDDeviceConnectionSnapshot(connection: connection, ownership: .unknown)
    ])

    await manager.handleHIDEvent(.connected(connection: connection, ownership: .unknown))

    let device = try #require(await manager.connectedDeviceDescriptions().first)
    #expect(device.physicalOutputCapabilities.lightingFeatures == [.playerIndicator])
    #expect(device.physicalOutputCapabilities.rumbleMotors.isEmpty)
    let identifier = try #require(await manager.pipelines.keys.first)
    #expect(
      !(await manager.sendManualRumble(
        for: identifier,
        left: 255,
        right: 255,
        lt: 0,
        rt: 0,
        durationMs: 50
      ))
    )
    // A USB Sixaxis ignores its LED report until it streams input, so player 1 follows the first
    // input report, once.
    #expect(await backend.recordedOutputReports().isEmpty)
    var input = [UInt8](repeating: 0, count: 49)
    input[0] = 0x01
    input.replaceSubrange(6...9, with: [0x80, 0x80, 0x80, 0x80])
    for _ in 0..<2 {
      await manager.routeHIDInputReport(
        locationID: connection.routingLocationID,
        connectionID: connection.connectionID,
        data: Data(input)
      )
    }
    let expected = SixaxisDriver().encoded(.setPlayerIndicator(.player1)).onlyReport
    #expect(await backend.recordedOutputReports() == [expected])
    // Only the exact-connection path can reach a never-seized native device.
    #expect(await backend.recordedOutputReportConnectionIDs() == [connection.connectionID])
    #expect(expected.reportID == 0x01 && expected.bytes.count == 49 && expected.bytes[10] == 0x02)
    #expect(expected.bytes[3] == 0 && expected.bytes[5] == 0)
    #expect(await backend.recordedFeatureReports().isEmpty)
    // A USB Sixaxis sends no input until the host reads feature 0xF2; macOS does not.
    #expect(await backend.recordedFeatureReadReportIDs() == [0xF2, 0xF5])
    // A never-seized native device is reachable only through its exact connection.
    let target: UUID? = connection.connectionID
    #expect(await backend.recordedFeatureReadTargets() == [target, target])
    await manager.stop()
  }

  @Test
  func nativeSixaxisControllersOfOneModelTakeDistinctReusablePlayerSlots() async throws {
    let backend = ScriptedHIDAccessBackend()
    await backend.enableOutputReports()
    await backend.enableFeatureReports()
    let manager = DeviceManager(
      dispatcher: LoggingOutputDispatcher(),
      hidManager: HIDManager(backend: backend)
    )
    await manager.markStartedForTest()
    var input = [UInt8](repeating: 0, count: 49)
    input[0] = 0x01
    input.replaceSubrange(6...9, with: [0x80, 0x80, 0x80, 0x80])
    func ledByte(afterConnecting connection: HIDDeviceConnection) async -> UInt8? {
      await manager.handleHIDEvent(.connected(connection: connection, ownership: .unknown))
      await manager.routeHIDInputReport(
        locationID: connection.routingLocationID,
        connectionID: connection.connectionID,
        data: Data(input)
      )
      return await backend.recordedOutputReports().last?.bytes[10]
    }
    let first = Self.connection(0x054C, 0x0268, locationID: 90, native: true)
    let second = Self.connection(0x054C, 0x0268, locationID: 95, native: true)
    let third = Self.connection(0x054C, 0x0268, locationID: 96, native: true)
    await backend.setConnectionSnapshots(
      [first, second, third].map {
        HIDDeviceConnectionSnapshot(connection: $0, ownership: .unknown)
      }
    )

    #expect(await ledByte(afterConnecting: first) == 0x02)
    #expect(await ledByte(afterConnecting: second) == 0x04)
    await manager.handleHIDEvent(.disconnected(connection: first))
    #expect(await ledByte(afterConnecting: third) == 0x02)
    await manager.stop()
  }

  @Test
  func nativePadDispatchesOnlyWhileInputIsDemanded() async throws {
    let dispatcher = NativeEventRecorder()
    dispatcher.demandsInput = false
    let manager = DeviceManager(
      dispatcher: dispatcher,
      hidManager: HIDManager(backend: ClaimRecordingHIDAccessBackend())
    )
    let connection = NativePassThroughTests.dualShock4Bluetooth(locationID: 91)
    await manager.handleHIDEvent(.connected(connection: connection, ownership: .unknown))
    try #require(await manager.connectedDeviceDescriptions().count == 1)

    await Self.sendDS4Reports(to: manager, locationID: 91, buttons: [0x08, 0x28], from: 1)
    #expect(dispatcher.states.isEmpty)

    dispatcher.demandsInput = true
    await Self.sendDS4Reports(to: manager, locationID: 91, buttons: [0x08, 0x48], from: 3)
    #expect(dispatcher.states.contains { $0.pressed.contains(.faceEast) })
    await manager.stop()
  }

  @Test
  func elementValuesAreRoutedOnlyToADriverThatParsesThem() async {
    let backend = ClaimRecordingHIDAccessBackend()
    let manager = DeviceManager(
      dispatcher: LoggingOutputDispatcher(),
      hidManager: HIDManager(backend: backend)
    )
    let generic = Self.connection(0x1234, 0x5678, locationID: 92, native: true)
    await manager.handleHIDEvent(.connected(connection: generic, ownership: .unknown))
    let ds4 = NativePassThroughTests.dualShock4Bluetooth(locationID: 93)
    await manager.handleHIDEvent(.connected(connection: ds4, ownership: .unknown))

    #expect(await manager.connectedDeviceDescriptions().count == 2)
    #expect(await backend.elementValueLocations() == [92])
    await manager.stop()
  }

  @Test
  func siblingEntriesDoNotKeepALocationNative() async {
    let backend = ClaimRecordingHIDAccessBackend()
    let manager = DeviceManager(
      dispatcher: LoggingOutputDispatcher(),
      hidManager: HIDManager(backend: backend)
    )
    let native = Self.connection(0x1234, 0x5678, locationID: 94, native: true)
    let sibling = Self.connection(0x1234, 0x5679, locationID: 94, native: false)
    await manager.handleHIDEvent(.connected(connection: native, ownership: .unknown))
    await manager.handleHIDEvent(.connected(connection: sibling, ownership: .exclusive))
    #expect(await manager.passThroughDeviceDescriptions().count == 1)

    await manager.handleHIDEvent(.disconnected(connection: native))
    let later = Self.connection(0x1234, 0x5678, locationID: 94, native: false)
    await manager.handleHIDEvent(.connected(connection: later, ownership: .exclusive))

    let owners = await manager.connectedDeviceDescriptions().map(\.physicalOwnership)
    #expect(owners == [.exclusiveHID])
    #expect(await manager.passThroughDeviceDescriptions().count == 1)
    await manager.stop()
  }

  @Test
  func locationZeroIsNeverTreatedAsANativeController() async {
    let manager = DeviceManager(
      dispatcher: LoggingOutputDispatcher(),
      hidManager: HIDManager(backend: ClaimRecordingHIDAccessBackend())
    )
    let native = Self.connection(0x1234, 0x5678, locationID: 0, native: true)
    let other = Self.connection(0x1234, 0x5679, locationID: 0, native: false)
    await manager.handleHIDEvent(.connected(connection: native, ownership: .unknown))
    await manager.handleHIDEvent(.connected(connection: other, ownership: .exclusive))

    #expect(await manager.passThroughDeviceDescriptions().isEmpty)

    var tracking = PhysicalHIDTrackingStateMachine()
    tracking.register(deviceID: 1, locationID: 0, syntheticProperty: nil, nativePassThrough: true)
    tracking.register(deviceID: 2, locationID: 0, syntheticProperty: nil, ownership: .exclusive)
    #expect(!tracking.hasNativeDevice(locationID: 0))
    #expect(tracking.acceptsInput(deviceID: 2))
    await manager.stop()
  }

  private static func sendDS4Reports(
    to manager: DeviceManager,
    locationID: UInt32,
    buttons: [UInt8],
    from timestamp: UInt16
  ) async {
    for (offset, value) in buttons.enumerated() {
      let report = makeDS4BluetoothReport(
        buttons0: value,
        sensorTimestamp: timestamp + UInt16(offset)
      )
      await manager.handleHIDEvent(
        .inputReport(locationID: locationID, connectionID: UUID(), reportID: 0x11, data: report)
      )
    }
  }

  private static func connection(
    _ vendorID: UInt16,
    _ productID: UInt16,
    locationID: UInt32,
    native: Bool
  ) -> HIDDeviceConnection {
    HIDDeviceConnection(
      physicalDevice: PhysicalDevice(
        vendorID: vendorID,
        productID: productID,
        productName: "Test pad",
        transportProperty: "USB",
        physicalLocationIdentifier: locationID,
        interfaces: [gamepadHIDInterface(host: .usb)],
        nativePassThrough: native
      ),
      routingLocationID: locationID
    )
  }
}
