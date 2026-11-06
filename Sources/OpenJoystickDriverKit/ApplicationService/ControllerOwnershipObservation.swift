import Foundation

/// How OJD owns or observes the physical controller input path.
public enum ControllerOwnershipObservation: String, Codable, CaseIterable, Equatable, Sendable {
  /// OJD reads the controller's HID interface exclusively.
  case exclusiveHID = "ExclusiveHID"
  /// OJD reads the controller over USB exclusively.
  case exclusiveRawUSB = "ExclusiveRawUSB"
  /// The OJD driver extension owns the controller's USB interface.
  case extensionOwnedUSB = "ExtensionOwnedUSB"
  /// macOS lists the controller as a HID device that OJD does not own.
  case systemHIDVisible = "SystemHIDVisible"
  /// macOS serves the controller as a native gamepad; OJD only observes its shared input.
  case systemGamepad = "SystemGamepad"
  /// Another program's virtual device stands in front of the controller.
  case upstreamVirtualDevice = "UpstreamVirtualDevice"
  /// OJD could not tell who owns the input path.
  case unknown = "Unknown"

  /// Whether the system serves the controller itself, so OJD publishes no virtual device for it.
  ///
  /// The decision depends on who serves the input, not on which OS does.
  public var isServedBySystem: Bool {
    switch self {
    case .systemGamepad, .systemHIDVisible: true
    case .exclusiveHID, .exclusiveRawUSB, .extensionOwnedUSB, .upstreamVirtualDevice, .unknown:
      false
    }
  }
}

/// The duplicate-device concern associated with the physical ownership observation.
public enum DuplicateExposureRisk: String, Codable, Equatable, Sendable {
  /// No duplicate device is visible.
  case none = "None"
  /// macOS's HID device for the controller is visible next to OJD's virtual device.
  case systemHIDVisible = "SystemHIDVisible"
  /// Another program's virtual device for the controller is visible.
  case upstreamVirtualDevice = "UpstreamVirtualDevice"
  /// OJD serves the controller, and GameController also lists it as a pad with no input.
  case systemGameController = "SystemGameController"
  /// The ownership is unknown, so duplicates cannot be ruled out.
  case unknownOwnership = "UnknownOwnership"
}

extension DuplicateExposureRisk {
  /// The duplicate-device concern of one physical ownership observation.
  public init(observation: ControllerOwnershipObservation) {
    self =
      switch observation {
      // OJD never publishes for a native gamepad, so games see only Apple's device.
      case .exclusiveHID, .exclusiveRawUSB, .extensionOwnedUSB, .systemGamepad: .none
      case .systemHIDVisible: .systemHIDVisible
      case .upstreamVirtualDevice: .upstreamVirtualDevice
      case .unknown: .unknownOwnership
      }
  }
}
