import Foundation

@testable import OpenJoystickDriverKit

actor ClaimRecordingHIDAccessBackend: HIDAccessBackend {
  private var released: [UInt32] = []
  private var reacquired: [UInt32] = []
  private var retried: [UInt32] = []
  private var elementValueRoutes: [UInt32] = []

  func releasedLocations() -> [UInt32] { released }
  func elementValueLocations() -> [UInt32] { elementValueRoutes }
  func reacquiredLocations() -> [UInt32] { reacquired }
  func retriedLocations() -> [UInt32] { retried }

  func deviceEvents() -> AsyncStream<HIDDeviceEvent> { AsyncStream { _ in } }

  func currentConnectionSnapshots() -> [HIDDeviceConnectionSnapshot]? { [] }

  func setOutputReport(
    locationID _: UInt32,
    report _: PhysicalHIDOutputReport
  ) -> PhysicalHIDReportResult<Void> { .unavailable }

  func setOutputReport(
    connection _: HIDDeviceConnection,
    report _: PhysicalHIDOutputReport
  ) -> PhysicalHIDReportResult<Void> { .unavailable }

  func setFeatureReport(
    locationID _: UInt32,
    report _: PhysicalHIDOutputReport
  ) -> PhysicalHIDReportResult<Void> { .unavailable }

  func setFeatureReport(
    connection _: HIDDeviceConnection,
    report _: PhysicalHIDOutputReport
  ) -> PhysicalHIDReportResult<Void> { .unavailable }

  func getFeatureReport(
    locationID _: UInt32,
    request _: PhysicalHIDFeatureReadRequest
  ) -> PhysicalHIDReportResult<Data> { .unavailable }

  func getFeatureReport(
    connection _: HIDDeviceConnection,
    request _: PhysicalHIDFeatureReadRequest
  ) -> PhysicalHIDReportResult<Data> { .unavailable }

  func releaseInputClaim(locationID: UInt32) -> PhysicalHIDClaimResult {
    released.append(locationID)
    return .released
  }

  func reacquireInputClaim(locationID: UInt32) -> PhysicalHIDClaimResult {
    reacquired.append(locationID)
    return .reacquired
  }

  func retryInputClaim(locationID: UInt32) { retried.append(locationID) }

  func routeElementValues(connection: HIDDeviceConnection) {
    elementValueRoutes.append(connection.routingLocationID)
  }
}
