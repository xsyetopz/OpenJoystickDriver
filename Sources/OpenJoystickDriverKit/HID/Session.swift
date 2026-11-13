public import Foundation

/// Why a physical HID request or access stream failed, as the platform backend reports it.
public enum PhysicalHIDFailure: Sendable, Equatable, CustomStringConvertible {
  /// A bounded read gave up at its deadline.
  case timedOut
  /// An earlier bounded read of the same device is still outstanding.
  case busy
  /// The device or its link did not respond to a write.
  case notResponding
  /// The device itself declined the request: a stalled control pipe or an unsupported request.
  case declined
  /// A status code of the host's HID stack that has no name here.
  case hostStatus(Int32)

  /// The text of the failure.
  public var description: String {
    switch self {
    case .timedOut: "timed out"
    case .busy: "busy"
    case .notResponding: "not responding"
    case .declined: "declined by the device"
    case .hostStatus(let code): "host status \(code)"
    }
  }
}

/// The result of a physical HID request that returns a value.
public enum PhysicalHIDReportResult<Value: Sendable>: Sendable {
  /// The request succeeded with a value.
  case success(Value)
  /// The device has no HID interface to ask.
  case unavailable
  /// The request failed.
  case failed(PhysicalHIDFailure)
}

extension PhysicalHIDReportResult {
  /// The value of a success; nil for any other result.
  var value: Value? {
    guard case .success(let value) = self else { return nil }
    return value
  }

  /// Whether the request succeeded.
  var succeeded: Bool {
    if case .success = self { return true }
    return false
  }

  /// A short text for the result, for logs and messages.
  var failureDescription: String {
    switch self {
    case .success: "success"
    case .unavailable: "HID interface unavailable"
    case .failed(let failure): failure.description
    }
  }
}

/// The result of a request to release or take back the input claim of a controller.
public enum PhysicalHIDClaimResult: Sendable, Equatable {
  /// OJD released the claim.
  case released
  /// OJD took the claim back.
  case reacquired
  /// The controller has no HID interface to claim.
  case unavailable
  /// The request failed.
  case failed(PhysicalHIDFailure)
}

/// A connection token and ownership observed by the active physical HID backend.
public struct HIDDeviceConnectionSnapshot: Equatable, Sendable {
  /// The connection.
  public let connection: HIDDeviceConnection
  /// The ownership observed for the connection.
  public let ownership: HIDInputOwnership

  /// Creates a snapshot from its fields.
  public init(connection: HIDDeviceConnection, ownership: HIDInputOwnership) {
    self.connection = connection
    self.ownership = ownership
  }

  /// The snapshots of the tracked connections whose devices are still present.
  ///
  /// Each snapshot takes the ownership recorded for its location, or `unknown` when none is. The
  /// snapshots are sorted by routing address, then by connection ID.
  package static func reconcile(
    trackedConnections: [UInt64: HIDDeviceConnection],
    presentDeviceIDs: Set<UInt64>,
    ownershipByLocation: [UInt32: HIDInputOwnership]
  ) -> [Self] {
    trackedConnections.compactMap { deviceID, connection in
      guard presentDeviceIDs.contains(deviceID) else { return nil }
      return Self(
        connection: connection,
        ownership: connection.routingAddress.locationID.flatMap { ownershipByLocation[$0] }
          ?? .unknown
      )
    }.sorted {
      let leftAddress = $0.connection.routingAddress
      let rightAddress = $1.connection.routingAddress
      if leftAddress != rightAddress { return leftAddress < rightAddress }
      return $0.connection.connectionID.uuidString < $1.connection.connectionID.uuidString
    }
  }
}

/// What the physical HID layer needs from a platform backend.
package protocol HIDAccessBackend: Sendable {
  /// The stream of events about devices.
  func deviceEvents() async -> AsyncStream<HIDDeviceEvent>
  /// The connections the backend currently tracks; nil when it cannot confirm which devices are
  /// present.
  func currentConnectionSnapshots() async -> [HIDDeviceConnectionSnapshot]?
  /// Sends an output report to the devices at `address`.
  func setOutputReport(
    address: ControllerConnectionAddress,
    report: PhysicalHIDOutputReport
  ) async -> PhysicalHIDReportResult<Void>
  /// Sends an output report to the device of `connection` only.
  func setOutputReport(
    connection: HIDDeviceConnection,
    report: PhysicalHIDOutputReport
  ) async -> PhysicalHIDReportResult<Void>
  /// Sends a feature report to the devices at `address`.
  func setFeatureReport(
    address: ControllerConnectionAddress,
    report: PhysicalHIDOutputReport
  ) async -> PhysicalHIDReportResult<Void>
  /// Sends a feature report to the device of `connection` only.
  func setFeatureReport(
    connection: HIDDeviceConnection,
    report: PhysicalHIDOutputReport
  ) async -> PhysicalHIDReportResult<Void>
  /// Reads a feature report from the devices at `address`.
  func getFeatureReport(
    address: ControllerConnectionAddress,
    request: PhysicalHIDFeatureReadRequest
  ) async -> PhysicalHIDReportResult<Data>
  /// Reads a feature report from the device of `connection` only.
  func getFeatureReport(
    connection: HIDDeviceConnection,
    request: PhysicalHIDFeatureReadRequest
  ) async -> PhysicalHIDReportResult<Data>
  /// Reads a feature report for a mode probe, which must not wait on a silent device.
  func probeFeatureReport(
    connection: HIDDeviceConnection,
    request: PhysicalHIDFeatureReadRequest
  ) async -> PhysicalHIDReportResult<Data>
  /// Releases the input claim of the devices at `address`, so the system or another client can use
  /// them.
  func releaseInputClaim(address: ControllerConnectionAddress) async -> PhysicalHIDClaimResult
  /// Takes the input claim of the devices at `address` back.
  func reacquireInputClaim(address: ControllerConnectionAddress) async -> PhysicalHIDClaimResult
  /// Re-runs the seize of an address's devices whose earlier attempt was refused or failed.
  func retryInputClaim(address: ControllerConnectionAddress) async
  /// Closes every device handle at `address`, seized or shared, so another process can open the
  /// devices.
  func closeDeviceHandles(address: ControllerConnectionAddress) async -> PhysicalHIDClaimResult
  /// Opens again the device handles ``closeDeviceHandles(address:)`` closed, seizing the devices
  /// that were seized.
  func reopenDeviceHandles(address: ControllerConnectionAddress) async -> PhysicalHIDClaimResult
  /// Delivers the decoded element values of `connection` to the driver that parses them.
  func routeElementValues(connection: HIDDeviceConnection) async
  /// Admits again each device of a model in `models` whose native pass-through changed with
  /// the current records, and returns the connections it admitted.
  func reevaluateOwnership(of models: Set<ControllerModelID>) async -> Set<UUID>
}

extension HIDAccessBackend {
  /// A backend with no bounded read reads as the startup reads do.
  package func probeFeatureReport(
    connection: HIDDeviceConnection,
    request: PhysicalHIDFeatureReadRequest
  ) async -> PhysicalHIDReportResult<Data> {
    await getFeatureReport(connection: connection, request: request)
  }

  /// A backend that opens no device handle has none to close.
  package func closeDeviceHandles(
    address _: ControllerConnectionAddress
  ) -> PhysicalHIDClaimResult {
    .unavailable
  }

  /// A backend that opens no device handle has none to open again.
  package func reopenDeviceHandles(
    address _: ControllerConnectionAddress
  ) -> PhysicalHIDClaimResult {
    .unavailable
  }

  /// A backend whose devices never pass through to macOS has nothing to re-evaluate.
  package func reevaluateOwnership(of _: Set<ControllerModelID>) -> Set<UUID> { [] }
}

/// The physical HID access of the application over a platform backend.
///
/// The host supplies the backend; `bluetoothLEHub` adds the Switch 2 controllers connected over
/// Bluetooth LE GATT. Tests inject fake backends.
public final class HIDManager: Sendable {
  /// The platform backend.
  private let backend: any HIDAccessBackend

  /// Creates a manager over `backend`.
  package init(backend: any HIDAccessBackend) { self.backend = backend }

  /// Serves the devices of `primary` and the hub's Bluetooth LE controllers as one backend.
  ///
  /// Without a hub, only the devices of `primary` are served.
  package init(primary: any HIDAccessBackend, bluetoothLEHub: Switch2BluetoothLEHub?) {
    backend =
      bluetoothLEHub.map { BluetoothLECompositeHIDBackend(primary: primary, hub: $0) } ?? primary
  }

  /// The stream of device events from the backend.
  public func deviceEvents() async -> AsyncStream<HIDDeviceEvent> { await backend.deviceEvents() }

  /// Returns exact current connections, or `nil` if the backend cannot confirm presence.
  ///
  /// An empty array is a confirmed observation with no tracked current connections.
  public func currentConnectionSnapshots() async -> [HIDDeviceConnectionSnapshot]? {
    await backend.currentConnectionSnapshots()
  }

  /// Sends an output report to the devices at `address`.
  public func setOutputReport(
    address: ControllerConnectionAddress,
    report: PhysicalHIDOutputReport
  ) async -> PhysicalHIDReportResult<Void> {
    await backend.setOutputReport(address: address, report: report)
  }

  /// Sends an output report to the exact connection that the backend observed.
  ///
  /// Unlike the output by address, it never falls back to another device at the same location.
  /// Sends a report only to the exact connection lifetime previously observed by the backend.
  /// Unlike route-based output, this never falls back to another device at the same location.
  public func setOutputReport(
    connection: HIDDeviceConnection,
    report: PhysicalHIDOutputReport
  ) async -> PhysicalHIDReportResult<Void> {
    await backend.setOutputReport(connection: connection, report: report)
  }

  /// Sends a feature report to the devices at `address`.
  public func setFeatureReport(
    address: ControllerConnectionAddress,
    report: PhysicalHIDOutputReport
  ) async -> PhysicalHIDReportResult<Void> {
    await backend.setFeatureReport(address: address, report: report)
  }

  /// Sends a feature report to the exact connection that the backend observed.
  ///
  /// Sends a feature report only to the exact connection lifetime previously observed by the
  /// backend.
  public func setFeatureReport(
    connection: HIDDeviceConnection,
    report: PhysicalHIDOutputReport
  ) async -> PhysicalHIDReportResult<Void> {
    await backend.setFeatureReport(connection: connection, report: report)
  }

  /// Reads a feature report from the devices at `address`.
  public func getFeatureReport(
    address: ControllerConnectionAddress,
    request: PhysicalHIDFeatureReadRequest
  ) async -> PhysicalHIDReportResult<Data> {
    await backend.getFeatureReport(address: address, request: request)
  }

  /// Reads a feature report from the exact connection that the backend observed, never from a
  /// sibling interface at its location.
  ///
  /// Reads a feature report only from the exact connection lifetime previously observed by the
  /// backend, never from a sibling interface at its location.
  public func getFeatureReport(
    connection: HIDDeviceConnection,
    request: PhysicalHIDFeatureReadRequest
  ) async -> PhysicalHIDReportResult<Data> {
    await backend.getFeatureReport(connection: connection, request: request)
  }

  /// Reads a feature report for a mode probe.
  ///
  /// It gives up after a deadline, and while an earlier probe read of the connection is
  /// outstanding it fails at once.
  func probeFeatureReport(
    connection: HIDDeviceConnection,
    request: PhysicalHIDFeatureReadRequest
  ) async -> PhysicalHIDReportResult<Data> {
    await backend.probeFeatureReport(connection: connection, request: request)
  }

  /// Releases the input claim of the devices at `address`, so the system or another client can use
  /// them.
  public func releaseInputClaim(
    address: ControllerConnectionAddress
  ) async -> PhysicalHIDClaimResult {
    await backend.releaseInputClaim(address: address)
  }

  /// Takes the input claim of the devices at `address` back.
  public func reacquireInputClaim(
    address: ControllerConnectionAddress
  ) async -> PhysicalHIDClaimResult {
    await backend.reacquireInputClaim(address: address)
  }

  /// Closes every device handle at `address`, so another process can open the devices.
  public func closeDeviceHandles(
    address: ControllerConnectionAddress
  ) async -> PhysicalHIDClaimResult {
    await backend.closeDeviceHandles(address: address)
  }

  /// Opens again the device handles that ``closeDeviceHandles(address:)`` closed.
  public func reopenDeviceHandles(
    address: ControllerConnectionAddress
  ) async -> PhysicalHIDClaimResult {
    await backend.reopenDeviceHandles(address: address)
  }

  /// Runs the seize again for the devices at `address` whose earlier attempt was refused or failed.
  public func retryInputClaim(address: ControllerConnectionAddress) async {
    await backend.retryInputClaim(address: address)
  }

  /// Delivers a connection's decoded element values, for a driver that parses them.
  public func routeElementValues(connection: HIDDeviceConnection) async {
    await backend.routeElementValues(connection: connection)
  }

  /// Admits again each device of a model in `models` whose native pass-through changed with the
  /// current records, so a changed `ownership` seizes or releases it without a replug.
  ///
  /// Returns the connections it admitted; their `.connected` events are already queued.
  func reevaluateOwnership(of models: Set<ControllerModelID>) async -> Set<UUID> {
    await backend.reevaluateOwnership(of: models)
  }
}
