#if canImport(SwiftUI)

  import AppKit
  import Foundation
  import OpenJoystickDriverKit
  import SwiftUI

  extension ControllerDetailView {

    var accessibilityValue: String {
      let details = OJDLocalized.formatted(
        "controllers.accessibilityDetails",
        reportedValue(device.connection),
        profileAccessibilityValue,
        device.protocolBinding.displayLabel,
        reportedValue(device.protocolBinding.rawValue),
        serialNumberLabel,
        usbIdentifier,
        endpointLabel(device.inputEndpoint),
        endpointLabel(device.outputEndpoint)
      )
      let battery = OJDLocalized.formatted(
        "controllers.batteryAccessibilityDetails",
        batteryPercentageLabel,
        chargingStateLabel,
        cableStateLabel
      )
      return "\(details) \(battery)"
    }

    private var profileAccessibilityValue: String {
      switch activeProfile {
      case .loading:
        return OJDLocalized.string(
          "controllers.profileCheckingSentence"
        )
      case .noProfile:
        return OJDLocalized.string(
          "controllers.noActiveProfileSentence"
        )
      case .profile(let name):
        return OJDLocalized.formatted(
          "controllers.activeProfileSentence",
          name
        )
      case .unavailable(let message):
        return OJDLocalized.formatted(
          "controllers.profileUnavailableSentence",
          message
        )
      case .error(let message):
        return OJDLocalized.formatted(
          "controllers.profileErrorSentence",
          message
        )
      }
    }
  }

#endif
