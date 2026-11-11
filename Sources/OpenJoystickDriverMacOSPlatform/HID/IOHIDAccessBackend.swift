import Foundation
package import OpenJoystickDriverKit

/// The HID access backend that delegates to a ``HIDDeviceStream``.
private final class IOHIDAccessBackend: HIDAccessBackend, Sendable {
  /// The stream that watches the devices and sends the reports.
  private let stream: HIDDeviceStream

  /// Creates the backend with the providers of the models that the stream matches.
  init(
    additionalProfileModels: @escaping @Sendable () -> [ControllerModelID],
    roleProfileModels: @escaping @Sendable () -> [ControllerModelID]
  ) {
    stream = HIDDeviceStream(
      additionalProfileModels: additionalProfileModels,
      roleProfileModels: roleProfileModels
    )
  }

  /// Starts the device event stream on the main actor.
  func deviceEvents() async -> AsyncStream<HIDDeviceEvent> {
    await MainActor.run { stream.deviceEvents() }
  }

  /// Returns the connections that the stream currently lists.
  func currentConnectionSnapshots() async -> [HIDDeviceConnectionSnapshot]? {
    await stream.currentConnectionSnapshots()
  }

  /// Sends an output report to the device at `address`.
  func setOutputReport(
    address: ControllerConnectionAddress,
    report: PhysicalHIDOutputReport
  ) -> PhysicalHIDReportResult<Void> {
    guard let locationID = address.locationID else { return .unavailable }
    return stream.setOutputReport(locationID: locationID, report: report)
  }

  /// Sends an output report to the device of `connection`.
  func setOutputReport(
    connection: HIDDeviceConnection,
    report: PhysicalHIDOutputReport
  ) async -> PhysicalHIDReportResult<Void> {
    await stream.setOutputReport(connection: connection, report: report)
  }

  /// Sends a feature report to the device at `address`.
  func setFeatureReport(
    address: ControllerConnectionAddress,
    report: PhysicalHIDOutputReport
  ) -> PhysicalHIDReportResult<Void> {
    guard let locationID = address.locationID else { return .unavailable }
    return stream.setFeatureReport(locationID: locationID, report: report)
  }

  /// Sends a feature report to the device of `connection`.
  func setFeatureReport(
    connection: HIDDeviceConnection,
    report: PhysicalHIDOutputReport
  ) async -> PhysicalHIDReportResult<Void> {
    await stream.setFeatureReport(connection: connection, report: report)
  }

  /// Reads a feature report from the device at `address`.
  func getFeatureReport(
    address: ControllerConnectionAddress,
    request: PhysicalHIDFeatureReadRequest
  ) -> PhysicalHIDReportResult<Data> {
    guard let locationID = address.locationID else { return .unavailable }
    return stream.getFeatureReport(locationID: locationID, request: request)
  }

  /// Reads a feature report from the device of `connection`.
  func getFeatureReport(
    connection: HIDDeviceConnection,
    request: PhysicalHIDFeatureReadRequest
  ) async -> PhysicalHIDReportResult<Data> {
    await stream.getFeatureReport(connection: connection, request: request)
  }

  /// Reads a feature report from the device of `connection` with a deadline, to probe its mode.
  func probeFeatureReport(
    connection: HIDDeviceConnection,
    request: PhysicalHIDFeatureReadRequest
  ) async -> PhysicalHIDReportResult<Data> {
    await stream.probeFeatureReport(connection: connection, request: request)
  }

  // Seizes and closes run on main, where the manager's run loop removes devices: a device that
  // detaches mid-open must not lose its plug-in on another thread, and `retryInputClaim` yields to
  // the main-confined stream continuation.
  /// Releases the input claim of the device at `address`; unavailable without a location ID.
  func releaseInputClaim(address: ControllerConnectionAddress) async -> PhysicalHIDClaimResult {
    guard let locationID = address.locationID else { return .unavailable }
    return await MainActor.run { stream.releaseInputClaim(locationID: locationID) }
  }

  /// Takes the input claim of the device at `address` back; unavailable without a location ID.
  func reacquireInputClaim(address: ControllerConnectionAddress) async -> PhysicalHIDClaimResult {
    guard let locationID = address.locationID else { return .unavailable }
    return await MainActor.run { stream.reacquireInputClaim(locationID: locationID) }
  }

  /// Retries the input claim of the device at `address`.
  func retryInputClaim(address: ControllerConnectionAddress) async {
    guard let locationID = address.locationID else { return }
    await MainActor.run { stream.retryInputClaim(locationID: locationID) }
  }

  /// Routes the element values of the device of `connection`.
  func routeElementValues(connection: HIDDeviceConnection) async {
    await stream.routeElementValues(connection: connection)
  }

  /// Re-evaluates the input ownership of the devices of `models`.
  func reevaluateOwnership(of models: Set<ControllerModelID>) async -> Set<UUID> {
    await MainActor.run { stream.reevaluateOwnership(of: models) }
  }
}

/// The IOHID-backed HID access of the application.
package func makeIOHIDAccessBackend(
  additionalProfileModels: @escaping @Sendable () -> [ControllerModelID],
  roleProfileModels: @escaping @Sendable () -> [ControllerModelID]
) -> any HIDAccessBackend {
  IOHIDAccessBackend(
    additionalProfileModels: additionalProfileModels,
    roleProfileModels: roleProfileModels
  )
}
