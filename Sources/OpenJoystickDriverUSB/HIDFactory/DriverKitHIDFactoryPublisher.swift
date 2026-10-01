import IOKit
import OpenJoystickDriverKit
import SwifterKit

/// Publishes virtual gamepads through OJD's DriverKit HID device factory extension.
///
/// It returns nil, so the dispatcher falls back to `IOHIDUserDevice`, while the extension is
/// absent or not ready, when another client owns the factory, and when every device slot is
/// taken. All devices share one connection, because the factory accepts commands only from the
/// connection that receives its events.
public actor DriverKitHIDFactoryPublisher: VirtualHIDDevicePublisher {
  typealias Connector = @Sendable () async throws -> any HIDFactoryConnection

  /// Nanoseconds to wait before each reconnect attempt after the connection drops. A crashed
  /// extension needs time to restart; after the last attempt the devices fail their sends and
  /// the dispatcher falls back to `IOHIDUserDevice`.
  static let defaultReconnectDelays: [UInt64] = [
    0, 500_000_000, 1_000_000_000, 2_000_000_000, 4_000_000_000,
  ]

  private let connect: Connector
  private let reconnectDelays: [UInt64]
  private var connection: Task<any HIDFactoryConnection, any Error>?
  /// The live devices of the current connection, by handle.
  private var devices: [UInt32: Published] = [:]
  private var reportedUnavailable = false

  private struct Published {
    let device: HIDFactoryDevice
    let configuration: HIDDeviceConfiguration
    let hostReports: VirtualHIDHostReports
  }

  public init(client: DriverClient = DriverClient()) {
    self.init { try await SwifterKitHIDFactoryConnection.connect(client: client) }
  }

  init(reconnectDelays: [UInt64] = defaultReconnectDelays, connect: @escaping Connector) {
    self.reconnectDelays = reconnectDelays
    self.connect = connect
  }

  @preconcurrency
  public func publish(
    _ device: VirtualHIDDeviceDescription,
    hostReports: VirtualHIDHostReports,
    onLost: @escaping @Sendable () -> Void
  ) async -> (any UserSpaceOutputDispatcher.VirtualDeviceBackend)? {
    let connection: any HIDFactoryConnection
    do { connection = try await currentConnection() } catch {
      reportUnavailable(error)
      return nil
    }
    let configuration = Self.configuration(for: device)
    let handle: UInt32
    do { handle = try await create(configuration, on: connection) } catch let error
      as HIDFactoryStatusError where error.status == kIOReturnNoSpace
    {
      print("[HIDFactory] Every device slot is taken; using IOHIDUserDevice")
      return nil
    } catch {
      reportUnavailable(error)
      return nil
    }
    let published = HIDFactoryDevice(handle: handle, connection: connection, onLost: onLost) {
      device in await self.deviceDidClose(device)
    }
    devices[handle] = Published(
      device: published,
      configuration: configuration,
      hostReports: hostReports
    )
    return published
  }

  static func configuration(for device: VirtualHIDDeviceDescription) -> HIDDeviceConfiguration {
    HIDDeviceConfiguration(
      reportDescriptor: device.reportDescriptor,
      transport: device.transport,
      vendorID: UInt32(device.vendorID),
      productID: UInt32(device.productID),
      versionNumber: UInt32(clamping: device.versionNumber),
      locationID: device.locationID,
      manufacturer: device.manufacturer,
      product: device.product,
      serialNumber: device.serialNumber,
      primaryUsagePage: device.primaryUsagePage,
      primaryUsage: device.primaryUsage,
      acceptedHostReportTypes: .all,
      answeredReportTypes: .all
    )
  }

  /// Creates one device, retrying once while the factory is busy.
  private func create(
    _ configuration: HIDDeviceConfiguration,
    on connection: any HIDFactoryConnection
  ) async throws -> UInt32 {
    do { return try await connection.createDevice(configuration) } catch let error
      as HIDFactoryStatusError where error.status == kIOReturnBusy
    {
      return try await connection.createDevice(configuration)
    }
  }

  private func currentConnection() async throws -> any HIDFactoryConnection {
    let task: Task<any HIDFactoryConnection, any Error>
    if let connection {
      task = connection
    } else {
      task = Task {
        let established = try await connect()
        Task { await self.receiveEvents(from: established) }
        return established
      }
      connection = task
    }
    do { return try await task.value } catch {
      if connection == task { connection = nil }
      throw error
    }
  }

  private func receiveEvents(from connection: any HIDFactoryConnection) async {
    for await event in connection.events { handle(event) }
    // The factory removed every device of the closed connection.
    self.connection = nil
    let lost = Array(devices.values)
    devices.removeAll()
    guard !lost.isEmpty else { return }
    for published in lost { published.device.suspend() }
    await republish(lost)
  }

  /// Recreates the devices of a dropped connection on a new one, so each virtual gamepad
  /// reappears with its last report instead of waiting for the next input.
  private func republish(_ lost: [Published]) async {
    for delay in reconnectDelays {
      try? await Task.sleep(nanoseconds: delay)
      guard let connection = try? await currentConnection() else { continue }
      for published in lost {
        guard let handle = try? await create(published.configuration, on: connection) else {
          published.device.markLost()
          continue
        }
        devices[handle] = published
        if await !published.device.rebind(handle: handle, connection: connection) {
          devices[handle] = nil
          try? await connection.terminateDevice(handle)
        }
      }
      return
    }
    print("[HIDFactory] Factory did not come back; using IOHIDUserDevice")
    for published in lost { published.device.markLost() }
  }

  private func handle(_ event: HIDFactoryEvent) {
    switch event {
    case .setReport(let device, let type, let reportID, let bytes):
      _ = devices[device]?.hostReports.setReport(type: type, reportID: reportID, bytes: bytes)
    case .getReport(let request):
      let answer =
        devices[request.device]?.hostReports.getReport(
          type: request.type,
          reportID: request.reportID,
          maxSize: request.capacity
        ) ?? (bytes: [], status: kIOReturnNotReady)
      Task { try? await request.complete(answer.bytes, answer.status) }
    case .terminated(let device): devices[device] = nil
    }
  }

  private func deviceDidClose(_ device: HIDFactoryDevice) {
    devices = devices.filter { $0.value.device !== device }
  }

  /// Logs once; IOHIDUserDevice takes over for every device until the factory is reachable.
  private func reportUnavailable(_ error: any Error) {
    guard !reportedUnavailable else { return }
    reportedUnavailable = true
    print("[HIDFactory] Factory unavailable, using IOHIDUserDevice: \(error)")
  }
}

/// One device the factory created. After its connection drops, the publisher rebinds it to a
/// device on a new connection, or marks it lost.
final class HIDFactoryDevice: UserSpaceOutputDispatcher.VirtualDeviceBackend {
  private enum Binding {
    case live(handle: UInt32, connection: any HIDFactoryConnection)
    /// Reconnecting; sends only update `lastReport`.
    case suspended
    /// Sends fail, so the dispatcher recreates the device.
    case lost
  }

  private struct State {
    var binding: Binding
    var lastReport: [UInt8]?
    var termination: Task<Void, Never>?
  }

  private let state: Locked<State>
  private let onLost: @Sendable () -> Void
  private let onClose: @Sendable (HIDFactoryDevice) async -> Void

  init(
    handle: UInt32,
    connection: any HIDFactoryConnection,
    onLost: @escaping @Sendable () -> Void,
    onClose: @escaping @Sendable (HIDFactoryDevice) async -> Void
  ) {
    state = Locked(State(binding: .live(handle: handle, connection: connection)))
    self.onLost = onLost
    self.onClose = onClose
  }

  func send(_ report: [UInt8]) async throws {
    let binding = state.withLock { state in
      state.lastReport = report
      return state.binding
    }
    switch binding {
    case .live(let handle, let connection):
      try await connection.submitInputReport(report, to: handle)
    case .suspended: return
    case .lost: throw HIDFactoryStatusError(status: kIOReturnNoDevice)
    }
  }

  func suspend() { state.withLock { $0.binding = .suspended } }

  /// Fails later sends and tells the owner once, unless the device is already closing.
  func markLost() {
    let notify = state.withLock { state -> Bool in
      if case .lost = state.binding { return false }
      state.binding = .lost
      return state.termination == nil
    }
    if notify { onLost() }
  }

  /// Moves the device to `handle` and resends its last report. Returns false when the device
  /// closed while reconnecting.
  func rebind(handle: UInt32, connection: any HIDFactoryConnection) async -> Bool {
    let report = state.withLock { state -> [UInt8]?? in
      guard state.termination == nil else { return nil }
      state.binding = .live(handle: handle, connection: connection)
      return .some(state.lastReport)
    }
    guard let report else { return false }
    if let report { try? await connection.submitInputReport(report, to: handle) }
    return true
  }

  func close() {
    state.withLock { state in
      guard state.termination == nil else { return }
      let binding = state.binding
      state.termination = Task { [onClose] in
        if case .live(let handle, let connection) = binding {
          // A device the system already removed fails to terminate; it is gone either way.
          try? await connection.terminateDevice(handle)
        }
        await onClose(self)
      }
    }
  }

  func waitUntilClosed() async { await state.withLock { $0.termination }?.value }
}
