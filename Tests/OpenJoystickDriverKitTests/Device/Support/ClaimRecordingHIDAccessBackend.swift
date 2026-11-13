import Foundation

@testable import OpenJoystickDriverKit

actor ClaimRecordingHIDAccessBackend: HIDAccessBackend {
  private var released: [UInt32] = []
  private var reacquired: [UInt32] = []
  private var retried: [UInt32] = []
  private var elementValueRoutes: [UInt32] = []
  private var openHandles: Set<UInt32> = []

  /// Whether a test marked the device handle at `locationID` open and nothing closed it since.
  func hasOpenHandle(at locationID: UInt32) -> Bool { openHandles.contains(locationID) }

  /// Marks the device handle at `locationID` open, as the platform backend leaves it on admission.
  func openHandle(at locationID: UInt32) { openHandles.insert(locationID) }

  /// The connection an ownership re-evaluation admits again; nil admits none.
  private var reevaluationAdmits: HIDDeviceConnection?
  private var snapshots: [HIDDeviceConnectionSnapshot] = []

  /// Makes the next ownership re-evaluation open the device handle at the location of `connection`
  /// and list it as the only connection, as the platform backend does.
  func admitOnReevaluation(_ connection: HIDDeviceConnection) { reevaluationAdmits = connection }

  func reevaluateOwnership(of _: Set<ControllerModelID>) -> Set<UUID> {
    guard let connection = reevaluationAdmits else { return [] }
    reevaluationAdmits = nil
    snapshots = [HIDDeviceConnectionSnapshot(connection: connection, ownership: .exclusive)]
    if let locationID = connection.routingAddress.locationID { openHandles.insert(locationID) }
    return [connection.connectionID]
  }

  func closeDeviceHandles(address: ControllerConnectionAddress) -> PhysicalHIDClaimResult {
    guard let locationID = address.locationID, openHandles.remove(locationID) != nil else {
      return .unavailable
    }
    return .released
  }

  func reopenDeviceHandles(address: ControllerConnectionAddress) -> PhysicalHIDClaimResult {
    guard let locationID = address.locationID else { return .unavailable }
    openHandles.insert(locationID)
    return .reacquired
  }

  func releasedLocations() -> [UInt32] { released }
  func elementValueLocations() -> [UInt32] { elementValueRoutes }
  func reacquiredLocations() -> [UInt32] { reacquired }
  func retriedLocations() -> [UInt32] { retried }

  func deviceEvents() -> AsyncStream<HIDDeviceEvent> { AsyncStream { _ in } }

  func currentConnectionSnapshots() -> [HIDDeviceConnectionSnapshot]? { snapshots }

  func setOutputReport(
    address _: ControllerConnectionAddress,
    report _: PhysicalHIDOutputReport
  ) -> PhysicalHIDReportResult<Void> { .unavailable }

  func setOutputReport(
    connection _: HIDDeviceConnection,
    report _: PhysicalHIDOutputReport
  ) -> PhysicalHIDReportResult<Void> { .unavailable }

  func setFeatureReport(
    address _: ControllerConnectionAddress,
    report _: PhysicalHIDOutputReport
  ) -> PhysicalHIDReportResult<Void> { .unavailable }

  func setFeatureReport(
    connection _: HIDDeviceConnection,
    report _: PhysicalHIDOutputReport
  ) -> PhysicalHIDReportResult<Void> { .unavailable }

  func getFeatureReport(
    address _: ControllerConnectionAddress,
    request _: PhysicalHIDFeatureReadRequest
  ) -> PhysicalHIDReportResult<Data> { .unavailable }

  func getFeatureReport(
    connection _: HIDDeviceConnection,
    request _: PhysicalHIDFeatureReadRequest
  ) -> PhysicalHIDReportResult<Data> { .unavailable }

  func releaseInputClaim(address: ControllerConnectionAddress) -> PhysicalHIDClaimResult {
    released.append(contentsOf: [address.locationID].compactMap { $0 })
    return .released
  }

  func reacquireInputClaim(address: ControllerConnectionAddress) -> PhysicalHIDClaimResult {
    reacquired.append(contentsOf: [address.locationID].compactMap { $0 })
    return .reacquired
  }

  func retryInputClaim(address: ControllerConnectionAddress) {
    retried.append(contentsOf: [address.locationID].compactMap { $0 })
  }

  func routeElementValues(connection: HIDDeviceConnection) {
    elementValueRoutes.append(contentsOf: [connection.routingAddress.locationID].compactMap { $0 })
  }
}
