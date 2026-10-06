import Darwin
import Foundation
import IOKit
import IOKit.hid
import Security

extension UserSpaceOutputDispatcher {
  internal func createEntry(for identifier: DeviceIdentifier) async throws -> Entry {
    guard lifecycle.isOpen else { throw CancellationError() }
    if let testBackendFactory {
      let backend = try await testBackendFactory(identifier)
      guard lifecycle.isOpen else {
        backend.close()
        throw CancellationError()
      }
      return Entry(backend: backend, inputReportState: UserSpaceInputReportState(format: format))
    }
    return try createIOKitEntry(for: identifier)
  }

  internal func hostReportHandler(
    identifier: DeviceIdentifier,
    input: UserSpaceInputReportState,
    sender: UserSpaceReportSender
  ) -> UserSpaceHostReportHandler {
    let isOpen: @Sendable () -> Bool = { [lifecycle] in lifecycle.isOpen }
    return UserSpaceHostReportHandler(
      identifier: identifier,
      input: input,
      sender: sender,
      isOpen: isOpen,
      onOutput: onOutputCommand
    ) { [weak self] status in self?.registryLock.withLock { self?._lastRumbleStatus = status } }
  }

  static func creationFailure(
    inputMonitoring: PermissionManager.AccessState =
      PermissionManager.currentInputMonitoringAccessState(),
    accessibility: PermissionManager.AccessState =
      PermissionManager.currentAccessibilityAccessState()
  ) -> CreationError {
    if inputMonitoring != .granted { return .inputMonitoringDenied }
    if accessibility != .granted { return .accessibilityDenied }
    return .createFailed
  }

  /// Deferred creation until `IOHIDUserDeviceActivate` avoids dropped get/set report calls.
  static let deviceCreationOptions = IOOptionBits(IOHIDUserDeviceOptions.createOnActivate.rawValue)

  internal func createIOKitEntry(for identifier: DeviceIdentifier) throws -> Entry {
    let properties = Self.deviceProperties(profile: profile, format: format, identifier: identifier)
    let device = IOHIDUserDeviceCreateWithProperties(
      kCFAllocatorDefault,
      properties as CFDictionary,
      Self.deviceCreationOptions
    )
    // IOHIDUserDevice.h requires only the virtual-device entitlement, so permissions are not
    // checked up front; they only explain a failed create.
    guard let device else { throw Self.creationFailure() }
    guard lifecycle.isOpen else {
      IOHIDUserDeviceCancel(device)
      throw CancellationError()
    }

    let identity = identifier.controllerIdentity
    let queue = DispatchQueue(
      label: "com.openjoystickdriver.iokit-hid.\(identity.vendorID).\(identity.productID)"
    )
    let inputReportState = UserSpaceInputReportState(format: format)
    let entry = Entry(
      backend: IOHIDBackend(device: device, queue: queue),
      inputReportState: inputReportState
    )
    let handler = hostReportHandler(
      identifier: identifier,
      input: inputReportState,
      sender: entry.sender
    )
    IOHIDUserDeviceRegisterGetReportBlock(device) { type, reportID, report, reportLength in
      do {
        guard let identifier = UInt32(exactly: reportID) else {
          throw VirtualHostReportError.malformed
        }
        let bytes = try handler.getReport(
          type: UserSpaceHostReportHandler.reportType(type),
          reportID: identifier,
          maxSize: Int(reportLength.pointee)
        )
        for (index, byte) in bytes.enumerated() { report[index] = byte }
        reportLength.pointee = bytes.count
        return kIOReturnSuccess
      } catch {
        reportLength.pointee = 0
        return UserSpaceHostReportHandler.ioKitError(error)
      }
    }
    IOHIDUserDeviceRegisterSetReportBlock(device) { type, reportID, report, reportLength in
      do {
        guard reportLength >= 0 else { throw VirtualHostReportError.malformed }
        let bytes = Array(UnsafeBufferPointer(start: report, count: Int(reportLength)))
        _ = try handler.setReport(
          type: UserSpaceHostReportHandler.reportType(type),
          reportID: reportID,
          bytes: bytes
        )
        return kIOReturnSuccess
      } catch { return UserSpaceHostReportHandler.ioKitError(error) }
    }
    IOHIDUserDeviceSetDispatchQueue(device, queue)
    IOHIDUserDeviceActivate(device)
    print("[UserSpaceOutputDispatcher] Created IOKit virtual device for \(identifier)")
    return entry
  }

  /// IOHID `Transport` string HIDAPI matches (`kIOHIDTransportBluetoothValue` prefix).
  static func ioHIDTransportValue(for profile: VirtualDeviceProfile) -> String {
    switch profile.transport {
    case kIOHIDTransportBluetoothValue, kIOHIDTransportBluetoothLowEnergyValue:
      kIOHIDTransportBluetoothValue
    default: kIOHIDTransportUSBValue
    }
  }

  /// The complete published property dictionary for the one `IOHIDUserDeviceCreateWithProperties`
  /// call: identity, report sizes, location, and the GenericDesktop/GamePad primary usage and
  /// usage pairs.
  static func deviceProperties(
    profile: VirtualDeviceProfile,
    format: any VirtualGamepadReportFormat,
    identifier: DeviceIdentifier
  ) -> [String: Any] {
    let primaryUsage = Int(kHIDUsage_GD_GamePad)
    var properties: [String: Any] = [
      kIOHIDReportDescriptorKey as String: Data(format.descriptor),
      kIOHIDVendorIDKey as String: Int(profile.vendorID),
      kIOHIDProductIDKey as String: Int(profile.productID),
      kIOHIDVersionNumberKey as String: profile.versionNumber,
      kIOHIDProductKey as String: profile.productName,
      kIOHIDManufacturerKey as String: profile.manufacturer,
      kIOHIDSerialNumberKey as String: UserSpaceVirtualDeviceConstants.serialNumber(
        for: identifier
      ), kIOHIDTransportKey as String: ioHIDTransportValue(for: profile),
      kIOHIDMaxInputReportSizeKey as String: reportBufferSize(
        payloadSize: format.inputReportPayloadSize,
        reportID: format.inputReportID
      ), kIOHIDPrimaryUsagePageKey as String: Int(kHIDPage_GenericDesktop),
      kIOHIDPrimaryUsageKey as String: primaryUsage,
      kIOHIDDeviceUsagePairsKey as String: [
        [
          kIOHIDDeviceUsagePageKey as String: Int(kHIDPage_GenericDesktop),
          kIOHIDDeviceUsageKey as String: primaryUsage,
        ]
      ],
    ]
    if let outputSize = format.outputReportPayloadSize {
      properties[kIOHIDMaxOutputReportSizeKey as String] = reportBufferSize(
        payloadSize: outputSize,
        reportID: format.outputReportID
      )
    }
    properties[kIOHIDLocationIDKey as String] = Int64(
      UserSpaceVirtualDeviceConstants.locationID(for: identifier)
    )
    return properties
  }

  internal static func reportBufferSize(payloadSize: Int, reportID: UInt8?) -> Int {
    reportID == nil ? payloadSize : payloadSize + 1
  }

  internal static func hasEntitlement(_ entitlement: String) -> Bool {
    guard let task = SecTaskCreateFromSelf(nil),
      let value = SecTaskCopyValueForEntitlement(task, entitlement as CFString, nil),
      CFGetTypeID(value) == CFBooleanGetTypeID()
    else { return false }
    return CFBooleanGetValue(unsafeDowncast(value, to: CFBoolean.self))
  }
}
