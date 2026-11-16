public import Foundation

/// GATT writes to one connected Switch 2 controller.
///
/// Each returns false when the link cannot send.
public protocol Switch2BluetoothLEWriter: Sendable {
  /// Writes one command to the command characteristic, without response.
  func writeCommand(_ bytes: [UInt8]) -> Bool
  /// Writes one vibration report to the model's vibration characteristic, without response.
  func writeVibration(_ bytes: [UInt8]) -> Bool
}

/// Switch 2 GATT identifiers and advertisement format, from ndeadly's switch2_controller_research
/// and joycon2cpp.
public enum Switch2BluetoothLEProfile {
  /// The UUID of the GATT service of a Switch 2 controller.
  public static let serviceUUID = "AB7DE9BE-89FE-49AD-828F-118F09DF7FD0"
  /// The UUID of the characteristic that notifies input frames.
  public static let inputUUID = "AB7DE9BE-89FE-49AD-828F-118F09DF7FD2"
  /// The UUID of the characteristic that takes commands.
  public static let commandUUID = "649D4AC9-8EB7-4E6C-AF44-1EA54FE5F005"
  /// The UUID of the characteristic that notifies command replies.
  public static let commandReplyUUID = "C765A961-D9D8-4D36-A20A-5315B111836A"

  /// The Nintendo company ID that starts the manufacturer data of an advertisement.
  static let nintendoCompanyID: UInt16 = 0x0553
  /// Nintendo's USB vendor ID, which the advertisement repeats.
  static let nintendoVendorID: UInt16 = 0x057E
  /// The `Transport` property value the host HID stack reports for a Bluetooth LE device.
  static let hidTransportProperty = "BluetoothLowEnergy"

  /// The vibration characteristic UUID that the current controller record of a Nintendo product
  /// declares in its `bluetoothLE` section; nil for a product without one.
  public static func vibrationUUID(productID: UInt16) -> String? {
    DeviceCatalog.current.withLock { $0 }
      .record(for: ControllerModelID(vendorID: nintendoVendorID, productID: productID))?
      .bluetoothLEVibrationCharacteristic
  }

  /// The product ID of a Switch 2 controller advertisement, or nil for any other advertisement.
  /// `manufacturerData` starts with the little-endian company ID, as CoreBluetooth delivers it.
  public static func productID(manufacturerData data: Data) -> UInt16? {
    let bytes = [UInt8](data)
    guard bytes.count >= 9 else { return nil }
    func word(_ offset: Int) -> UInt16 { UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8 }
    guard word(0) == nintendoCompanyID, word(5) == nintendoVendorID else { return nil }
    let productID = word(7)
    return vibrationUUID(productID: productID) == nil ? nil : productID
  }
}

/// Presents connected Switch 2 Bluetooth LE controllers as HID connections, and carries their
/// command channel and vibration output over GATT.
///
/// The CoreBluetooth central calls the `link` and `received` methods on its serial queue, so input
/// keeps its order. Each connection is addressed by its peripheral's Core Bluetooth identifier,
/// as ``ControllerConnectionAddress/gattPeripheral(_:)``.
public final class Switch2BluetoothLEHub: @unchecked Sendable {
  /// The console's vibration report length on every model.
  static let vibrationReportLength = 0x2A

  /// A read that waits for the next command reply.
  private struct ReplyWaiter {
    /// Tells this waiter from a later one of the same link.
    let token: UInt64
    /// Resumed with the reply, or nil when the read times out or the link goes.
    let continuation: CheckedContinuation<[UInt8]?, Never>
  }

  /// One connected controller.
  private struct Link {
    /// The peripheral's Core Bluetooth identifier.
    let peripheralID: UUID
    /// The HID connection that the hub presents.
    let connection: HIDDeviceConnection
    /// The writer for the controller's GATT characteristics.
    let writer: any Switch2BluetoothLEWriter
    /// The command replies that no read has taken.
    var replies: [[UInt8]] = []
    /// The unread rest of the reply being read, empty after a reply read to its end.
    var current: [UInt8]?
    /// The read that waits for a reply; nil when none waits.
    var waiter: ReplyWaiter?
  }

  /// Guards the links, the waiter counter and the event stream.
  private let lock = NSLock()
  /// The connected controllers by peripheral identifier.
  private var links: [UUID: Link] = [:]
  /// The token of the latest waiter.
  private var nextWaiterToken: UInt64 = 0
  /// The continuation of the current event stream; nil when no stream is open.
  private var continuation: AsyncStream<HIDDeviceEvent>.Continuation?
  /// Tells event streams apart, so a finished stream does not clear a newer one.
  private var streamGeneration: UInt64 = 0

  /// Creates a hub with no connected controllers.
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
      let device = PhysicalDevice(
        vendorID: Switch2BluetoothLEProfile.nintendoVendorID,
        productID: productID,
        productName: productName,
        transportProperty: Switch2BluetoothLEProfile.hidTransportProperty,
        interfaces: [
          PhysicalInterfaceSignature(
            interfaceClass: 0x03,
            hostTransport: .bluetoothLE,
            physicalTransport: .bluetoothLE,
            accessBackend: .gatt
          )
        ]
      )
      let connection = HIDDeviceConnection(
        physicalDevice: device,
        routingAddress: .gattPeripheral(peripheralID)
      )
      links[peripheralID] = Link(peripheralID: peripheralID, connection: connection, writer: writer)
      return (.connected(connection: connection, ownership: .exclusive), continuation)
    }
    stream?.yield(event)
  }

  /// Delivers one input notification: report 0x05 without its ID byte.
  public func receivedInput(peripheralID: UUID, bytes: [UInt8]) {
    let target = lock.withLock {
      () -> (HIDDeviceConnection, AsyncStream<HIDDeviceEvent>.Continuation)? in
      guard let link = links[peripheralID], let continuation else { return nil }
      return (link.connection, continuation)
    }
    guard let (connection, stream) = target else { return }
    stream.yield(
      .inputReport(
        address: connection.routingAddress,
        connectionID: connection.connectionID,
        reportID: 0x05,
        data: Data([0x05] + bytes)
      )
    )
  }

  /// Delivers one command-reply notification.
  public func receivedReply(peripheralID: UUID, bytes: [UInt8]) {
    let waiter = lock.withLock { () -> ReplyWaiter? in
      guard links[peripheralID] != nil else { return nil }
      guard let waiter = links[peripheralID]?.waiter else {
        links[peripheralID]?.replies.append(bytes)
        return nil
      }
      links[peripheralID]?.waiter = nil
      return waiter
    }
    waiter?.continuation.resume(returning: bytes)
  }

  /// Removes the controller `peripheralID` and ends the read that waits on it.
  public func linkDisconnected(peripheralID: UUID) {
    let removed = lock.withLock { () -> (Link, AsyncStream<HIDDeviceEvent>.Continuation?)? in
      guard let link = links.removeValue(forKey: peripheralID) else { return nil }
      return (link, continuation)
    }
    guard let (link, stream) = removed else { return }
    link.waiter?.continuation.resume(returning: nil)
    stream?.yield(.disconnected(connection: link.connection))
  }

  // MARK: - HID backend

  /// Whether `address` names a connected Switch 2 controller's GATT link.
  func owns(_ address: ControllerConnectionAddress) -> Bool {
    guard case .gattPeripheral(let peripheralID) = address else { return false }
    return lock.withLock { links[peripheralID] != nil }
  }

  /// Starts a new event stream, ending the previous one, and replays the connected controllers.
  func events() -> AsyncStream<HIDDeviceEvent> {
    let (stream, newContinuation) = AsyncStream.makeStream(of: HIDDeviceEvent.self)
    let (previous, connections, generation) = lock.withLock {
      let previous = continuation
      continuation = newContinuation
      streamGeneration &+= 1
      let connections = links.values.map(\.connection).sorted {
        $0.routingAddress < $1.routingAddress
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

  /// The snapshots of the connected controllers, sorted by routing address.
  func connectionSnapshots() -> [HIDDeviceConnectionSnapshot] {
    lock.withLock {
      links.values.map {
        HIDDeviceConnectionSnapshot(connection: $0.connection, ownership: .exclusive)
      }
    }.sorted { $0.connection.routingAddress < $1.connection.routingAddress }
  }

  /// Sends a USB-layout vibration report.
  ///
  /// Over Bluetooth LE the report-ID byte is zero and the report is 42 bytes on every model.
  func setOutputReport(
    peripheralID: UUID,
    report: PhysicalHIDOutputReport
  ) -> PhysicalHIDReportResult<Void> {
    guard let writer = lock.withLock({ links[peripheralID]?.writer }) else { return .unavailable }
    var bytes = Array(report.bytes.prefix(Self.vibrationReportLength))
    guard !bytes.isEmpty else { return .unavailable }
    bytes[0] = 0
    bytes += [UInt8](repeating: 0, count: Self.vibrationReportLength - bytes.count)
    return writer.writeVibration(bytes) ? .success(()) : .failed(.notResponding)
  }

  // MARK: - Command channel

  /// Writes one command, dropping replies to earlier commands that nobody read.
  func writeCommand(peripheralID: UUID, bytes: [UInt8]) throws {
    let writer = lock.withLock { () -> (any Switch2BluetoothLEWriter)? in
      links[peripheralID]?.replies.removeAll()
      links[peripheralID]?.current = nil
      return links[peripheralID]?.writer
    }
    guard let writer else { throw USBTransportError.disconnected }
    guard writer.writeCommand(bytes) else { throw USBTransportError.inputOutput }
  }

  /// Reads at most `length` bytes of the next reply.
  ///
  /// A read that ends exactly at a reply's end is followed by one empty read, so a caller reading
  /// until a short transfer stops at each reply.
  func readReply(
    peripheralID: UUID,
    length: Int,
    timeoutMilliseconds: UInt32
  ) async throws -> [UInt8] {
    let pending = try lock.withLock { () -> [UInt8]? in
      guard links[peripheralID] != nil else { throw USBTransportError.disconnected }
      return links[peripheralID]?.current
    }
    if let pending { return take(length, of: pending, peripheralID: peripheralID) }
    guard let reply = await nextReply(peripheralID: peripheralID, timeout: timeoutMilliseconds)
    else {
      throw lock.withLock { links[peripheralID] == nil }
        ? USBTransportError.disconnected : USBTransportError.timeout
    }
    return take(length, of: reply, peripheralID: peripheralID)
  }

  /// Whether a read is suspended until the next reply of `peripheralID`.
  func hasWaitingReadForTesting(peripheralID: UUID) -> Bool {
    lock.withLock { links[peripheralID]?.waiter != nil }
  }

  /// Takes up to `length` bytes of `reply` and keeps the rest for the next read of `peripheralID`.
  private func take(_ length: Int, of reply: [UInt8], peripheralID: UUID) -> [UInt8] {
    let chunk = Array(reply.prefix(length))
    lock.withLock {
      links[peripheralID]?.current = chunk.count < length ? nil : Array(reply.dropFirst(length))
    }
    return chunk
  }

  /// The start of a wait for a reply.
  private enum WaitStart {
    /// A reply, or nil when the link is gone, is ready.
    case ready([UInt8]?)
    /// The read waits; the token identifies its waiter.
    case waiting(token: UInt64)
  }

  /// Waits up to `timeout` milliseconds for the next reply of `peripheralID`; nil when none
  /// arrives.
  private func nextReply(peripheralID: UUID, timeout: UInt32) async -> [UInt8]? {
    await withCheckedContinuation { (continuation: CheckedContinuation<[UInt8]?, Never>) in
      let (start, abandoned) = lock.withLock { () -> (WaitStart, ReplyWaiter?) in
        guard var link = links[peripheralID] else { return (.ready(nil), nil) }
        if !link.replies.isEmpty {
          let reply = link.replies.removeFirst()
          links[peripheralID] = link
          return (.ready(reply), nil)
        }
        // One read at a time: a newer read replaces a waiter that its caller abandoned.
        let abandoned = link.waiter
        nextWaiterToken &+= 1
        link.waiter = ReplyWaiter(token: nextWaiterToken, continuation: continuation)
        links[peripheralID] = link
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
            guard let waiter = links[peripheralID]?.waiter, waiter.token == token else {
              return nil
            }
            links[peripheralID]?.waiter = nil
            return waiter
          }
          expired?.continuation.resume(returning: nil)
        }
      }
    }
  }
}
