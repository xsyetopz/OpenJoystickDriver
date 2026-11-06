import Foundation

/// Reads a probe's feature report from one HID connection.
///
/// It can only read.
struct HIDConnectionModeProbeReader: ControllerModeProbeReader {
  /// The manager that reads the report.
  let hidManager: HIDManager
  /// The connection to read from.
  let connection: HIDDeviceConnection

  /// Reads the feature report that `request` asks for from the connection.
  func readFeatureReport(
    _ request: PhysicalHIDFeatureReadRequest
  ) async -> PhysicalHIDReportResult<Data> {
    await hidManager.probeFeatureReport(connection: connection, request: request)
  }
}

extension DeviceManager {
  /// The mode a connected model's match keys select.
  ///
  /// A record without modes costs no read.
  func selectedHIDMode(
    for connection: HIDDeviceConnection,
    device: PhysicalDevice,
    vendorID: UInt16,
    productID: UInt16
  ) async -> ControllerModeSelection {
    await protocolDriverRegistry.selectMode(
      of: ControllerModelID(vendorID: vendorID, productID: productID),
      backend: connection.accessBackend,
      reader: HIDConnectionModeProbeReader(hidManager: hidManager, connection: connection),
      device: device
    )
  }
}

/// The probe reader of a route that cannot read feature reports; the selector never asks it,
/// because it ends the selection at the default mode before any probe of a non-IOHID route.
struct UnreadableModeProbeReader: ControllerModeProbeReader {
  /// Reports every feature read as unavailable.
  func readFeatureReport(
    _ request: PhysicalHIDFeatureReadRequest
  ) async -> PhysicalHIDReportResult<Data> {  // swiftlint:disable:this async_without_await
    .unavailable
  }
}
