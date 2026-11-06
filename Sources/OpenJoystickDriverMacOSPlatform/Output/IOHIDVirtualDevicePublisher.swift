import Foundation
import IOKit
import IOKit.hid
import OpenJoystickDriverKit
import Security

/// Publishes virtual gamepads as `IOHIDUserDevice`s.
///
/// Creating one needs the virtual-device entitlement.
package struct IOHIDVirtualDevicePublisher: VirtualHIDDevicePublisher {
  /// The entitlement that creating an `IOHIDUserDevice` needs.
  static let requiredVirtualDeviceEntitlement = "com.apple.developer.hid.virtual.device"

  /// Explains a failed create by the permission that is missing.
  private let access: any AccessControlSystem

  /// Throws `missingEntitlement` when the process lacks the virtual-device entitlement.
  package init() throws {
    guard Self.hasEntitlement(Self.requiredVirtualDeviceEntitlement) else {
      throw UserSpaceOutputDispatcher.CreationError.missingEntitlement(
        Self.requiredVirtualDeviceEntitlement
      )
    }
    access = MacOSAccessControlSystem()
  }

  /// Creates an unpublished virtual device for the controller `identifier` from `profile` and
  /// `format`.
  ///
  /// - Throws: ``UserSpaceOutputDispatcher/CreationError`` that names the missing permission, or
  ///   `createFailed` when IOKit refuses the device.
  package func createDevice(
    for identifier: LogicalControllerID,
    profile: VirtualDeviceProfile,
    format: any VirtualGamepadReportFormat
  ) throws -> any VirtualDeviceBackend {
    let properties = Self.deviceProperties(profile: profile, format: format, identifier: identifier)
    let device = IOHIDUserDeviceCreateWithProperties(
      kCFAllocatorDefault,
      properties as CFDictionary,
      Self.deviceCreationOptions
    )
    // IOHIDUserDevice.h requires only the virtual-device entitlement, so permissions are not
    // checked up front; they only explain a failed create.
    guard let device else {
      throw Self.creationFailure(
        inputRead: access.inputReadAccessState(),
        inputInject: access.inputInjectAccessState()
      )
    }
    let model = identifier.hardware.model
    let queue = DispatchQueue(
      label: "com.openjoystickdriver.iokit-hid.\(model.vendorID).\(model.productID)"
    )
    return IOHIDVirtualDeviceBackend(device: device, queue: queue)
  }

  /// Deferred creation until `IOHIDUserDeviceActivate` avoids dropped get/set report calls.
  static let deviceCreationOptions = IOOptionBits(IOHIDUserDeviceOptions.createOnActivate.rawValue)

  /// Returns the error to throw for a failed creation: the permission that is not granted, or
  /// `createFailed` when both are.
  static func creationFailure(
    inputRead: PermissionManager.AccessState,
    inputInject: PermissionManager.AccessState
  ) -> UserSpaceOutputDispatcher.CreationError {
    if inputRead != .granted { return .inputReadDenied }
    if inputInject != .granted { return .inputInjectDenied }
    return .createFailed
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
    identifier: LogicalControllerID
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

  /// Returns the size of the report buffer, one byte more than the payload when the report has an
  /// ID.
  static func reportBufferSize(payloadSize: Int, reportID: UInt8?) -> Int {
    reportID == nil ? payloadSize : payloadSize + 1
  }

  /// Tells whether this process holds the boolean entitlement `entitlement`.
  static func hasEntitlement(_ entitlement: String) -> Bool {
    guard let task = SecTaskCreateFromSelf(nil),
      let value = SecTaskCopyValueForEntitlement(task, entitlement as CFString, nil),
      CFGetTypeID(value) == CFBooleanGetTypeID()
    else { return false }
    return CFBooleanGetValue(unsafeDowncast(value, to: CFBoolean.self))
  }
}
