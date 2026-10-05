import Foundation
import OpenJoystickDriverKit

extension RuntimePresentation {
  static func outputDetail(enabled: Bool?, status: VirtualOutputBackendStatus?) -> String? {
    guard let enabled else { return nil }
    guard enabled else {
      return OJDLocalized.string(
        "mapping.outputUnavailable"
      )
    }
    return status?.isError == true
      ? OJDLocalized.string(
        "mapping.outputNeedsAttention"
      ) : OJDLocalized.string("mapping.outputReady")
  }

  /// The message for `error`; a remapping error from the service ends with its code, such as
  /// "(E3013)", so a report names it and `ojd explain` can look it up.
  static func userFacingError(_ error: Error) -> String {
    let message = userFacingMessage(error)
    guard let error = error as? ApplicationServiceRemappingRPCError else { return message }
    return OJDLocalized.formatted(
      "error.withCode",
      message,
      error.code.errorCode.rawValue
    )
  }

  private static func userFacingMessage(_ error: Error) -> String {
    if let error = error as? ApplicationServiceRemappingRPCError {
      switch error.code {
      case .profileUpdateConflict:
        return OJDLocalized.string(
          "error.profileChanged"
        )
      case .duplicateName:
        return OJDLocalized.string(
          "error.duplicateProfile"
        )
      case .profileNotFound:
        return OJDLocalized.string(
          "error.profileMissing"
        )
      case .invalidProfile, .invalidArguments:
        return OJDLocalized.string(
          "error.reviewAssignments"
        )
      case .unwritableLibrary, .librarySizeExceeded, .profileCountExceeded:
        return OJDLocalized.string(
          "error.profileLibrarySave"
        )
      case .corruptLibrary:
        return OJDLocalized.string(
          "error.profileLibraryCorrupt"
        )
      case .joyConPairUnavailable:
        return OJDLocalized.string(
          "error.joyConPairUnavailable"
        )
      case .routerEngineUnavailable, .routerLibraryUnavailable, .routerLibraryAndEngineUnavailable,
        .routerShutDown:
        return OJDLocalized.string(
          "error.remappingUnavailable"
        )
      default:
        return OJDLocalized.string(
          "error.generic"
        )
      }
    }
    if error is RuntimeProfileDraftError || error is RemappingValidationError {
      return OJDLocalized.string(
        "error.reviewAssignments"
      )
    }
    switch error {
    case ApplicationServiceClientError.notConnected:
      return OJDLocalized.string(
        "error.notAvailable"
      )
    case ApplicationServiceClientError.timeout:
      return OJDLocalized.string(
        "error.timeout"
      )
    case ApplicationServiceClientError.invalidResponse:
      return OJDLocalized.string(
        "error.unexpected"
      )
    default:
      return OJDLocalized.string(
        "error.generic"
      )
    }
  }

  static func isUnavailable(_ error: Error) -> Bool {
    if let error = error as? ApplicationServiceRemappingRPCError {
      switch error.code {
      case .routerEngineUnavailable, .routerLibraryUnavailable, .routerLibraryAndEngineUnavailable,
        .routerShutDown:
        return true
      default: break
      }
    }
    switch error {
    case ApplicationServiceClientError.notConnected, ApplicationServiceClientError.timeout:
      return true
    default: return false
    }
  }

  static func buttonLabel(_ button: RemappingButton) -> String {
    switch button {
    case .leftFunction:
      return OJDLocalized.string("mapping.leftFunctionButton")
    case .rightFunction:
      return OJDLocalized.string("mapping.rightFunctionButton")
    case .leftPaddle: return OJDLocalized.string("mapping.leftPaddle")
    case .rightPaddle: return OJDLocalized.string("mapping.rightPaddle")
    case .leftSL: return OJDLocalized.string("mapping.leftJoyConSL")
    case .leftSR: return OJDLocalized.string("mapping.leftJoyConSR")
    case .rightSL: return OJDLocalized.string("mapping.rightJoyConSL")
    case .rightSR: return OJDLocalized.string("mapping.rightJoyConSR")
    case .leftGrip: return OJDLocalized.string("mapping.leftGrip")
    case .rightGrip: return OJDLocalized.string("mapping.rightGrip")
    case .leftPadClick:
      return OJDLocalized.string("mapping.leftPadClick")
    case .rightPadClick:
      return OJDLocalized.string("mapping.rightPadClick")
    case .south: return OJDLocalized.string("mapping.buttonSouth")
    case .east: return OJDLocalized.string("mapping.buttonEast")
    case .west: return OJDLocalized.string("mapping.buttonWest")
    case .north: return OJDLocalized.string("mapping.buttonNorth")
    case .leftShoulder:
      return OJDLocalized.string("mapping.leftShoulder")
    case .rightShoulder:
      return OJDLocalized.string("mapping.rightShoulder")
    case .leftStick:
      return OJDLocalized.string("mapping.leftStickClick")
    case .rightStick:
      return OJDLocalized.string("mapping.rightStickClick")
    case .start: return OJDLocalized.string("mapping.start")
    case .back: return OJDLocalized.string("mapping.back")
    case .guide: return OJDLocalized.string("mapping.guide")
    case .share: return OJDLocalized.string("mapping.share")
    case .options: return OJDLocalized.string("mapping.options")
    case .touchpad: return OJDLocalized.string("mapping.touchpadClick")
    case .mute: return OJDLocalized.string("mapping.mute")
    case .leftTriggerClick:
      return OJDLocalized.string("mapping.leftTriggerClick")
    case .rightTriggerClick:
      return OJDLocalized.string("mapping.rightTriggerClick")
    }
  }

  static func axisLabel(_ axis: RemappingAxis) -> String {
    switch axis {
    case .leftStickX:
      return OJDLocalized.string("mapping.leftStickHorizontal")
    case .leftStickY:
      return OJDLocalized.string("mapping.leftStickVertical")
    case .rightStickX:
      return OJDLocalized.string("mapping.rightStickHorizontal")
    case .rightStickY:
      return OJDLocalized.string("mapping.rightStickVertical")
    case .leftTrigger: return OJDLocalized.string("mapping.leftTrigger")
    case .rightTrigger:
      return OJDLocalized.string("mapping.rightTrigger")
    }
  }

  static func modifierLabel(_ modifier: RemappingKeyModifier) -> String {
    switch modifier {
    case .command: return OJDLocalized.string("keyboard.command")
    case .control: return OJDLocalized.string("keyboard.control")
    case .option: return OJDLocalized.string("keyboard.option")
    case .shift: return OJDLocalized.string("keyboard.shift")
    }
  }

  static func modifierSystemSymbolName(_ modifier: RemappingKeyModifier) -> String {
    switch modifier {
    case .command: return "command"
    case .control: return "control"
    case .option: return "option"
    case .shift: return "shift"
    }
  }

  static func keyboardSystemSymbolName(_ key: RemappingKeyboardKey) -> String? {
    switch key {
    case .escape: return "escape"
    case .tab: return "tab"
    case .capsLock: return "capslock"
    case .space: return "space"
    case .returnKey: return "return"
    case .deleteBackward: return "delete.left"
    case .deleteForward: return "delete.forward"
    case .arrowUp: return "arrow.up"
    case .arrowDown: return "arrow.down"
    case .arrowLeft: return "arrow.left"
    case .arrowRight: return "arrow.right"
    case .pageUp: return "arrow.up.to.line"
    case .pageDown: return "arrow.down.to.line"
    case .home: return "arrow.up.to.line.compact"
    case .end: return "arrow.down.to.line.compact"
    default: return nil
    }
  }

  static func keyboardSystemSymbolFallbackName(_ key: RemappingKeyboardKey) -> String? {
    switch key {
    case .deleteBackward: return "delete.backward"
    case .deleteForward: return "delete.right"
    case .returnKey: return "return.left"
    case .capsLock: return "capslock.fill"
    default: return nil
    }
  }

  static func keyboardKeyLabel(_ key: RemappingKeyboardKey) -> String {
    switch key {
    case .escape: return OJDLocalized.string("keyboard.escape")
    case .tab: return OJDLocalized.string("keyboard.tab")
    case .capsLock: return OJDLocalized.string("keyboard.capsLock")
    case .space: return OJDLocalized.string("keyboard.space")
    case .returnKey: return OJDLocalized.string("keyboard.return")
    case .deleteBackward: return OJDLocalized.string("keyboard.delete")
    case .deleteForward:
      return OJDLocalized.string("keyboard.forwardDelete")
    case .arrowUp: return OJDLocalized.string("keyboard.upArrow")
    case .arrowDown: return OJDLocalized.string("keyboard.downArrow")
    case .arrowLeft: return OJDLocalized.string("keyboard.leftArrow")
    case .arrowRight: return OJDLocalized.string("keyboard.rightArrow")
    case .pageUp: return OJDLocalized.string("keyboard.pageUp")
    case .pageDown: return OJDLocalized.string("keyboard.pageDown")
    default: return humanized(key.rawValue)
    }
  }

  static func humanized(_ value: String) -> String {
    value.split(separator: "_").map { part in
      let value = String(part)
      return value.isEmpty ? value : value.prefix(1).uppercased() + value.dropFirst()
    }.joined(separator: " ")
  }
}
