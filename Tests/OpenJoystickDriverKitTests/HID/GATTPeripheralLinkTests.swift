import Foundation
import Testing

@testable import OpenJoystickDriverKit

/// A peripheral that records writes by characteristic and accepts them while connected.
final class MockGATTPeripheral: GATTPeripheral, @unchecked Sendable {
  let identifier = UUID()
  private let lock = NSLock()
  private var writeLog: [(characteristic: String, bytes: [UInt8])] = []
  private var isConnected = true

  var writes: [(characteristic: String, bytes: [UInt8])] { lock.withLock { writeLog } }

  func disconnect() { lock.withLock { isConnected = false } }

  func writeWithoutResponse(_ bytes: [UInt8], to characteristic: String) -> Bool {
    lock.withLock {
      guard isConnected else { return false }
      writeLog.append((characteristic, bytes))
      return true
    }
  }
}

@Suite
struct GATTPeripheralLinkTests {
  private static let proProductID: UInt16 = 0x2069
  private static let proVibrationUUID = "CC483F51-9258-427D-A939-630C31F72B05"

  private static func makeLink() throws -> (
    GATTPeripheralLink, MockGATTPeripheral, Switch2BluetoothLEHub
  ) {
    let peripheral = MockGATTPeripheral()
    let hub = Switch2BluetoothLEHub()
    let link = try #require(
      GATTPeripheralLink(
        peripheral: peripheral,
        productID: proProductID,
        productName: "Pro Controller",
        hub: hub
      )
    )
    return (link, peripheral, hub)
  }

  @Test
  func mockPeripheralDeliversInputFramesThroughLink() async throws {
    let (link, peripheral, hub) = try Self.makeLink()
    var events = hub.events().makeAsyncIterator()
    link.admit()

    guard case .connected(let connection, let ownership) = await events.next() else {
      Issue.record("expected the admitted connection")
      return
    }
    #expect(ownership == .exclusive)
    #expect(connection.routingAddress == .gattPeripheral(peripheral.identifier))
    #expect(connection.accessBackend == .gatt)
    #expect(connection.physicalDevice.interfaces?.first?.accessBackend == .gatt)

    let fills: [UInt8] = [0x11, 0x22]
    for fill in fills {
      link.notified(
        characteristic: Switch2BluetoothLEProfile.inputUUID.lowercased(),
        value: [UInt8](repeating: fill, count: 63)
      )
    }
    for fill in fills {
      guard
        case .inputReport(let address, let connectionID, let reportID, let data) =
          await events.next()
      else {
        Issue.record("expected an input frame")
        return
      }
      #expect(address == .gattPeripheral(peripheral.identifier))
      #expect(connectionID == connection.connectionID)
      #expect(reportID == 0x05 && data.count == 64 && data.last == fill)
    }

    link.disconnected()
    guard case .disconnected(let gone) = await events.next() else {
      Issue.record("expected the disconnection")
      return
    }
    #expect(gone == connection)
  }

  @Test
  func commandsRepliesAndVibrationUseTheirCharacteristics() async throws {
    let (link, peripheral, hub) = try Self.makeLink()
    link.admit()
    let session = Switch2BluetoothLECommandSession(hub: hub, peripheralID: peripheral.identifier)

    #expect(try session.write(endpoint: 0x02, data: [0x02, 0x91], timeout: 500) == 2)
    link.notified(characteristic: Switch2BluetoothLEProfile.commandReplyUUID, value: [9, 8, 7])
    #expect(try await session.read(endpoint: 0x82, length: 64, timeout: 500) == [9, 8, 7])

    let report = PhysicalHIDOutputReport(reportID: 0, bytes: [0x01, 0x02])
    guard case .success = hub.setOutputReport(peripheralID: peripheral.identifier, report: report)
    else {
      Issue.record("expected the vibration write to succeed")
      return
    }
    let writes = peripheral.writes
    #expect(
      writes.map(\.characteristic)
        == [Switch2BluetoothLEProfile.commandUUID, Self.proVibrationUUID]
    )
    #expect(writes[0].bytes == [0x02, 0x91])
    #expect(writes[1].bytes.count == Switch2BluetoothLEHub.vibrationReportLength)

    peripheral.disconnect()
    #expect(throws: USBTransportError.inputOutput) {
      try session.write(endpoint: 0x02, data: [0x03], timeout: 500)
    }
  }

  @Test
  func admittedLinkDoesNotKeepHubAlive() throws {
    weak var weakHub: Switch2BluetoothLEHub?
    var link: GATTPeripheralLink?
    do {
      let (admitted, _, hub) = try Self.makeLink()
      admitted.admit()
      weakHub = hub
      link = admitted
    }
    #expect(weakHub == nil)
    link?.notified(characteristic: Switch2BluetoothLEProfile.inputUUID, value: [1])
    link?.disconnected()
    link = nil
  }

  @Test
  func notificationsFromOtherCharacteristicsAreIgnored() async throws {
    let (link, _, hub) = try Self.makeLink()
    var events = hub.events().makeAsyncIterator()
    link.admit()
    _ = await events.next()
    link.notified(characteristic: "0000180F-0000-1000-8000-00805F9B34FB", value: [1])
    link.notified(characteristic: Switch2BluetoothLEProfile.inputUUID, value: [2])
    guard case .inputReport(_, _, _, let data) = await events.next() else {
      Issue.record("expected only the input frame")
      return
    }
    #expect(data == Data([0x05, 2]))
  }

  @Test
  func productWithoutVibrationCharacteristicHasNoLink() {
    let link = GATTPeripheralLink(
      peripheral: MockGATTPeripheral(),
      productID: 0x2009,
      productName: nil,
      hub: Switch2BluetoothLEHub()
    )
    #expect(link == nil)
  }

  @Test
  func onlyUSBAccessBackendsUseRawUSB() {
    #expect(DeviceAccessBackend.gatt.rawValue == "GATT")
    #expect(!DeviceAccessBackend.gatt.usesRawUSB)
    #expect(!DeviceAccessBackend.hid.usesRawUSB)
    #expect(DeviceAccessBackend.rawUSB.usesRawUSB && DeviceAccessBackend.usbExtension.usesRawUSB)
  }
}
