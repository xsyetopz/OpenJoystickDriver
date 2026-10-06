import Foundation
import Testing

@testable import OpenJoystickDriverKit

/// Records GATT writes, and answers each command with `reply` when one is set.
final class RecordingSwitch2Writer: Switch2BluetoothLEWriter, @unchecked Sendable {
  private let lock = NSLock()
  private var commandLog: [[UInt8]] = []
  private var vibrationLog: [[UInt8]] = []
  var accepts = true
  var reply: (@Sendable ([UInt8]) -> Void)?

  var commands: [[UInt8]] { lock.withLock { commandLog } }
  var vibrations: [[UInt8]] { lock.withLock { vibrationLog } }

  func writeCommand(_ bytes: [UInt8]) -> Bool {
    lock.withLock { commandLog.append(bytes) }
    guard accepts else { return false }
    reply?(bytes)
    return true
  }

  func writeVibration(_ bytes: [UInt8]) -> Bool {
    lock.withLock { vibrationLog.append(bytes) }
    return accepts
  }
}

/// GATT framing from ndeadly's switch2_controller_research and joycon2cpp, not a hardware capture.
@Suite
struct Switch2BluetoothLEHubTests {
  static let peripheral = UUID()

  static func connectedHub(
    productID: UInt16 = 0x2069,
    writer: RecordingSwitch2Writer = RecordingSwitch2Writer()
  ) -> (Switch2BluetoothLEHub, UInt32) {
    let hub = Switch2BluetoothLEHub()
    hub.linkConnected(
      peripheralID: peripheral,
      productID: productID,
      productName: "Pro Controller",
      writer: writer
    )
    return (hub, hub.connectionSnapshots()[0].connection.routingLocationID)
  }

  @Test
  func advertisementsNameTheSwitch2ProductOnly() {
    let pro = Data([0x53, 0x05, 0x01, 0x00, 0x03, 0x7E, 0x05, 0x69, 0x20, 0x00])
    #expect(Switch2BluetoothLEProfile.productID(manufacturerData: pro) == 0x2069)
    var otherCompany = pro
    otherCompany[0] = 0x4C
    #expect(Switch2BluetoothLEProfile.productID(manufacturerData: otherCompany) == nil)
    var switch1 = pro
    switch1[7] = 0x09
    #expect(Switch2BluetoothLEProfile.productID(manufacturerData: switch1) == nil)
    #expect(Switch2BluetoothLEProfile.productID(manufacturerData: pro.prefix(8)) == nil)
  }

  @Test
  func vibrationCharacteristicsComeFromTheBundledRecords() {
    let expected: [UInt16: String] = [
      0x2066: "FA19B0FB-CD1F-46A7-84A1-BBB09E00C149",
      0x2067: "289326CB-A471-485D-A8F4-240C14F18241",
      0x2069: "CC483F51-9258-427D-A939-630C31F72B05",
      0x2073: "3F8FB670-AB25-45BF-B540-38C72834D064",
    ]
    for (productID, uuid) in expected {
      #expect(Switch2BluetoothLEProfile.vibrationUUID(productID: productID) == uuid)
    }
    #expect(Switch2BluetoothLEProfile.vibrationUUID(productID: 0x2009) == nil)
  }

  @Test
  func connectionsAreExclusiveBluetoothLEHIDConnectionsReplayedToEachStream() async {
    let (hub, location) = Self.connectedHub()
    #expect(location == Switch2BluetoothLEHub.firstRoutingLocationID)
    var events = hub.events().makeAsyncIterator()
    guard case .connected(let connection, let ownership) = await events.next() else {
      Issue.record("expected the replayed connection")
      return
    }
    #expect(ownership == .exclusive)
    #expect(connection.physicalDevice.vendorID == 0x057E)
    #expect(connection.physicalDevice.productID == 0x2069)
    #expect(connection.physicalDevice.interfaces?.first?.hostTransport == .bluetoothLE)

    hub.receivedInput(peripheralID: Self.peripheral, bytes: [UInt8](repeating: 0x11, count: 63))
    guard
      case .inputReport(let inputLocation, let connectionID, let reportID, let data) =
        await events.next()
    else {
      Issue.record("expected an input report")
      return
    }
    #expect(inputLocation == location && connectionID == connection.connectionID)
    #expect(reportID == 0x05 && data.count == 64 && data.first == 0x05 && data.last == 0x11)

    hub.linkDisconnected(peripheralID: Self.peripheral)
    guard case .disconnected(let gone) = await events.next() else {
      Issue.record("expected the disconnection")
      return
    }
    #expect(gone == connection)
    #expect(!hub.owns(locationID: location))
  }

  @Test
  func commandRepliesReadInChunksAndEndAtEachReply() async throws {
    let writer = RecordingSwitch2Writer()
    let (hub, location) = Self.connectedHub(writer: writer)
    let session = Switch2BluetoothLECommandSession(hub: hub, locationID: location)

    // A stale reply is dropped when the next command is written.
    hub.receivedReply(peripheralID: Self.peripheral, bytes: [0xEE])
    #expect(try await session.write(endpoint: 0x02, data: [0x02, 0x91, 0x01], timeout: 500) == 3)
    #expect(writer.commands == [[0x02, 0x91, 0x01]])
    let reply = [UInt8](0..<0x50)
    hub.receivedReply(peripheralID: Self.peripheral, bytes: reply)
    #expect(try await session.read(endpoint: 0x82, length: 64, timeout: 500) == Array(reply[..<64]))
    #expect(try await session.read(endpoint: 0x82, length: 16, timeout: 500) == Array(reply[64...]))

    // A reply that fills the read exactly is followed by an empty read, which ends the reply.
    _ = try await session.write(endpoint: 0x02, data: [0x03], timeout: 500)
    hub.receivedReply(peripheralID: Self.peripheral, bytes: [UInt8](repeating: 7, count: 64))
    #expect(try await session.read(endpoint: 0x82, length: 64, timeout: 500).count == 64)
    #expect(try await session.read(endpoint: 0x82, length: 16, timeout: 500).isEmpty)

    // A reply that arrives while the read waits resumes it.
    _ = try await session.write(endpoint: 0x02, data: [0x04], timeout: 500)
    let waiting = Task { try await session.read(endpoint: 0x82, length: 64, timeout: 2_000) }
    try await Task.sleep(nanoseconds: 20_000_000)
    hub.receivedReply(peripheralID: Self.peripheral, bytes: [1, 2, 3])
    #expect(try await waiting.value == [1, 2, 3])

    _ = try await session.write(endpoint: 0x02, data: [0x05], timeout: 500)
    await #expect(throws: USBTransportError.timeout) {
      try await session.read(endpoint: 0x82, length: 64, timeout: 10)
    }
    writer.accepts = false
    await #expect(throws: USBTransportError.inputOutput) {
      try await session.write(endpoint: 0x02, data: [0], timeout: 500)
    }
    await #expect(throws: USBTransportError.notSupported) {
      try await session.read(endpoint: 0x02, length: 64, timeout: 500)
    }
    hub.linkDisconnected(peripheralID: Self.peripheral)
    await #expect(throws: USBTransportError.disconnected) {
      try await session.write(endpoint: 0x02, data: [0], timeout: 500)
    }
  }

  @Test
  func disconnectEndsAWaitingRead() async throws {
    let (hub, location) = Self.connectedHub()
    let session = Switch2BluetoothLECommandSession(hub: hub, locationID: location)
    let waiting = Task { try await session.read(endpoint: 0x82, length: 64, timeout: 5_000) }
    try await Task.sleep(nanoseconds: 20_000_000)
    hub.linkDisconnected(peripheralID: Self.peripheral)
    await #expect(throws: USBTransportError.disconnected) { try await waiting.value }
  }

  @Test
  func vibrationKeepsTheUSBLayoutWithAZeroReportIDSlotIn42Bytes() {
    let writer = RecordingSwitch2Writer()
    let (hub, location) = Self.connectedHub(writer: writer)
    let driver = Switch2Driver(layout: .pro, link: .bluetoothLE)
    let full = RumbleIntensities(leftMain: .max, rightMain: .max)
    let report = driver.encoded(.setRumble(full, duration: .milliseconds(100))).onlyReport

    #expect(hub.setOutputReport(locationID: location, report: report).succeeded)
    let sent = try? #require(writer.vibrations.first)
    #expect(sent?.count == 42 && sent?.first == 0)
    #expect(sent.map { Array($0[1...]) } == Array(report.bytes[1..<42]))
    #expect(hub.setOutputReport(locationID: location &+ 1, report: report).succeeded == false)
  }

  @Test
  func compositeRoutingSendsHubLocationsToGATTAndTheRestToIOHID() async throws {
    let writer = RecordingSwitch2Writer()
    let (hub, location) = Self.connectedHub(writer: writer)
    let primary = ScriptedHIDAccessBackend()
    await primary.enableOutputReports()
    let composite = BluetoothLECompositeHIDBackend(primary: primary, hub: hub)
    let report = PhysicalHIDOutputReport(reportID: 0x02, bytes: [UInt8](repeating: 2, count: 64))

    #expect(await composite.setOutputReport(locationID: location, report: report).succeeded)
    #expect(await composite.setOutputReport(locationID: 0x0021_0000, report: report).succeeded)
    #expect(writer.vibrations.count == 1)
    #expect(await primary.recordedOutputReports() == [report])
    #expect(await composite.releaseInputClaim(locationID: location) == .released)
    #expect(
      await composite.currentConnectionSnapshots()?.map(\.connection.routingLocationID) == [
        location
      ]
    )

    let provider = BluetoothLECompositeUSBTransportProvider(base: nil, hub: hub)
    let device = USBTransportDevice(
      route: .ioUSBHost,
      serviceID: 0,
      vendorID: 0x057E,
      productID: 0x2069,
      locationID: location
    )
    let session = try await provider.open(device, options: USBTransportOpenOptions())
    try await session.write(endpoint: 0x02, data: [0x0C], timeout: 500)
    #expect(writer.commands == [[0x0C]])
    await #expect(throws: USBTransportError.notFound) {
      _ = try await provider.open(
        USBTransportDevice(
          route: .ioUSBHost,
          serviceID: 0,
          vendorID: 0x057E,
          productID: 0x2069,
          locationID: 0x0021_0000
        ),
        options: USBTransportOpenOptions()
      )
    }
  }

  /// End to end over the manager: the catalog binds the GATT connection to the Bluetooth LE
  /// driver, startup commands reach the command characteristic, and input reaches the dispatcher.
  @Test
  func managerDrivesABluetoothLEProController() async throws {
    let writer = RecordingSwitch2Writer()
    let (hub, location) = Self.connectedHub(writer: writer)
    writer.reply = { command in
      var reply = [UInt8](repeating: 0, count: 0x50)
      reply[0] = command[0]
      reply[1] = 0x01
      reply[3] = 0x01
      hub.receivedReply(peripheralID: Self.peripheral, bytes: reply)
    }
    let recorder = HIDRoleEventRecorder()
    let manager = DeviceManager(
      dispatcher: recorder,
      hidManager: HIDManager(
        backend: BluetoothLECompositeHIDBackend(primary: ScriptedHIDAccessBackend(), hub: hub)
      ),
      usbTransportProvider: BluetoothLECompositeUSBTransportProvider(base: nil, hub: hub)
    )
    await manager.markStartedForTest()
    let connection = hub.connectionSnapshots()[0].connection
    await manager.handleHIDEvent(.connected(connection: connection, ownership: .exclusive))

    let identifier = DeviceIdentifier(vendorID: 0x057E, productID: 0x2069, locationID: location)
    #expect(Array(await manager.pipelines.keys) == [identifier])
    #expect(await waitUntil { writer.commands.count >= 9 })
    #expect(writer.commands.allSatisfy { $0.count > 2 && $0[2] == 0x01 })

    var input = [UInt8](repeating: 0, count: 63)
    input[5 - 1] = 0x04
    await manager.handleHIDEvent(
      .inputReport(
        locationID: location,
        connectionID: connection.connectionID,
        reportID: 0x05,
        data: Data([0x05] + input)
      )
    )
    #expect(await waitUntil { recorder.pressed(from: identifier).contains(.faceSouth) })
    await manager.stop()
  }

  private func waitUntil(condition: @escaping @Sendable () async -> Bool) async -> Bool {
    let deadline = ContinuousClock.now.advanced(by: .seconds(10))
    while ContinuousClock.now < deadline {
      if await condition() { return true }
      try? await Task.sleep(for: .milliseconds(1))
    }
    return await condition()
  }
}
