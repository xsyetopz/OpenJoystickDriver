import Foundation
import OpenJoystickDriverKit

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
    let always = routeFacts(for: device)
    let power = powerFacts(for: device)
    let capabilities = capabilityFacts(for: device)
    return selectedByFacts(for: device, appName: appName) + pausedFacts(for: device) + always
      + inputHealthFacts(for: device) + heldFacts(for: device) + [holdersFact(for: device)]
      + alsoListedFacts(for: device)
      + (power + wiiRemoteFacts(for: device) + capabilities).filter { $0.value != .none }
  }

  /// The app in front that selected the profile in force, if any.
  private static func selectedByFacts(
    for device: ApplicationServiceDeviceDescription,
    appName: (String) -> String
  ) -> [ControllerFact] {
    return device.profileInForce?.appID.map {
      [
        fact(
          .profileSelectedBy,
          "ui.controllers.profileSelectedBy.label",
          .text(appName($0))
        )
      ]
    } ?? []
  }

  /// The fact that a `Pause` has the controller pass through unmapped, if it does.
  private static func pausedFacts(
    for device: ApplicationServiceDeviceDescription
  ) -> [ControllerFact] {
    return device.paused
      ? [
        fact(
          .paused,
          "ui.controllers.paused.label",
          .text(OJDLocalized.string("ui.controllers.paused.value"))
        )
      ] : []
  }

  /// The publication, route and serial number facts.
  private static func routeFacts(
    for device: ApplicationServiceDeviceDescription
  ) -> [ControllerFact] {
    // The Handled by picker already names who serves the controller, so its route and a "not
    // shown because macOS serves it" publication would repeat the picker's selection.
    let pickerShown = ServingPolicy.offersServerChoice(ServingInput(device))
    let route =
      pickerShown
      ? [] : [fact(.serving, "ui.controllers.serving.label", .text(device.servingRouteLabel))]
    let shown =
      pickerShown && publicationRepeatsSystemServer(device.publication)
      ? [] : [fact(.publication, "cli.controller.show.labelPublication", publication(device))]
    return shown + route + [fact(.serialNumber, "term.serialNumber", serialNumber(device))]
  }

  /// The input health, unless another client holds the controller.
  private static func inputHealthFacts(
    for device: ApplicationServiceDeviceDescription
  ) -> [ControllerFact] {
    // A controller that another client holds runs no input session, so it has no input health.
    return device.hidInputOwnership == .ownedByAnotherClient
      ? []
      : [fact(.inputHealth, "cli.controller.show.labelInput", .text(inputHealthText(device)))]
  }

  /// The battery, charging and cable facts.
  private static func powerFacts(
    for device: ApplicationServiceDeviceDescription
  ) -> [ControllerFact] {
    return [
      fact(.battery, "ui.controllers.battery", battery(device)),
      fact(.chargingState, "ui.controllers.chargingState", chargingState(device)),
      fact(
        .cableState,
        "ui.controllers.cableState",
        chargingState(device) == .none ? cableState(device) : .none
      ),
    ]
  }

  /// The report mode, extension and Motion Plus facts of a Wii Remote.
  private static func wiiRemoteFacts(
    for device: ApplicationServiceDeviceDescription
  ) -> [ControllerFact] {
    return device.connectionState?.wiiRemote.map {
      [
        fact(.wiiReportMode, "cli.controller.show.labelReportMode", .text($0.reportModeText)),
        fact(.wiiExtension, "cli.controller.show.labelExtension", .text($0.extensionText())),
        fact(.wiiMotionPlus, "cli.controller.show.labelMotionPlus", .text($0.motionPlusText())),
      ]
    } ?? []
  }

  /// The rumble, lighting, adaptive trigger, motion and touch facts.
  private static func capabilityFacts(
    for device: ApplicationServiceDeviceDescription
  ) -> [ControllerFact] {
    let output = device.physicalOutputCapabilities
    return [
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
  }

  /// The client that holds the controller for itself, if another client does.
  private static func heldFacts(for device: ApplicationServiceDeviceDescription) -> [ControllerFact]
  {
    return device.hidInputOwnership == .ownedByAnotherClient
      ? [
        fact(
          .exclusiveOwner,
          "ui.controllers.exclusiveOwner",
          .text(
            USBExclusiveOwner.heldMessage(for: device.inputOwner, localize: OJDLocalized.string)
          )
        )
      ] : []
  }

  /// The processes that hold the controller open.
  private static func holdersFact(for device: ApplicationServiceDeviceDescription) -> ControllerFact
  {
    fact(
      .holders,
      "ui.controllers.holders",
      list(device.holders.map { $0.label(localize: OJDLocalized.string) })
    )
  }

  /// The fact that the system also lists the controller, if it does.
  private static func alsoListedFacts(
    for device: ApplicationServiceDeviceDescription
  ) -> [ControllerFact] {
    return device.duplicateExposureRisk == .systemGameController
      ? [
        fact(
          .alsoListedBySystem,
          "ui.controllers.alsoListedBySystem",
          .text(OJDLocalized.string("status.controllerAlsoListedBySystem"))
        )
      ] : []
  }

  /// Returns the technical facts, shown under Advanced: identifiers, the parser (the binding that
  /// parses the controller's input, in its `ojd` spelling, such as `xbox-xusb:receiver`),
  /// ownership, the record, publication timing, and the controls the parser sends.
  ///
  /// - Parameters:
  ///   - device: The controller.
  ///   - record: The controller model's effective record, if one matches.
  /// - Returns: The technical facts, shown under Advanced: identifiers, the parser (the binding
  ///   that parses the controller's input, in its `ojd` spelling, such as `xbox-xusb:receiver`),
  ///   ownership, the record, publication timing, and the controls the parser sends.
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
