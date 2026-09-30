import Foundation
import IOKit

public enum PhysicalHIDFailure: Sendable, Equatable { case ioReturn(IOReturn) }

public enum PhysicalHIDReportResult<Value: Sendable>: Sendable {
  case success(Value)
  case unavailable
  case failed(PhysicalHIDFailure)
}

extension PhysicalHIDReportResult {
  var value: Value? {
    guard case .success(let value) = self else { return nil }
    return value
  }

  var succeeded: Bool {
    if case .success = self { return true }
    return false
  }

  var failureDescription: String {
    switch self {
    case .success: "success"
    case .unavailable: "HID interface unavailable"
    case .failed(.ioReturn(let code)): "IOKit code \(code)"
    }
  }
}

public enum PhysicalHIDClaimResult: Sendable, Equatable {
  case released
  case reacquired
  case unavailable
  case failed(PhysicalHIDFailure)
}

/// A connection token and ownership observed by the active physical HID backend.
public struct HIDDeviceConnectionSnapshot: Equatable, Sendable {
  public let connection: HIDDeviceConnection
  public let ownership: HIDInputOwnership

  public init(connection: HIDDeviceConnection, ownership: HIDInputOwnership) {
    self.connection = connection
    self.ownership = ownership
  }

  static func reconcile(
    trackedConnections: [UInt64: HIDDeviceConnection],
    presentDeviceIDs: Set<UInt64>,
    ownershipByLocation: [UInt32: HIDInputOwnership]
  ) -> [Self] {
    trackedConnections.compactMap { deviceID, connection in
      guard presentDeviceIDs.contains(deviceID) else { return nil }
      return Self(
        connection: connection,
        ownership: ownershipByLocation[connection.routingLocationID] ?? .unknown
      )
    }.sorted {
      let leftLocation = $0.connection.routingLocationID
      let rightLocation = $1.connection.routingLocationID
      if leftLocation != rightLocation { return leftLocation < rightLocation }
      return $0.connection.connectionID.uuidString < $1.connection.connectionID.uuidString
    }
  }
}

protocol HIDAccessBackend: Sendable {
  func deviceEvents() async -> AsyncStream<HIDDeviceEvent>
  func currentConnectionSnapshots() async -> [HIDDeviceConnectionSnapshot]?
  func setOutputReport(
    locationID: UInt32,
    report: PhysicalHIDOutputReport
  ) async -> PhysicalHIDReportResult<Void>
  func setOutputReport(
    connection: HIDDeviceConnection,
    report: PhysicalHIDOutputReport
  ) async -> PhysicalHIDReportResult<Void>
  func setFeatureReport(
    locationID: UInt32,
    report: PhysicalHIDOutputReport
  ) async -> PhysicalHIDReportResult<Void>
  func setFeatureReport(
    connection: HIDDeviceConnection,
    report: PhysicalHIDOutputReport
  ) async -> PhysicalHIDReportResult<Void>
  func getFeatureReport(
    locationID: UInt32,
    request: PhysicalHIDFeatureReadRequest
  ) async -> PhysicalHIDReportResult<Data>
  func getFeatureReport(
    connection: HIDDeviceConnection,
    request: PhysicalHIDFeatureReadRequest
  ) async -> PhysicalHIDReportResult<Data>
  func releaseInputClaim(locationID: UInt32) async -> PhysicalHIDClaimResult
  func reacquireInputClaim(locationID: UInt32) async -> PhysicalHIDClaimResult
  /// Re-runs the seize of a location's devices whose earlier attempt was refused or failed.
  func retryInputClaim(locationID: UInt32) async
  func routeElementValues(connection: HIDDeviceConnection) async
}

private final class IOHIDAccessBackend: HIDAccessBackend, Sendable {
  private let stream: HIDDeviceStream

  init(additionalProfileIdentifiers: [DeviceIdentifier], roleProfileIdentifiers: [DeviceIdentifier])
  {
    stream = HIDDeviceStream(
      additionalProfileIdentifiers: additionalProfileIdentifiers,
      roleProfileIdentifiers: roleProfileIdentifiers
    )
  }

  func deviceEvents() async -> AsyncStream<HIDDeviceEvent> {
    await MainActor.run { stream.deviceEvents() }
  }

  func currentConnectionSnapshots() async -> [HIDDeviceConnectionSnapshot]? {
    await stream.currentConnectionSnapshots()
  }

  func setOutputReport(
    locationID: UInt32,
    report: PhysicalHIDOutputReport
  ) -> PhysicalHIDReportResult<Void> {
    stream.setOutputReport(locationID: locationID, report: report)
  }

  func setOutputReport(
    connection: HIDDeviceConnection,
    report: PhysicalHIDOutputReport
  ) async -> PhysicalHIDReportResult<Void> {
    await stream.setOutputReport(connection: connection, report: report)
  }

  func setFeatureReport(
    locationID: UInt32,
    report: PhysicalHIDOutputReport
  ) -> PhysicalHIDReportResult<Void> {
    stream.setFeatureReport(locationID: locationID, report: report)
  }

  func setFeatureReport(
    connection: HIDDeviceConnection,
    report: PhysicalHIDOutputReport
  ) async -> PhysicalHIDReportResult<Void> {
    await stream.setFeatureReport(connection: connection, report: report)
  }

  func getFeatureReport(
    locationID: UInt32,
    request: PhysicalHIDFeatureReadRequest
  ) -> PhysicalHIDReportResult<Data> {
    stream.getFeatureReport(locationID: locationID, request: request)
  }

  func getFeatureReport(
    connection: HIDDeviceConnection,
    request: PhysicalHIDFeatureReadRequest
  ) async -> PhysicalHIDReportResult<Data> {
    await stream.getFeatureReport(connection: connection, request: request)
  }

  func releaseInputClaim(locationID: UInt32) -> PhysicalHIDClaimResult {
    stream.releaseInputClaim(locationID: locationID)
  }

  func reacquireInputClaim(locationID: UInt32) -> PhysicalHIDClaimResult {
    stream.reacquireInputClaim(locationID: locationID)
  }

  func retryInputClaim(locationID: UInt32) { stream.retryInputClaim(locationID: locationID) }

  func routeElementValues(connection: HIDDeviceConnection) async {
    await stream.routeElementValues(connection: connection)
  }
}

/// App HID access wrapper over IOHIDManager on every supported macOS release.
///
/// Tests inject fake backends through `init(backend:)`.
public final class HIDManager: Sendable {
  private let backend: any HIDAccessBackend

  init(backend: any HIDAccessBackend) { self.backend = backend }

  /// `roleProfileIdentifiers` are the models whose family declares HID protocol roles.
  /// `bluetoothLEHub` adds the Switch 2 controllers connected over Bluetooth LE GATT.
  public init(
    additionalProfileIdentifiers: [DeviceIdentifier] = [],
    roleProfileIdentifiers: [DeviceIdentifier] = [],
    bluetoothLEHub: Switch2BluetoothLEHub? = nil
  ) {
    let ioHID = IOHIDAccessBackend(
      additionalProfileIdentifiers: additionalProfileIdentifiers,
      roleProfileIdentifiers: roleProfileIdentifiers
    )
    backend =
      bluetoothLEHub.map { BluetoothLECompositeHIDBackend(primary: ioHID, hub: $0) } ?? ioHID
  }

  public func deviceEvents() async -> AsyncStream<HIDDeviceEvent> { await backend.deviceEvents() }

  /// Returns exact current connections, or `nil` if the backend cannot confirm presence.
  /// An empty array is a confirmed observation with no tracked current connections.
  public func currentConnectionSnapshots() async -> [HIDDeviceConnectionSnapshot]? {
    await backend.currentConnectionSnapshots()
  }

  public func setOutputReport(
    locationID: UInt32,
    report: PhysicalHIDOutputReport
  ) async -> PhysicalHIDReportResult<Void> {
    await backend.setOutputReport(locationID: locationID, report: report)
  }

  /// Sends a report only to the exact connection lifetime previously observed by the backend.
  /// Unlike route-based output, this never falls back to another device at the same location.
  public func setOutputReport(
    connection: HIDDeviceConnection,
    report: PhysicalHIDOutputReport
  ) async -> PhysicalHIDReportResult<Void> {
    await backend.setOutputReport(connection: connection, report: report)
  }

  public func setFeatureReport(
    locationID: UInt32,
    report: PhysicalHIDOutputReport
  ) async -> PhysicalHIDReportResult<Void> {
    await backend.setFeatureReport(locationID: locationID, report: report)
  }

  /// Sends a feature report only to the exact connection lifetime previously observed by the
  /// backend.
  public func setFeatureReport(
    connection: HIDDeviceConnection,
    report: PhysicalHIDOutputReport
  ) async -> PhysicalHIDReportResult<Void> {
    await backend.setFeatureReport(connection: connection, report: report)
  }

  public func getFeatureReport(
    locationID: UInt32,
    request: PhysicalHIDFeatureReadRequest
  ) async -> PhysicalHIDReportResult<Data> {
    await backend.getFeatureReport(locationID: locationID, request: request)
  }

  /// Reads a feature report only from the exact connection lifetime previously observed by the
  /// backend, never from a sibling interface at its location.
  public func getFeatureReport(
    connection: HIDDeviceConnection,
    request: PhysicalHIDFeatureReadRequest
  ) async -> PhysicalHIDReportResult<Data> {
    await backend.getFeatureReport(connection: connection, request: request)
  }

  public func releaseInputClaim(locationID: UInt32) async -> PhysicalHIDClaimResult {
    await backend.releaseInputClaim(locationID: locationID)
  }

  public func reacquireInputClaim(locationID: UInt32) async -> PhysicalHIDClaimResult {
    await backend.reacquireInputClaim(locationID: locationID)
  }

  public func retryInputClaim(locationID: UInt32) async {
    await backend.retryInputClaim(locationID: locationID)
  }

  /// Delivers a connection's decoded element values, for a driver that parses them.
  public func routeElementValues(connection: HIDDeviceConnection) async {
    await backend.routeElementValues(connection: connection)
  }
}
