package import Foundation
import GameController
import IOKit
import IOKit.hid
package import OpenJoystickDriverKit

extension HIDDeviceStream {
  package func setOutputReport(
    locationID: UInt32,
    report: PhysicalHIDOutputReport
  ) -> PhysicalHIDReportResult<Void> {
    setReport(locationID: locationID, report: report, type: kIOHIDReportTypeOutput, label: "Output")
  }

  /// Sends an output report to the device of `connection`, on the main actor.
  package func setOutputReport(
    connection: HIDDeviceConnection,
    report: PhysicalHIDOutputReport
  ) async -> PhysicalHIDReportResult<Void> {
    await MainActor.run {
      setReport(
        connection: connection,
        report: report,
        type: kIOHIDReportTypeOutput,
        label: "Output"
      )
    }
  }

  /// Sends a feature report to the devices at `locationID`.
  package func setFeatureReport(
    locationID: UInt32,
    report: PhysicalHIDOutputReport
  ) -> PhysicalHIDReportResult<Void> {
    setReport(
      locationID: locationID,
      report: report,
      type: kIOHIDReportTypeFeature,
      label: "Feature"
    )
  }

  /// Sends a feature report to the device of `connection`, on the main actor.
  package func setFeatureReport(
    connection: HIDDeviceConnection,
    report: PhysicalHIDOutputReport
  ) async -> PhysicalHIDReportResult<Void> {
    await MainActor.run {
      setReport(
        connection: connection,
        report: report,
        type: kIOHIDReportTypeFeature,
        label: "Feature"
      )
    }
  }

  /// Reads the feature report that `request` names from the devices at `locationID`.
  package func getFeatureReport(
    locationID: UInt32,

    request: PhysicalHIDFeatureReadRequest
  ) -> PhysicalHIDReportResult<Data> {
    guard eventAdapter.acceptsFeedback(locationID: locationID) else { return .unavailable }
    let devices = seizeLock.withLock { seizedByLocation[locationID] ?? [] }
    guard !devices.isEmpty else { return .unavailable }

    var lastResult = kIOReturnNotFound
    for device in devices {
      var bytes = [UInt8](repeating: 0, count: request.length)

      var reportLength = request.length
      let result = bytes.withUnsafeMutableBufferPointer { pointer in
        guard let baseAddress = pointer.baseAddress else { return kIOReturnBadArgument }
        return unsafe IOHIDDeviceGetReport(
          device,
          kIOHIDReportTypeFeature,
          CFIndex(request.reportID),
          baseAddress,
          &reportLength
        )
      }
      if result == kIOReturnSuccess { return .success(Data(bytes.prefix(reportLength))) }
      lastResult = result
    }
    print(
      "[HIDDeviceStream] Feature report read failed for loc=\(locationID)"
        + " report=0x\(unsafe String(format: "%02X", request.reportID)) kr=\(lastResult)"
    )
    return .failed(.init(ioReturn: lastResult))
  }

  /// Replaces the seize of each device at a location with a shared open, so another client can
  /// open the devices while input keeps flowing here.

  /// Sends `report` of the given IOHID report `type` to the devices at `locationID`.
  ///
  /// `label` names the report type in the failure text. The result is unavailable when the location
  /// has no seized device or does not accept feedback.
  private func setReport(
    locationID: UInt32,
    report: PhysicalHIDOutputReport,
    type: IOHIDReportType,
    label: String
  ) -> PhysicalHIDReportResult<Void> {
    guard eventAdapter.acceptsFeedback(locationID: locationID) else { return .unavailable }
    let devices = seizeLock.withLock { seizedByLocation[locationID] ?? [] }
    guard !devices.isEmpty else { return .unavailable }

    var lastResult = kIOReturnNotFound
    for device in devices {
      var bytes = report.bytes
      let reportLength = bytes.count
      let result = bytes.withUnsafeMutableBufferPointer { pointer in
        guard let baseAddress = pointer.baseAddress else { return kIOReturnBadArgument }
        return unsafe IOHIDDeviceSetReport(
          device,
          type,
          CFIndex(report.reportID),
          baseAddress,
          reportLength
        )
      }
      if result == kIOReturnSuccess { return .success(()) }
      lastResult = result
    }
    print(
      "[HIDDeviceStream] \(label) report failed for loc=\(locationID)"
        + " report=0x\(unsafe String(format: "%02X", report.reportID)) kr=\(lastResult)"
    )
    return .failed(.init(ioReturn: lastResult))
  }

  /// Reads a feature report only from the exact connection lifetime, never a sibling at its
  /// location.
  ///
  /// It waits for the device on the main actor, as the startup reads always have.
  package func getFeatureReport(
    connection: HIDDeviceConnection,
    request: PhysicalHIDFeatureReadRequest
  ) async -> PhysicalHIDReportResult<Data> {
    await MainActor.run {
      guard let device = exactDevice(for: connection, type: kIOHIDReportTypeFeature, reads: true)
      else { return .unavailable }
      return Self.readFeatureReport(device, request: request)
    }
  }

  /// Reads a feature report for a mode probe, off the main actor and bounded by `timeout`.
  ///
  /// While an earlier probe read of the same connection has not returned, it fails with
  /// `kIOReturnBusy` instead of reading.
  func probeFeatureReport(
    connection: HIDDeviceConnection,
    request: PhysicalHIDFeatureReadRequest,
    timeout: TimeInterval = 2
  ) async -> PhysicalHIDReportResult<Data> {
    let device = await MainActor.run {
      exactDevice(for: connection, type: kIOHIDReportTypeFeature, reads: true).map(
        UncheckedSendableDevice.init
      )
    }
    guard let device else { return .unavailable }
    return await boundedReads.run(key: connection.connectionID, timeout: timeout) {
      Self.readFeatureReport(device.device, request: request)
    }
  }

  /// Reads the feature report that `request` names from `device`.
  private static func readFeatureReport(
    _ device: IOHIDDevice,
    request: PhysicalHIDFeatureReadRequest
  ) -> PhysicalHIDReportResult<Data> {
    var bytes = [UInt8](repeating: 0, count: request.length)
    var reportLength = request.length
    let result = bytes.withUnsafeMutableBufferPointer { pointer in
      guard let baseAddress = pointer.baseAddress else { return kIOReturnBadArgument }
      return unsafe IOHIDDeviceGetReport(
        device,
        kIOHIDReportTypeFeature,
        CFIndex(request.reportID),
        baseAddress,
        &reportLength
      )
    }
    guard result == kIOReturnSuccess else { return .failed(.init(ioReturn: result)) }
    return .success(Data(bytes.prefix(reportLength)))
  }

  /// Sends `report` of the given IOHID report `type` to the device of `connection`.
  @MainActor
  private func setReport(
    connection: HIDDeviceConnection,
    report: PhysicalHIDOutputReport,
    type: IOHIDReportType,
    label: String
  ) -> PhysicalHIDReportResult<Void> {
    guard let device = exactDevice(for: connection, type: type) else { return .unavailable }
    var bytes = report.bytes
    let reportLength = bytes.count
    let result = bytes.withUnsafeMutableBufferPointer { pointer in
      guard let baseAddress = pointer.baseAddress else { return kIOReturnBadArgument }
      return unsafe IOHIDDeviceSetReport(
        device,
        type,
        CFIndex(report.reportID),
        baseAddress,
        reportLength
      )
    }
    guard result == kIOReturnSuccess else {
      print(
        "[HIDDeviceStream] \(label) report failed for exact connection "
          + "report=0x\(unsafe String(format: "%02X", report.reportID)) kr=\(result)"
      )
      return .failed(.init(ioReturn: result))
    }
    return .success(())
  }

  /// The device object of an exact connection lifetime that accepts a `type` report, read when
  /// `reads` is set and written otherwise.
  @MainActor
  private func exactDevice(
    for connection: HIDDeviceConnection,
    type: IOHIDReportType,
    reads: Bool = false
  ) -> IOHIDDevice? {
    guard let manager, let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>,
      let deviceID = seizeLock.withLock({
        connectionsByDeviceID.first { $0.value == connection }?.key
      }), let device = devices.first(where: { trackingID(for: $0) == deviceID }),
      eventAdapter.acceptsInput(deviceID: deviceID),
      seizeLock.withLock({
        // A native device is never seized: an output report DeviceManager's native allowance
        // permits, or a feature read it makes, goes through its shared open; every other write
        // needs the seize.
        if connection.physicalDevice.nativePassThrough {
          let permitted = reads ? type == kIOHIDReportTypeFeature : type == kIOHIDReportTypeOutput
          return unsafe permitted && sharedOpenByDeviceID[deviceID] != nil
        }
        return seizedByLocation[connection.ioKitLocationID]?.contains(where: {
          CFEqual($0, device)
        }) == true
      })
    else { return nil }
    return device
  }
}

/// An `IOHIDDevice` handed to the queue that reads it.
///
/// IOKit device calls are thread-safe.
private struct UncheckedSendableDevice: @unchecked Sendable {
  /// The device, wrapped so that it can cross concurrency domains.
  let device: IOHIDDevice
}
