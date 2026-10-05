import Foundation
import ProtocolPacketFixtures
import Testing

@testable import OpenJoystickDriverKit

// HID step ordering through DeviceManager, recorded by `ScriptedHIDAccessBackend`. The recorder
// keeps output and feature reports in separate lists and neither records nor answers feature
// reads, so each list's order is pinned but interleaving across the lists is not observable.
extension DriverLifecycleCharacterizationTests {
  struct HIDStartupRecording {
    let backend: ScriptedHIDAccessBackend
    let manager: DeviceManager
    let connection: HIDDeviceConnection
  }

  /// Connects one catalog HID controller over `transport` and runs the startup path to its end.
  /// `interface` defaults to a descriptor-contract gamepad interface.
  func startHIDController(
    _ subject: Subject,
    transport: String,
    locationID: UInt32,
    interface: PhysicalInterfaceSignature? = nil
  ) async -> HIDStartupRecording {
    let backend = ScriptedHIDAccessBackend()
    await backend.enableOutputReports()
    await backend.enableFeatureReports()
    let connection = HIDDeviceConnection(
      physicalDevice: PhysicalDevice(
        vendorID: subject.identifier.controllerIdentity.vendorID,
        productID: subject.identifier.controllerIdentity.productID,
        productName: "Characterized controller",
        transportProperty: transport,
        physicalLocationIdentifier: locationID,
        interfaces: [interface ?? gamepadHIDInterface(host: subject.host)]
      ),
      routingLocationID: locationID
    )
    await backend.setConnectionSnapshots([
      HIDDeviceConnectionSnapshot(connection: connection, ownership: .exclusive)
    ])
    let manager = DeviceManager(
      dispatcher: LoggingOutputDispatcher(),
      hidManager: HIDManager(backend: backend)
    )
    await manager.markStartedForTest()
    await manager.handleHIDEvent(.connected(connection: connection, ownership: .exclusive))
    return HIDStartupRecording(backend: backend, manager: manager, connection: connection)
  }

  func recordedSteps(_ recording: HIDStartupRecording) async -> [String] {
    let outputs = await recording.backend.recordedOutputReports()
    let features = await recording.backend.recordedFeatureReports()
    return ["outputs=\(outputs.count)"] + outputs.flatMap(render) + ["features=\(features.count)"]
      + features.flatMap(render)
  }

  /// Keep-alive writes (GameSir sends one every 500 ms) are wall-clock paced; stop them so a
  /// slow run cannot interleave one into a recorded transcript.
  func stopKeepAlive(_ recording: HIDStartupRecording) async {
    for task in await recording.manager.hidPeriodicOutputTasks.values {
      task.cancel()
      await task.value
    }
  }

  func dualShock4BluetoothStartupSteps() async -> [String] {
    let recording = await startHIDController(
      Self.dualShock4Bluetooth,
      transport: "Bluetooth",
      locationID: 201
    )
    let steps = await recordedSteps(recording)
    await recording.manager.stop()
    return steps
  }

  func sixaxisBluetoothStartupSteps() async -> [String] {
    let recording = await startHIDController(
      Self.sixaxisBluetooth,
      transport: "Bluetooth",
      locationID: 202
    )
    let steps = await recordedSteps(recording)
    await recording.manager.stop()
    return steps
  }

  /// Startup includes the three 200 ms recovery rounds; the controller answers no reads.
  func switchBluetoothStartupSteps() async -> [String] {
    let recording = await startHIDController(
      Self.switchBluetooth,
      transport: "Bluetooth",
      locationID: 203
    )
    let steps = await recordedSteps(recording)
    await recording.manager.stop()
    return steps
  }

  /// Startup, then the presence path after the dongle reports a connected controller, on dongle
  /// slot 1 as `hid-steam.c` lays it out (a Steam role needs its feature report).
  func steamDonglePresenceSteps() async -> [String] {
    let recording = await startHIDController(
      Self.steamDongle,
      transport: "USB",
      locationID: 204,
      interface: steamHIDInterface(number: 1)
    )
    let startup = await recordedSteps(recording)
    await recording.manager.handleHIDEvent(
      .inputReport(
        locationID: 204,
        connectionID: recording.connection.connectionID,
        reportID: 1,
        data: ProtocolPacketFixtures.Steam.wirelessReport(status: 0x02)
      )
    )
    let connected = await recordedSteps(recording)
    await recording.manager.stop()
    return ["startup"] + startup + ["connected"] + connected
  }

  /// Stops the 500 ms heartbeat before reading, so the periodic output is not in the list.
  func gameSirEnhancedHIDStartupSteps() async -> [String] {
    let recording = await startHIDController(
      Self.gameSirEnhancedHID,
      transport: "USB",
      locationID: 205
    )
    await stopKeepAlive(recording)
    let steps = await recordedSteps(recording)
    await recording.manager.stop()
    return steps
  }

  @Test
  func dualShock4BluetoothStartupStepOrder() async {
    #expect(
      await dualShock4BluetoothStartupSteps() == [
        "outputs=1", "  id=0x11 n=78",
        "    11c4000100000000000000000000000000000000000000000000000000000000",
        "    0000000000000000000000000000000000000000000000000000000000000000",
        "    000000000000000000003789fe89", "features=0",
      ]
    )
  }

  @Test
  func sixaxisBluetoothStartupStepOrder() async {
    #expect(
      await sixaxisBluetoothStartupSteps() == [
        "outputs=0", "features=1", "  id=0xf4 n=5", "    f442030000",
      ]
    )
  }

  /// The record limits the Bluetooth enable report to Bluetooth, so USB startup writes nothing.
  @Test
  func sixaxisUSBStartupWritesNothing() async {
    let recording = await startHIDController(Self.sixaxisUSB, transport: "USB", locationID: 206)
    let steps = await recordedSteps(recording)
    await recording.manager.stop()
    #expect(steps == ["outputs=0", "features=0"])
  }

  @Test
  func switchBluetoothStartupStepOrder() async {
    #expect(
      await switchBluetoothStartupSteps() == [
        "outputs=9", "  id=0x01 n=12", "    010000014040000140400330", "  id=0x01 n=12",
        "    010100014040000140404001", "  id=0x01 n=12", "    010200014040000140404801",
        "  id=0x01 n=16", "    01030001404000014040102060000018", "  id=0x01 n=16",
        "    01040001404000014040102680000014", "  id=0x01 n=16",
        "    01050001404000014040102060000018", "  id=0x01 n=16",
        "    01060001404000014040102680000014", "  id=0x01 n=16",
        "    01070001404000014040102060000018", "  id=0x01 n=16",
        "    01080001404000014040102680000014", "features=0",
      ]
    )
  }

  @Test
  func steamDonglePresenceStepOrder() async {
    #expect(
      await steamDonglePresenceSteps() == [
        "startup", "outputs=0", "features=1", "  id=0x00 n=64",
        "    b400000000000000000000000000000000000000000000000000000000000000",
        "    0000000000000000000000000000000000000000000000000000000000000000", "connected",
        "outputs=0", "features=3", "  id=0x00 n=64",
        "    b400000000000000000000000000000000000000000000000000000000000000",
        "    0000000000000000000000000000000000000000000000000000000000000000", "  id=0x00 n=64",
        "    8100000000000000000000000000000000000000000000000000000000000000",
        "    0000000000000000000000000000000000000000000000000000000000000000", "  id=0x00 n=64",
        "    8709070700080700301800000000000000000000000000000000000000000000",
        "    0000000000000000000000000000000000000000000000000000000000000000",
      ]
    )
  }

  @Test
  func gameSirEnhancedHIDStartupStepOrder() async {
    #expect(
      await gameSirEnhancedHIDStartupSteps() == [
        "outputs=2", "  id=0x0f n=64",
        "    0ff2000000000000000000000000000000000000000000000000000000000000",
        "    0000000000000000000000000000000000000000000000000000000000000000", "  id=0x0f n=64",
        "    0f04200000010000000000000000000000000000000000000000000000000000",
        "    0000000000000000000000000000000000000000000000000000000000000000", "features=0",
      ]
    )
  }
}
