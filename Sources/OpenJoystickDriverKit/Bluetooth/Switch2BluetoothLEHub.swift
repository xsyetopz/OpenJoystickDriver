import Foundation
import IOKit
import IOKit.hid

/// GATT writes to one connected Switch 2 controller. Each returns false when the link cannot send.
public protocol Switch2BluetoothLEWriter: Sendable {
  /// Writes one command to the command characteristic, without response.
  func writeCommand(_ bytes: [UInt8]) -> Bool
  /// Writes one vibration report to the model's vibration characteristic, without response.
  func writeVibration(_ bytes: [UInt8]) -> Bool
}

/// Switch 2 GATT identifiers and advertisement format, from ndeadly's switch2_controller_research
/// and joycon2cpp.
public enum Switch2BluetoothLEProfile {
  public static let serviceUUID = "AB7DE9BE-89FE-49AD-828F-118F09DF7FD0"
  public static let inputUUID = "AB7DE9BE-89FE-49AD-828F-118F09DF7FD2"
  public static let commandUUID = "649D4AC9-8EB7-4E6C-AF44-1EA54FE5F005"
  public static let commandReplyUUID = "C765A961-D9D8-4D36-A20A-5315B111836A"

  /// The vibration characteristic of each model, keyed by product ID.
  public static let vibrationUUIDs: [UInt16: String] = [
    0x2066: "FA19B0FB-CD1F-46A7-84A1-BBB09E00C149", 0x2067: "289326CB-A471-485D-A8F4-240C14F18241",
    0x2069: "CC483F51-9258-427D-A939-630C31F72B05", 0x2073: "3F8FB670-AB25-45BF-B540-38C72834D064",
  ]

  static let nintendoCompanyID: UInt16 = 0x0553
  static let nintendoVendorID: UInt16 = 0x057E

  /// The product ID of a Switch 2 controller advertisement, or nil for any other advertisement.
  /// `manufacturerData` starts with the little-endian company ID, as CoreBluetooth delivers it.
  public static func productID(manufacturerData data: Data) -> UInt16? {
    let bytes = [UInt8](data)
    guard bytes.count >= 9 else { return nil }
    func word(_ offset: Int) -> UInt16 { UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8 }
    guard word(0) == nintendoCompanyID, word(5) == nintendoVendorID else { return nil }
    let productID = word(7)
    return vibrationUUIDs[productID] == nil ? nil : productID
  }
}

/// Presents connected Switch 2 Bluetooth LE controllers as HID connections, and carries their
/// command channel and vibration output over GATT.
///
/// The CoreBluetooth central calls the `link` and `received` methods on its serial queue, so input
/// keeps its order. Each connection gets a routing location above
/// ``firstRoutingLocationID``, a range that IOHID locations are assumed not to use.
public final class Switch2BluetoothLEHub: @unchecked Sendable {
  public static let firstRoutingLocationID: UInt32 = 0xB1E0_0000
  /// The console's vibration report length on every model.
  static let vibrationReportLength = 0x2A

  private struct ReplyWaiter {
    let token: UInt64
    let continuation: CheckedContinuation<[UInt8]?, Never>
  }

  private struct Link {
    let peripheralID: UUID
    let connection: HIDDeviceConnection
    let writer: any Switch2BluetoothLEWriter
    var replies: [[UInt8]] = []
    /// The unread rest of the reply being read, empty after a reply read to its end.
    var current: [UInt8]?
    var waiter: ReplyWaiter?
  }

  private let lock = NSLock()
  private var links: [UInt32: Link] = [:]
  private var locationByPeripheral: [UUID: UInt32] = [:]
  private var nextLocationOffset: UInt32 = 0
  private var nextWaiterToken: UInt64 = 0
  private var continuation: AsyncStream<HIDDeviceEvent>.Continuation?
  private var streamGeneration: UInt64 = 0

  public init() {}

  // MARK: - CoreBluetooth central input

  /// Admits a controller whose input and command-reply notifications are enabled.
  public func linkConnected(
    peripheralID: UUID,
    productID: UInt16,
    productName: String?,
    writer: any Switch2BluetoothLEWriter
  ) {
    // A reconnect without a disconnect callback ends the earlier connection first.
    linkDisconnected(peripheralID: peripheralID)
    let (event, stream): (HIDDeviceEvent, AsyncStream<HIDDeviceEvent>.Continuation?) = lock.withLock
    {
      let location = Self.firstRoutingLocationID &+ nextLocationOffset
      nextLocationOffset &+= 1
      let device = PhysicalDevice(
        vendorID: Switch2BluetoothLEProfile.nintendoVendorID,
        productID: productID,
        productName: productName,
        transportProperty: kIOHIDTransportBluetoothLowEnergyValue,
        interfaces: [
          PhysicalInterfaceSignature(
            interfaceClass: 0x03,
            hostTransport: .bluetoothLE,
            physicalTransport: .bluetoothLE,
            accessBackend: .ioHID
          )
        ]
      )
      let connection = HIDDeviceConnection(physicalDevice: device, routingLocationID: location)
      links[location] = Link(peripheralID: peripheralID, connection: connection, writer: writer)
      locationByPeripheral[peripheralID] = location
      return (.connected(connection: connection, ownership: .exclusive), continuation)
    }
    stream?.yield(event)
  }

  /// Delivers one input notification: report 0x05 without its ID byte.
  public func receivedInput(peripheralID: UUID, bytes: [UInt8]) {
    let target = lock.withLock {
      () -> (HIDDeviceConnection, AsyncStream<HIDDeviceEvent>.Continuation)? in
      guard let location = locationByPeripheral[peripheralID], let link = links[location],
        let continuation
      else { return nil }
      return (link.connection, continuation)
    }
    guard let (connection, stream) = target else { return }
    stream.yield(
      .inputReport(
        locationID: connection.routingLocationID,
        connectionID: connection.connectionID,
        reportID: 0x05,
        data: Data([0x05] + bytes)
      )
    )
  }

  /// Delivers one command-reply notification.
  public func receivedReply(peripheralID: UUID, bytes: [UInt8]) {
    let waiter = lock.withLock { () -> ReplyWaiter? in
      guard let location = locationByPeripheral[peripheralID] else { return nil }
      guard let waiter = links[location]?.waiter else {
        links[location]?.replies.append(bytes)
        return nil
      }
      links[location]?.waiter = nil
      return waiter
    }
    waiter?.continuation.resume(returning: bytes)
  }

  public func linkDisconnected(peripheralID: UUID) {
    let removed = lock.withLock { () -> (Link, AsyncStream<HIDDeviceEvent>.Continuation?)? in
      guard let location = locationByPeripheral.removeValue(forKey: peripheralID),
        let link = links.removeValue(forKey: location)
      else { return nil }
      return (link, continuation)
    }
    guard let (link, stream) = removed else { return }
    link.waiter?.continuation.resume(returning: nil)
    stream?.yield(.disconnected(connection: link.connection))
  }

  // MARK: - HID backend

  func owns(locationID: UInt32) -> Bool { lock.withLock { links[locationID] != nil } }

  /// Starts a new event stream, ending the previous one, and replays the connected controllers.
  func events() -> AsyncStream<HIDDeviceEvent> {
    let (stream, newContinuation) = AsyncStream.makeStream(of: HIDDeviceEvent.self)
    let (previous, connections, generation) = lock.withLock {
      let previous = continuation
      continuation = newContinuation
      streamGeneration &+= 1
      let connections = links.values.map(\.connection).sorted {
        $0.routingLocationID < $1.routingLocationID
      }
      return (previous, connections, streamGeneration)
    }
    previous?.finish()
    newContinuation.onTermination = { [weak self] _ in
      guard let self else { return }
      lock.withLock { if streamGeneration == generation { continuation = nil } }
    }
    for connection in connections {
      newContinuation.yield(.connected(connection: connection, ownership: .exclusive))
    }
    return stream
  }

  func connectionSnapshots() -> [HIDDeviceConnectionSnapshot] {
    lock.withLock {
      links.values.map {
        HIDDeviceConnectionSnapshot(connection: $0.connection, ownership: .exclusive)
      }
    }.sorted { $0.connection.routingLocationID < $1.connection.routingLocationID }
  }

  /// Sends a USB-layout vibration report. Over Bluetooth LE the report-ID byte is zero and the
  /// report is 42 bytes on every model.
  func setOutputReport(
    locationID: UInt32,
    report: PhysicalHIDOutputReport
  ) -> PhysicalHIDReportResult<Void> {
    guard let writer = lock.withLock({ links[locationID]?.writer }) else { return .unavailable }
    var bytes = Array(report.bytes.prefix(Self.vibrationReportLength))
    guard !bytes.isEmpty else { return .unavailable }
    bytes[0] = 0
    bytes += [UInt8](repeating: 0, count: Self.vibrationReportLength - bytes.count)
    return writer.writeVibration(bytes) ? .success(()) : .failed(.ioReturn(kIOReturnNotResponding))
  }

  // MARK: - Command channel

  /// Writes one command, dropping replies to earlier commands that nobody read.
  func writeCommand(locationID: UInt32, bytes: [UInt8]) throws {
    let writer = lock.withLock { () -> (any Switch2BluetoothLEWriter)? in
      links[locationID]?.replies.removeAll()
      links[locationID]?.current = nil
      return links[locationID]?.writer
    }
    guard let writer else { throw USBTransportError.disconnected }
    guard writer.writeCommand(bytes) else { throw USBTransportError.inputOutput }
  }

  /// Reads at most `length` bytes of the next reply. A read that ends exactly at a reply's end is
  /// followed by one empty read, so a caller reading until a short transfer stops at each reply.
  func readReply(
    locationID: UInt32,
    length: Int,
    timeoutMilliseconds: UInt32
  ) async throws -> [UInt8] {
    let pending = try lock.withLock { () -> [UInt8]? in
      guard links[locationID] != nil else { throw USBTransportError.disconnected }
      return links[locationID]?.current
    }
    if let pending { return take(length, of: pending, locationID: locationID) }
    guard let reply = await nextReply(locationID: locationID, timeout: timeoutMilliseconds) else {
      throw lock.withLock { links[locationID] == nil }
        ? USBTransportError.disconnected : USBTransportError.timeout
    }
    return take(length, of: reply, locationID: locationID)
  }

  private func take(_ length: Int, of reply: [UInt8], locationID: UInt32) -> [UInt8] {
    let chunk = Array(reply.prefix(length))
    lock.withLock {
      links[locationID]?.current = chunk.count < length ? nil : Array(reply.dropFirst(length))
    }
    return chunk
  }

  private enum WaitStart {
    case ready([UInt8]?)
    case waiting(token: UInt64)
  }

  private func nextReply(locationID: UInt32, timeout: UInt32) async -> [UInt8]? {
    await withCheckedContinuation { (continuation: CheckedContinuation<[UInt8]?, Never>) in
      let (start, abandoned) = lock.withLock { () -> (WaitStart, ReplyWaiter?) in
        guard var link = links[locationID] else { return (.ready(nil), nil) }
        if !link.replies.isEmpty {
          let reply = link.replies.removeFirst()
          links[locationID] = link
          return (.ready(reply), nil)
        }
        // One read at a time: a newer read replaces a waiter that its caller abandoned.
        let abandoned = link.waiter
        nextWaiterToken &+= 1
        link.waiter = ReplyWaiter(token: nextWaiterToken, continuation: continuation)
        links[locationID] = link
        return (.waiting(token: nextWaiterToken), abandoned)
      }
      abandoned?.continuation.resume(returning: nil)
      switch start {
      case .ready(let reply): continuation.resume(returning: reply)
      case .waiting(let token):
        DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(Int(timeout))) {
          [weak self] in
          guard let self else { return }
          let expired = lock.withLock { () -> ReplyWaiter? in
            guard let waiter = links[locationID]?.waiter, waiter.token == token else { return nil }
            links[locationID]?.waiter = nil
            return waiter
          }
          expired?.continuation.resume(returning: nil)
        }
      }
    }
  }
}
