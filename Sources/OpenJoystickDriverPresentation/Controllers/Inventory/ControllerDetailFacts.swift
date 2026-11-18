import Foundation
import OpenJoystickDriverKit

/// One labelled fact of the Controllers detail.
struct ControllerFact: Equatable, Identifiable {
  /// What a fact says, which names the row.
  enum Kind: Hashable {
    /// The app in front that selected the profile in force.
    case profileSelectedBy
    /// Whether a virtual device publishes the controller.
    case publication
    /// Whether a `Pause` has the controller pass through unmapped.
    case paused
    /// The route that serves the controller.
    case serving
    /// The serial number.
    case serialNumber
    /// The health of the input session.
    case inputHealth
    /// The battery level.
    case battery
    /// Whether the controller charges.
    case chargingState
    /// Whether the controller is on a cable, while its charging state is unknown.
    case cableState
    /// The report mode of a Wii Remote.
    case wiiReportMode
    /// The extension plugged into a Wii Remote.
    case wiiExtension
    /// The Motion Plus state of a Wii Remote.
    case wiiMotionPlus
    /// The rumble motors.
    case rumble
    /// The lighting features.
    case lighting
    /// The adaptive triggers.
    case adaptiveTriggers
    /// Whether the controller has a motion sensor.
    case motion
    /// The number of touch contacts.
    case touchContacts
    /// The unit ID.
    case unitID
    /// The binding that parses the controller's input.
    case parser
    /// Who owns the controller's input and output.
    case ownership
    /// The concern of the physical ownership, when the system does not list the controller too.
    case duplicateExposureRisk
    /// Where the controller's record comes from.
    case record
    /// Where the HID usage map comes from.
    case inputMapping
    /// The controls the parser emits.
    case controls
    /// How the startup commands went.
    case startupStatus
    /// The format of the input reports.
    case inputReportFormat
    /// How many times the input recovered.
    case inputRecoveries
    /// When the last publication was attempted.
    case publicationAttempted
    /// When the last publication completed.
    case publicationCompleted
    /// The vendor and product ID.
    case usbIdentifier
    /// The endpoint that sends input.
    case inputEndpoint
    /// The endpoint that takes output.
    case outputEndpoint
    /// The client that holds the controller exclusively.
    case exclusiveOwner
    /// Every process that holds the controller open.
    case holders
    /// Whether the system also lists the controller.
    case alsoListedBySystem
  }

  /// What the fact says.
  let kind: Kind
  /// The localized name of the fact.
  let label: String
  /// The value of the fact.
  let value: OJDValue

  /// The kind, which names the fact.
  var id: Kind { kind }
}

/// The facts the Controllers detail lists for one controller, from the same service description
/// `ojd controller show` reads.
///
/// A fact that applies but has no value shows "None"; a fact the controller cannot have, such as an
/// unreported battery or a motion sensor it lacks, is left out.
enum ControllerDetailFacts {
  /// Returns the facts every user wants: what is published and how, the controller's state, and
  /// what it can do.
  ///
  /// - Parameters:
  ///   - device: The controller.
  ///   - appName: The name of the app with a bundle identifier.
  /// - Returns: The facts every user wants: what is published and how, the controller's state, and
  ///   what it can do.
  static func general(
    for device: ApplicationServiceDeviceDescription,
    appName: (String) -> String = { $0 }
  ) -> [ControllerFact] {
    let output = device.physicalOutputCapabilities
    let selectedBy =
      device.profileInForce?.appID.map {
        [
          fact(
            .profileSelectedBy,
            "ui.controllers.profileSelectedBy.label",
            .text(appName($0))
          )
        ]
      } ?? []
    let paused =
      device.paused
      ? [
        fact(
          .paused,
          "ui.controllers.paused.label",
          .text(OJDLocalized.string("ui.controllers.paused.value"))
        )
      ] : []
    let always = [
      fact(.publication, "cli.controller.show.labelPublication", publication(device)),
      fact(.serving, "ui.controllers.serving.label", .text(device.servingRouteLabel)),
      fact(.serialNumber, "term.serialNumber", serialNumber(device)),
    ]
    // A controller that another client holds runs no input session, so it has no input health.
    let input =
      device.hidInputOwnership == .ownedByAnotherClient
      ? []
      : [fact(.inputHealth, "cli.controller.show.labelInput", .text(inputHealthText(device)))]
    let power = [
      fact(.battery, "ui.controllers.battery", battery(device)),
      fact(.chargingState, "ui.controllers.chargingState", chargingState(device)),
      fact(
        .cableState,
        "ui.controllers.cableState",
        chargingState(device) == .none ? cableState(device) : .none
      ),
    ]
    let wiiRemote =
      device.connectionState?.wiiRemote.map {
        [
          fact(.wiiReportMode, "cli.controller.show.labelReportMode", .text($0.reportModeText)),
          fact(.wiiExtension, "cli.controller.show.labelExtension", .text($0.extensionText())),
          fact(.wiiMotionPlus, "cli.controller.show.labelMotionPlus", .text($0.motionPlusText())),
        ]
      } ?? []
    let capabilities = [
      fact(.rumble, "cli.controller.show.labelRumble", list(output.rumbleMotors.map(\.title))),
      fact(
        .lighting,
        "cli.controller.show.labelLighting",
        list(output.lightingFeatures.map(\.title))
      ),
      fact(
        .adaptiveTriggers,
        "ui.controllers.adaptiveTriggers",
        list(output.adaptiveTriggers.map(\.title))
      ),
      fact(
        .motion,
        "ui.controllers.motion",
        device.capabilities.motion ? .text(OJDLocalized.string("status.available")) : .none
      ),
      fact(
        .touchContacts,
        "ui.controllers.touchContacts",
        device.capabilities.touchContactCount > 0
          ? .text(String(device.capabilities.touchContactCount)) : .none
      ),
    ]
    let held =
      device.hidInputOwnership == .ownedByAnotherClient
      ? [
        fact(
          .exclusiveOwner,
          "ui.controllers.exclusiveOwner",
          .text(
            USBExclusiveOwner.heldMessage(for: device.inputOwner, localize: OJDLocalized.string)
          )
        )
      ] : []
    let holders = fact(
      .holders,
      "ui.controllers.holders",
      list(device.holders.map { $0.label(localize: OJDLocalized.string) })
    )
    let listed =
      device.duplicateExposureRisk == .systemGameController
      ? [
        fact(
          .alsoListedBySystem,
          "ui.controllers.alsoListedBySystem",
          .text(OJDLocalized.string("status.controllerAlsoListedBySystem"))
        )
      ] : []
    return selectedBy + paused + always + input + held + [holders] + listed
      + (power + wiiRemote + capabilities).filter { $0.value != .none }
  }

  /// Returns the technical facts, shown under Advanced: identifiers, the parser (the binding that
  /// parses the controller's input, in its `ojd` spelling, such as `xbox-xusb:receiver`),
  /// ownership, the record, publication timing, and the controls the parser emits.
  ///
  /// - Parameters:
  ///   - device: The controller.
  ///   - record: The controller model's effective record, if one matches.
  /// - Returns: The technical facts, shown under Advanced: identifiers, the parser (the binding
  ///   that parses the controller's input, in its `ojd` spelling, such as `xbox-xusb:receiver`),
  ///   ownership, the record, publication timing, and the controls the parser emits.
  static func advanced(
    for device: ApplicationServiceDeviceDescription,
    record: ControllerRecord?
  ) -> [ControllerFact] {
    let health = device.inputHealth
    let publication = device.publication
    let now = DispatchTime.now().uptimeNanoseconds
    let optional = [
      fact(
        .duplicateExposureRisk,
        "ui.controllers.duplicateExposureRisk",
        // The General facts already say that the system lists the controller too.
        device.duplicateExposureRisk == .systemGameController
          ? .none : .text(duplicateExposureText(device.duplicateExposureRisk))
      ),
      fact(
        .controls,
        "cli.controller.show.labelControls",
        list(
          Control.allCases.filter(device.capabilities.controls.contains).map {
            controlText($0)
          }
        )
      ),
      fact(
        .startupStatus,
        "ui.controllers.startupStatus",
        OJDValue(device.startupCommandStatus)
      ),
      fact(
        .inputMapping,
        "cli.controller.show.labelInputMapping",
        device.bindingResult.inputMapping.map { .text(inputMappingText($0)) } ?? .none
      ),
      fact(.inputReportFormat, "ui.controllers.inputReportFormat", OJDValue(health.reportFormat)),
      fact(
        .inputRecoveries,
        "ui.controllers.inputRecoveries",
        health.recoveryCount > 0 ? .text(String(health.recoveryCount)) : .none
      ),
      fact(
        .publicationAttempted,
        "ui.controllers.publicationAttempted",
        age(publication?.lastAttemptedNanoseconds, now: now)
      ),
      fact(
        .publicationCompleted,
        "ui.controllers.publicationCompleted",
        age(publication?.lastCompletedNanoseconds, now: now)
      ),
    ].filter { $0.value != .none }
    return [
      fact(.unitID, "cli.controller.show.labelUnit", .reported(device.portKey?.rawValue)),
      fact(.parser, "term.parser", parserText(device)),
      fact(.ownership, "cli.controller.show.labelOwnership", .text(ownershipText(device))),
      fact(.record, "cli.controller.show.labelRecord", .text(recordText(record))),
    ] + optional + [
      fact(.usbIdentifier, "ui.controllers.usbIdentifier", usbIdentifier(device)),
      fact(.inputEndpoint, "term.inputEndpoint", .endpoint(device.inputEndpoint)),
      fact(.outputEndpoint, "term.outputEndpoint", .endpoint(device.outputEndpoint)),
    ]
  }

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

  /// Returns the fact with the localized label.
  ///
  /// - Parameters:
  ///   - kind: What the fact says.
  ///   - key: The localization key of the label.
  ///   - value: The value of the fact.
  /// - Returns: The fact with the localized label.
  private static func fact(
    _ kind: ControllerFact.Kind,
    _ key: String,
    _ value: OJDValue
  )
    -> ControllerFact
  {
    ControllerFact(kind: kind, label: OJDLocalized.string(key), value: value)
  }

  /// Returns the comma-separated names, or no value when there are none.
  ///
  /// - Parameter names: The names.
  /// - Returns: The comma-separated names, or no value when there are none.
  private static func list(_ names: [String]) -> OJDValue {
    names.isEmpty ? .none : .text(names.joined(separator: ", "))
  }
}
