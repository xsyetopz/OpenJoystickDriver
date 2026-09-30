import Foundation

@testable import OpenJoystickDriverKit

actor RecoveryHIDBackend: HIDAccessBackend {
  func deviceEvents() -> AsyncStream<HIDDeviceEvent> { AsyncStream { $0.finish() } }

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

  func releaseInputClaim(locationID _: UInt32) -> PhysicalHIDClaimResult { .unavailable }

  func reacquireInputClaim(locationID _: UInt32) -> PhysicalHIDClaimResult { .unavailable }

  func retryInputClaim(locationID _: UInt32) {}

  func routeElementValues(connection _: HIDDeviceConnection) {}
}
