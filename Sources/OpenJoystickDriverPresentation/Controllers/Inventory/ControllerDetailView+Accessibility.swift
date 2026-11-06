#if canImport(SwiftUI)

  import AppKit
  import Foundation
  import OpenJoystickDriverKit
  import SwiftUI

  extension ControllerDetailView {

    /// The sentence VoiceOver reads for the detail: the connection, the active profile, the
    /// protocol, the serial number as shown, the IDs, the endpoints and the battery.
    var accessibilityValue: String {
      let details = OJDLocalized.formatted(
        "ui.controllers.accessibilityDetails",
        connectionValue.spokenText,
        profileAccessibilityValue,
        device.protocolBinding.displayName,
        OJDValue.reported(device.protocolBinding.commandLineName).spokenText,
        serialVisibility.presentation(of: ControllerDetailFacts.serialNumber(device)).spokenText,
        ControllerDetailFacts.usbIdentifier(device).spokenText,
        OJDValue.endpoint(device.inputEndpoint).spokenText,
        OJDValue.endpoint(device.outputEndpoint).spokenText
      )
      let battery = OJDLocalized.formatted(
        "ui.controllers.batteryAccessibilityDetails",
        ControllerDetailFacts.battery(device).spokenText,
        ControllerDetailFacts.chargingState(device).spokenText,
        ControllerDetailFacts.cableState(device).spokenText
      )
      return "\(details) \(battery)"
    }

    /// The sentence about the active profile: checking, none, its name, or the failure.
    private var profileAccessibilityValue: String {
      switch activeProfile {
      case .loading:
        return OJDLocalized.string(
          "ui.controllers.profileCheckingSentence"
        )
      case .noProfile:
        return OJDLocalized.string(
          "ui.controllers.noActiveProfileSentence"
        )
      case .profile(let name):
        return OJDLocalized.formatted(
          "ui.controllers.activeProfileSentence",
          name
        )
      case .unavailable(let message):
        return OJDLocalized.formatted(
          "ui.controllers.profileUnavailableSentence",
          message
        )
      case .error(let message):
        return OJDLocalized.formatted(
          "ui.controllers.profileErrorSentence",
          message
        )
      }
    }
  }

#endif
