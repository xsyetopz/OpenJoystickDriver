import Darwin
import Foundation
import IOKit
import IOKit.hid
import Security

extension UserSpaceOutputDispatcher {
  /// Creates the native device for `identifier`, starting from `seed` when it replaces a lost
  /// device.
  internal func createEntry(
    for identifier: DeviceIdentifier,
    seed: UserSpaceInputReportState.Snapshot? = nil
  ) async throws -> Entry {
    guard lifecycle.isOpen else { throw CancellationError() }
    if let devicePublisher,
      let entry = try await createPublishedEntry(for: identifier, devicePublisher, seed: seed)
    {
      return entry
    }
    if let testBackendFactory {
      let backend = try await testBackendFactory(identifier)
      guard lifecycle.isOpen else {
        backend.close()
        throw CancellationError()
      }
      return Entry(
        backend: backend,
        inputReportState: UserSpaceInputReportState(format: format, seed: seed)
      )
    }
    return try createIOKitEntry(for: identifier, seed: seed)
  }

  /// Returns nil when the publisher declines, so the caller falls back to `IOHIDUserDevice`.
  internal func createPublishedEntry(
    for identifier: DeviceIdentifier,
    _ publisher: any VirtualHIDDevicePublisher,
    seed: UserSpaceInputReportState.Snapshot? = nil
  ) async throws -> Entry? {
    let inputReportState = UserSpaceInputReportState(format: format, seed: seed)
    let entry = Entry(inputReportState: inputReportState)
    let handler = hostReportHandler(
      identifier: identifier,
      input: inputReportState,
      sender: entry.sender
    )
    let description = Self.deviceDescription(
      profile: profile,
      format: format,
      identifier: identifier
    )
    guard
      let backend = await publisher.publish(
        description,
        hostReports: VirtualHIDHostReports(handler: handler),
        onLost: { [weak self, weak entry] in
          guard let self, let entry else { return }
          Task { await self.replaceLostEntry(for: identifier, lost: entry) }
        }
      )
    else {
      await entry.close()
      return nil
    }
    guard lifecycle.isOpen else {
      backend.close()
      await entry.close()
      throw CancellationError()
    }
    entry.sender.attach(backend)
    print("[UserSpaceOutputDispatcher] Created published virtual device for \(identifier)")
    return entry
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

  internal func createIOKitEntry(
    for identifier: DeviceIdentifier,
    seed: UserSpaceInputReportState.Snapshot? = nil
  ) throws -> Entry {
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
    let inputReportState = UserSpaceInputReportState(format: format, seed: seed)
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

  /// The identity, descriptor, transport, location, and GenericDesktop/GamePad primary usage that
  /// every provider publishes for one device.
  static func deviceDescription(
    profile: VirtualDeviceProfile,
    format: any VirtualGamepadReportFormat,
    identifier: DeviceIdentifier
  ) -> VirtualHIDDeviceDescription {
    VirtualHIDDeviceDescription(
      reportDescriptor: format.descriptor,
      vendorID: profile.vendorID,
      productID: profile.productID,
      versionNumber: profile.versionNumber,
      manufacturer: profile.manufacturer,
      product: profile.productName,
      serialNumber: UserSpaceVirtualDeviceConstants.serialNumber(for: identifier),
      transport: ioHIDTransportValue(for: profile),
      locationID: UserSpaceVirtualDeviceConstants.locationID(for: identifier),
      primaryUsagePage: UInt32(kHIDPage_GenericDesktop),
      primaryUsage: UInt32(kHIDUsage_GD_GamePad)
    )
  }

  /// The complete published property dictionary for the one `IOHIDUserDeviceCreateWithProperties`
  /// call: identity, report sizes, location, and the GenericDesktop/GamePad primary usage and
  /// usage pairs.
  static func deviceProperties(
    profile: VirtualDeviceProfile,
    format: any VirtualGamepadReportFormat,
    identifier: DeviceIdentifier
  ) -> [String: Any] {
    let device = deviceDescription(profile: profile, format: format, identifier: identifier)
    let usagePage = Int(device.primaryUsagePage)
    let usage = Int(device.primaryUsage)
    var properties: [String: Any] = [
      kIOHIDReportDescriptorKey as String: Data(device.reportDescriptor),
      kIOHIDVendorIDKey as String: Int(device.vendorID),
      kIOHIDProductIDKey as String: Int(device.productID),
      kIOHIDVersionNumberKey as String: device.versionNumber,
      kIOHIDProductKey as String: device.product,
      kIOHIDManufacturerKey as String: device.manufacturer,
      kIOHIDSerialNumberKey as String: device.serialNumber,
      kIOHIDTransportKey as String: device.transport,
      kIOHIDMaxInputReportSizeKey as String: reportBufferSize(
        payloadSize: format.inputReportPayloadSize,
        reportID: format.inputReportID
      ), kIOHIDPrimaryUsagePageKey as String: usagePage,
      kIOHIDPrimaryUsageKey as String: usage,
      kIOHIDDeviceUsagePairsKey as String: [
        [kIOHIDDeviceUsagePageKey as String: usagePage, kIOHIDDeviceUsageKey as String: usage]
      ],
    ]
    if let outputSize = format.outputReportPayloadSize {
      properties[kIOHIDMaxOutputReportSizeKey as String] = reportBufferSize(
        payloadSize: outputSize,
        reportID: format.outputReportID
      )
    }
    properties[kIOHIDLocationIDKey as String] = Int64(device.locationID)
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
