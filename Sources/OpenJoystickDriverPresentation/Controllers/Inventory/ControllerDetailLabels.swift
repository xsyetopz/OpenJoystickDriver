import Foundation
import OpenJoystickDriverKit

/// The localization key of each state the Controllers detail names.
///
/// Every switch lists all cases, so an added case fails to compile until it has text.
enum ControllerDetailLabels {
  /// Returns the localization key of the reason a controller publishes no virtual device.
  ///
  /// - Parameter reason: The reason.
  /// - Returns: The localization key of the reason a controller publishes no virtual device.
  static func notPublishedReasonKey(
    _ reason: ApplicationServicePublicationStatus.NotPublishedReason
  ) -> String {
    switch reason {
    case .outputDisabled: return "ui.controllers.publication.reason.outputDisabled"
    case .systemGamepad: return "ui.controllers.publication.reason.systemGamepad"
    case .nativeHIDPassThrough: return "ui.controllers.publication.reason.nativeHIDPassThrough"
    case .upstreamVirtualDevice: return "ui.controllers.publication.reason.upstreamVirtualDevice"
    case .sessionSuspended: return "ui.controllers.publication.reason.sessionSuspended"
    case .noVirtualProfile: return "ui.controllers.publication.reason.noVirtualProfile"
    case .suppressed: return "ui.controllers.publication.reason.suppressed"
    case .noInputYet: return "ui.controllers.publication.reason.noInputYet"
    case .heldByAnotherClient: return "ui.controllers.publication.reason.heldByAnotherClient"
    }
  }

  /// Returns the localization key of the reason the output is disabled.
  ///
  /// - Parameter reason: The reason.
  /// - Returns: The localization key of the reason the output is disabled.
  static func servingReasonKey(_ reason: OutputDisabledReason) -> String {
    switch reason {
    case .userDisabled: return notPublishedReasonKey(.outputDisabled)
    case .upstreamVirtualDevice: return notPublishedReasonKey(.upstreamVirtualDevice)
    case .noVirtualProfile: return notPublishedReasonKey(.noVirtualProfile)
    }
  }

  /// Returns the localization key of the reason the input health failed.
  ///
  /// - Parameter reason: The reason.
  /// - Returns: The localization key of the reason the input health failed.
  static func inputHealthReasonKey(_ reason: ControllerInputHealthFailureReason) -> String {
    switch reason {
    case .missingReports: return "ui.controllers.inputHealth.reason.missingReports"
    case .freshnessNotAdvancing: return "ui.controllers.inputHealth.reason.freshnessNotAdvancing"
    case .guideNotPressed: return "ui.controllers.inputHealth.reason.guideNotPressed"
    }
  }

  /// Returns the localization key of how the controller was found.
  ///
  /// - Parameter source: The discovery source.
  /// - Returns: The localization key of how the controller was found.
  static func discoveryKey(_ source: DeviceDiscoverySource) -> String {
    switch source {
    case .hid: return "ui.controllers.discovery.hid"
    case .rawUSB: return "ui.controllers.discovery.rawUSB"
    }
  }

  /// Returns the localization key of the physical ownership.
  ///
  /// - Parameter ownership: The ownership the service observed.
  /// - Returns: The localization key of the physical ownership.
  static func physicalOwnershipKey(_ ownership: ControllerOwnershipObservation) -> String {
    switch ownership {
    case .exclusiveHID: return "ui.controllers.physicalOwnership.exclusiveHID"
    case .exclusiveRawUSB: return "ui.controllers.physicalOwnership.exclusiveRawUSB"
    case .extensionOwnedUSB: return "ui.controllers.physicalOwnership.extensionOwnedUSB"
    case .systemHIDVisible: return "ui.controllers.physicalOwnership.systemHIDVisible"
    case .systemGamepad: return "ui.controllers.physicalOwnership.systemGamepad"
    case .upstreamVirtualDevice: return "ui.controllers.physicalOwnership.upstreamVirtualDevice"
    case .unknown: return "ui.controllers.physicalOwnership.unknown"
    }
  }

  /// Returns the localization key of the HID input ownership.
  ///
  /// - Parameter ownership: The ownership.
  /// - Returns: The localization key of the HID input ownership.
  static func hidInputOwnershipKey(_ ownership: HIDInputOwnership) -> String {
    switch ownership {
    case .unknown: return "ui.controllers.hidInputOwnership.unknown"
    case .exclusive: return "ui.controllers.hidInputOwnership.exclusive"
    case .shared: return "ui.controllers.hidInputOwnership.shared"
    case .accessDenied: return "ui.controllers.hidInputOwnership.accessDenied"
    case .ownedByAnotherClient: return "ui.controllers.hidInputOwnership.ownedByAnotherClient"
    case .acquisitionFailed: return "ui.controllers.hidInputOwnership.acquisitionFailed"
    }
  }

  /// Returns the failure of a wireless disconnect, localized.
  ///
  /// The stage, system code, and detail stay in the log and in `ojd controller disconnect`.
  ///
  /// - Parameter failure: The failure.
  /// - Returns: The failure of a wireless disconnect, localized.
  static func wirelessDisconnectFailureText(
    _ failure: WirelessControllerDisconnectFailure
  ) -> String {
    let key: String
    switch failure {
    case .notFound: key = "ui.controllers.disconnectWireless.failure.notFound"
    case .notBluetooth: key = "ui.controllers.disconnectWireless.failure.notBluetooth"
    case .bluetoothLEUnsupported:
      key = "ui.controllers.disconnectWireless.failure.bluetoothLEUnsupported"
    case .missingAddress: key = "ui.controllers.disconnectWireless.failure.missingAddress"
    case .disconnectFailed: key = "ui.controllers.disconnectWireless.failure.disconnectFailed"
    case .timedOut: key = "ui.controllers.disconnectWireless.failure.timedOut"
    }
    return OJDLocalized.string(key)
  }
}
