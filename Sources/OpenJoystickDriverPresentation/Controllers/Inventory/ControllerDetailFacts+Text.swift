import Foundation
import OpenJoystickDriverKit

extension ControllerDetailFacts {
  /// Returns the Automatic choice of the Virtual HID profile picker.
  ///
  /// It names the profile the service selected on its own, so the picker is the one place the
  /// published profile is shown; it is plain "Automatic" while an override is the selection or when
  /// no profile is selected.
  ///
  /// - Parameter device: The controller.
  /// - Returns: The Automatic choice of the Virtual HID profile picker.
  static func automaticProfileLabel(_ device: ApplicationServiceDeviceDescription) -> String {
    let automatic = OJDLocalized.string("ui.mapping.automatic")
    guard let status = device.virtualHIDProfile, let profile = status.profile,
      status.source != .override
    else { return automatic }
    return OJDLocalized.formatted(
      "ui.virtualProfile.automaticSelected",
      profile.identity.productName
    )
  }

  /// Returns whether a virtual device publishes the controller, why not, and for a failed send
  /// the failure text, localized; "None" when the service reports none.
  ///
  /// - Parameter device: The controller.
  /// - Returns: Whether a virtual device publishes the controller, why not, and for a failed send
  ///   the failure text, localized; "None" when the service reports none.
  static func publication(_ device: ApplicationServiceDeviceDescription) -> OJDValue {
    // The Input row already says the controller waits for its first input.
    let inputRowSaysWaiting =
      device.hidInputOwnership != .ownedByAnotherClient
      && device.inputHealth.state == .awaitingInput
    return device.publication.map {
      .text(publicationText($0, omittingNoInputYet: inputRowSaysWaiting))
    } ?? .none
  }

  /// Returns whether the publication only says that macOS serves the controller itself.
  ///
  /// - Parameter publication: The publication status the service reported, if any.
  /// - Returns: Whether the publication only says that macOS serves the controller itself.
  static func publicationRepeatsSystemServer(
    _ publication: ApplicationServicePublicationStatus?
  ) -> Bool {
    guard let publication, publication.state == .notPublished else { return false }
    return publication.reason == .systemGamepad || publication.reason == .nativeHIDPassThrough
  }

  /// Returns the input health state, with its failure reason when it has one.
  ///
  /// - Parameter device: The controller.
  /// - Returns: The input health state, with its failure reason when it has one.
  static func inputHealthText(_ device: ApplicationServiceDeviceDescription) -> String {
    let state = OJDLocalized.string(inputHealthKey(device.inputHealth.state))
    guard let reason = device.inputHealth.failureReason else { return state }
    return OJDLocalized.formatted(
      "ui.controllers.inputHealth.withReason",
      state,
      OJDLocalized.string(ControllerDetailLabels.inputHealthReasonKey(reason))
    )
  }

  /// Returns where the controller was found and who owns its physical and HID input.
  ///
  /// - Parameter device: The controller.
  /// - Returns: Where the controller was found and who owns its physical and HID input.
  static func ownershipText(_ device: ApplicationServiceDeviceDescription) -> String {
    OJDLocalized.formatted(
      "ui.controllers.ownership.value",
      OJDLocalized.string(ControllerDetailLabels.discoveryKey(device.discoverySource)),
      OJDLocalized.string(ControllerDetailLabels.physicalOwnershipKey(device.physicalOwnership)),
      OJDLocalized.string(ControllerDetailLabels.hidInputOwnershipKey(device.hidInputOwnership))
    )
  }

  /// Returns the duplicate-exposure concern of the physical ownership, localized.
  ///
  /// - Parameter risk: The concern.
  /// - Returns: The duplicate-exposure concern of the physical ownership, localized.
  static func duplicateExposureText(_ risk: DuplicateExposureRisk) -> String {
    switch risk {
    case .none: return OJDLocalized.string("status.none")
    case .systemHIDVisible:
      return OJDLocalized.string(ControllerDetailLabels.physicalOwnershipKey(.systemHIDVisible))
    case .upstreamVirtualDevice:
      return OJDLocalized.string(
        ControllerDetailLabels.physicalOwnershipKey(.upstreamVirtualDevice)
      )
    case .systemGameController:
      return OJDLocalized.string(ControllerDetailLabels.physicalOwnershipKey(.systemGamepad))
    case .unknownOwnership:
      return OJDLocalized.string(ControllerDetailLabels.physicalOwnershipKey(.unknown))
    }
  }

  /// Returns the record layer, and the file when a user or package file sets the record.
  ///
  /// - Parameter record: The controller model's effective record, or nil.
  /// - Returns: The record layer, and the file when a user or package file sets the record.
  static func recordText(_ record: ControllerRecord?) -> String {
    guard let record else { return OJDLocalized.string("cli.controller.show.recordNone") }
    guard let file = record.file else {
      return OJDLocalized.string("cli.controller.show.recordBundled")
    }
    return recordLocation(file.path)
  }

  /// Returns the record row for a user or package file, with the home folder written as `~`.
  ///
  /// - Parameter path: The path of the record file.
  /// - Returns: The record row for a user or package file, with the home folder written as `~`.
  static func recordLocation(_ path: String) -> String {
    OJDLocalized.formatted("cli.controller.show.recordUser", HomeFolder.redacting(path))
  }

  /// Returns the localization key of the input health state.
  ///
  /// - Parameter state: The state.
  /// - Returns: The localization key of the input health state.
  private static func inputHealthKey(_ state: ControllerInputHealthState) -> String {
    switch state {
    case .awaitingInput: return "ui.controllers.inputHealth.awaitingInput"
    case .healthy: return "ui.controllers.inputHealth.healthy"
    case .stale: return "ui.controllers.inputHealth.stale"
    case .waitingForNeutral: return "ui.controllers.inputHealth.waitingForNeutral"
    }
  }

  /// Returns the localization key of the publication state.
  ///
  /// - Parameter state: The state.
  /// - Returns: The localization key of the publication state.
  private static func publicationKey(_ state: ApplicationServicePublicationStatus.State) -> String {
    switch state {
    case .published: return "ui.controllers.publication.published"
    case .notPublished: return "ui.controllers.publication.notPublished"
    case .failed: return "ui.controllers.publication.failed"
    }
  }

  /// Returns the record layer that sets the controller's server, by the name the Library gives it.
  ///
  /// - Parameter record: The controller model's effective record.
  /// - Returns: The record layer that sets the controller's server, by the name the Library gives
  ///   it.
  static func serverSourceText(_ record: ControllerRecord) -> String {
    (record.fieldLayers["server"] ?? .driver).libraryTitle
  }

  /// Returns the publication state, with the reason or the failure when it has one.
  ///
  /// - Parameters:
  ///   - publication: The publication status the service reported.
  ///   - omittingNoInputYet: Whether to leave out the reason that the controller waits for input.
  /// - Returns: The publication state, with the reason or the failure when it has one.
  static func publicationText(
    _ publication: ApplicationServicePublicationStatus,
    omittingNoInputYet: Bool = false
  ) -> String {
    let state = OJDLocalized.string(publicationKey(publication.state))
    let detail: String
    switch publication.state {
    case .published: return state
    case .notPublished:
      guard let reason = publication.reason, !(omittingNoInputYet && reason == .noInputYet) else {
        return state
      }
      detail = OJDLocalized.string(ControllerDetailLabels.notPublishedReasonKey(reason))
    case .failed:
      guard let failure = publication.failure else { return state }
      detail = OJDLocalized.formatted("ui.controllers.publication.failedSend", failure)
    }
    return OJDLocalized.formatted("ui.controllers.publication.withReason", state, detail)
  }

  /// Returns the serial number as reported.
  ///
  /// - Parameter device: The controller.
  /// - Returns: The serial number as reported.
  static func serialNumber(_ device: ApplicationServiceDeviceDescription) -> OJDValue {
    .reported(device.serialNumber)
  }

  /// Returns the vendor and product ID.
  ///
  /// - Parameter device: The controller.
  /// - Returns: The vendor and product ID.
  static func usbIdentifier(_ device: ApplicationServiceDeviceDescription) -> OJDValue {
    .usbIdentifier(vendorID: device.vendorID, productID: device.productID)
  }

  /// Returns the battery level, or none when the controller reports none.
  ///
  /// - Parameter device: The controller.
  /// - Returns: The battery level, or none when the controller reports none.
  static func battery(_ device: ApplicationServiceDeviceDescription) -> OJDValue {
    OJDValue(device.connectionState?.power.battery.percentageText)
  }

  /// Returns the charging state, or none while it is unknown.
  ///
  /// - Parameter device: The controller.
  /// - Returns: The charging state, or none while it is unknown.
  static func chargingState(_ device: ApplicationServiceDeviceDescription) -> OJDValue {
    switch device.connectionState?.power.charging ?? .unknown {
    case .discharging: return .text(OJDLocalized.string("ui.controllers.discharging"))
    case .charging: return .text(OJDLocalized.string("ui.controllers.charging"))
    case .full: return .text(OJDLocalized.string("ui.controllers.batteryFull"))
    case .notChargeable: return .text(OJDLocalized.string("ui.controllers.notChargeable"))
    case .unknown: return .none
    }
  }

  /// Returns whether the controller is on a cable, or none when it does not report it.
  ///
  /// - Parameter device: The controller.
  /// - Returns: Whether the controller is on a cable, or none when it does not report it.
  static func cableState(_ device: ApplicationServiceDeviceDescription) -> OJDValue {
    switch device.connectionState?.power.wiredPower {
    case true?:
      return .text(OJDLocalized.string("ui.settings.notifications.controllerConnectedShort"))
    case false?:
      return .text(OJDLocalized.string("ui.settings.notifications.controllerDisconnectedShort"))
    case nil: return .none
    }
  }

  /// Returns how long before `now` the system uptime `nanoseconds` was, as relative text.
  ///
  /// - Parameters:
  ///   - nanoseconds: The uptime of the event, or nil.
  ///   - now: The uptime now.
  /// - Returns: How long before `now` the system uptime `nanoseconds` was, as relative text.
  static func age(_ nanoseconds: UInt64?, now: UInt64) -> OJDValue {
    guard let nanoseconds, nanoseconds <= now else { return .none }
    let seconds = Double(now - nanoseconds) / 1_000_000_000
    return .text(
      RelativeDateTimeFormatter().localizedString(
        for: Date(timeIntervalSinceNow: -seconds),
        relativeTo: Date()
      )
    )
  }
}
