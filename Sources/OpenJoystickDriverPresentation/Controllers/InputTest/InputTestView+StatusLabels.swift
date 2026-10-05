#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit
  import OpenJoystickDriverKit
  import SwiftUI

  extension InputTestView {

    var statusLabel: String {
      switch model.sessionState {
      case .idle: return OJDLocalized.string("inputTest.idle")
      case .starting: return OJDLocalized.string("inputTest.starting")
      case .live: return OJDLocalized.string("inputTest.live")
      case .stale: return OJDLocalized.string("inputTest.stale")
      case .disconnected:
        return OJDLocalized.string("inputTest.disconnected")
      case .permissionRequired:
        return OJDLocalized.string(
          "inputTest.permissionRequired"
        )
      case .unavailable:
        return OJDLocalized.string("inputTest.unavailable")
      case .error: return OJDLocalized.string("common.failed")
      }
    }

    var statusSemanticState: SemanticState {
      switch model.sessionState {
      case .live: return .active
      case .starting: return .loading
      case .stale, .permissionRequired: return .attention
      case .idle: return .inactive
      case .disconnected: return .disconnected
      case .unavailable: return .unknown
      case .error: return .failure
      }
    }

    func motorLabel(_ motor: PhysicalRumbleMotor) -> String {
      switch motor {
      case .leftMain: return OJDLocalized.string("inputTest.leftMain")
      case .rightMain: return OJDLocalized.string("inputTest.rightMain")
      case .leftTrigger:
        return OJDLocalized.string("inputTest.leftTrigger")
      case .rightTrigger:
        return OJDLocalized.string("inputTest.rightTrigger")
      case .leftHaptic: return OJDLocalized.string("inputTest.leftHaptic")
      case .rightHaptic:
        return OJDLocalized.string("inputTest.rightHaptic")
      }
    }

    func reported(_ value: String) -> String {
      let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
      return trimmed.isEmpty
        ? OJDLocalized.string("controllers.notReported") : trimmed
    }

    func usbIdentifier(_ device: ApplicationServiceDeviceDescription) -> String {
      guard device.vendorID != 0 || device.productID != 0 else {
        return OJDLocalized.string("controllers.notReported")
      }
      return String(format: "%04X:%04X", device.vendorID, device.productID)
    }
  }

#endif
