import Foundation
import OpenJoystickDriverKit

extension RuntimePresentation {
  static func outputDetail(enabled: Bool?, status: VirtualOutputBackendStatus?) -> String? {
    guard let enabled else { return nil }
    guard enabled else {
      return OJDLocalized.string(
        "mapping.outputUnavailable",
        fallback: "Controller output is unavailable"
      )
    }
    return status?.isError == true
      ? OJDLocalized.string(
        "mapping.outputNeedsAttention",
        fallback: "Controller output needs attention"
      ) : OJDLocalized.string("mapping.outputReady", fallback: "Controller output is ready")
  }

  static func userFacingError(_ error: Error) -> String {
    if let error = error as? ApplicationServiceRemappingRPCError {
      switch error.code {
      case .profileUpdateConflict:
        return OJDLocalized.string(
          "error.profileChanged",
          fallback: "This profile changed elsewhere. Reload or keep editing."
        )
      case .duplicateName:
        return OJDLocalized.string(
          "error.duplicateProfile",
          fallback: "A profile with that name already exists."
        )
      case .profileNotFound:
        return OJDLocalized.string(
          "error.profileMissing",
          fallback: "That profile is no longer available."
        )
      case .invalidProfile, .invalidArguments:
        return OJDLocalized.string(
          "error.reviewAssignments",
          fallback: "Review the profile assignments and try again."
        )
      case .unwritableLibrary, .librarySizeExceeded, .profileCountExceeded:
        return OJDLocalized.string(
          "error.profileLibrarySave",
          fallback: "Your profiles could not be saved."
        )
      case .corruptLibrary:
        return OJDLocalized.string(
          "error.profileLibraryCorrupt",
          fallback: "The active profile list is damaged and could not be loaded."
        )
      case .joyConPairUnavailable:
        return OJDLocalized.string(
          "error.joyConPairUnavailable",
          fallback: "The selected Joy-Cons could not be paired. "
            + "Refresh connected controllers and try again."
        )
      case .routerEngineUnavailable, .routerLibraryUnavailable, .routerLibraryAndEngineUnavailable,
        .routerShutDown:
        return OJDLocalized.string(
          "error.remappingUnavailable",
          fallback: "Controller remapping is temporarily unavailable."
        )
      default:
        return OJDLocalized.string(
          "error.generic",
          fallback: "OpenJoystickDriver couldn't complete that action."
        )
      }
    }
    if error is RuntimeProfileDraftError || error is RemappingValidationError {
      return OJDLocalized.string(
        "error.reviewAssignments",
        fallback: "Review the profile assignments and try again."
      )
    }
    switch error {
    case ApplicationServiceClientError.notConnected:
      return OJDLocalized.string(
        "error.notAvailable",
        fallback: "OpenJoystickDriver isn't available right now."
      )
    case ApplicationServiceClientError.timeout:
      return OJDLocalized.string(
        "error.timeout",
        fallback: "OpenJoystickDriver is taking too long to respond."
      )
    case ApplicationServiceClientError.invalidResponse:
      return OJDLocalized.string(
        "error.unexpected",
        fallback: "OpenJoystickDriver returned an unexpected result."
      )
    default:
      return OJDLocalized.string(
        "error.generic",
        fallback: "OpenJoystickDriver couldn't complete that action."
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
      return OJDLocalized.string("mapping.leftFunctionButton", fallback: "Left function button")
    case .rightFunction:
      return OJDLocalized.string("mapping.rightFunctionButton", fallback: "Right function button")
    case .leftPaddle: return OJDLocalized.string("mapping.leftPaddle", fallback: "Left paddle")
    case .rightPaddle: return OJDLocalized.string("mapping.rightPaddle", fallback: "Right paddle")
    case .leftSL: return OJDLocalized.string("mapping.leftJoyConSL", fallback: "Left Joy-Con SL")
    case .leftSR: return OJDLocalized.string("mapping.leftJoyConSR", fallback: "Left Joy-Con SR")
    case .rightSL: return OJDLocalized.string("mapping.rightJoyConSL", fallback: "Right Joy-Con SL")
    case .rightSR: return OJDLocalized.string("mapping.rightJoyConSR", fallback: "Right Joy-Con SR")
    case .leftGrip: return OJDLocalized.string("mapping.leftGrip", fallback: "Left grip")
    case .rightGrip: return OJDLocalized.string("mapping.rightGrip", fallback: "Right grip")
    case .leftPadClick:
      return OJDLocalized.string("mapping.leftPadClick", fallback: "Left pad click")
    case .rightPadClick:
      return OJDLocalized.string("mapping.rightPadClick", fallback: "Right pad click")
    case .south: return OJDLocalized.string("mapping.buttonSouth", fallback: "A / Cross")
    case .east: return OJDLocalized.string("mapping.buttonEast", fallback: "B / Circle")
    case .west: return OJDLocalized.string("mapping.buttonWest", fallback: "X / Square")
    case .north: return OJDLocalized.string("mapping.buttonNorth", fallback: "Y / Triangle")
    case .leftShoulder:
      return OJDLocalized.string("mapping.leftShoulder", fallback: "Left shoulder")
    case .rightShoulder:
      return OJDLocalized.string("mapping.rightShoulder", fallback: "Right shoulder")
    case .leftStick:
      return OJDLocalized.string("mapping.leftStickClick", fallback: "Left stick click")
    case .rightStick:
      return OJDLocalized.string("mapping.rightStickClick", fallback: "Right stick click")
    case .start: return OJDLocalized.string("mapping.start", fallback: "Start")
    case .back: return OJDLocalized.string("mapping.back", fallback: "Back")
    case .guide: return OJDLocalized.string("mapping.guide", fallback: "Guide")
    case .share: return OJDLocalized.string("mapping.share", fallback: "Share")
    case .options: return OJDLocalized.string("mapping.options", fallback: "Options")
    case .touchpad: return OJDLocalized.string("mapping.touchpadClick", fallback: "Touchpad click")
    case .mute: return OJDLocalized.string("mapping.mute", fallback: "Mute")
    case .leftTriggerClick:
      return OJDLocalized.string("mapping.leftTriggerClick", fallback: "Left trigger click")
    case .rightTriggerClick:
      return OJDLocalized.string("mapping.rightTriggerClick", fallback: "Right trigger click")
    }
  }

  static func axisLabel(_ axis: RemappingAxis) -> String {
    switch axis {
    case .leftStickX:
      return OJDLocalized.string("mapping.leftStickHorizontal", fallback: "Left stick horizontal")
    case .leftStickY:
      return OJDLocalized.string("mapping.leftStickVertical", fallback: "Left stick vertical")
    case .rightStickX:
      return OJDLocalized.string("mapping.rightStickHorizontal", fallback: "Right stick horizontal")
    case .rightStickY:
      return OJDLocalized.string("mapping.rightStickVertical", fallback: "Right stick vertical")
    case .leftTrigger: return OJDLocalized.string("mapping.leftTrigger", fallback: "Left trigger")
    case .rightTrigger:
      return OJDLocalized.string("mapping.rightTrigger", fallback: "Right trigger")
    }
  }

  static func modifierLabel(_ modifier: RemappingKeyModifier) -> String {
    switch modifier {
    case .command: return OJDLocalized.string("keyboard.command", fallback: "Command")
    case .control: return OJDLocalized.string("keyboard.control", fallback: "Control")
    case .option: return OJDLocalized.string("keyboard.option", fallback: "Option")
    case .shift: return OJDLocalized.string("keyboard.shift", fallback: "Shift")
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
    case .escape: return OJDLocalized.string("keyboard.escape", fallback: "Escape")
    case .tab: return OJDLocalized.string("keyboard.tab", fallback: "Tab")
    case .capsLock: return OJDLocalized.string("keyboard.capsLock", fallback: "Caps Lock")
    case .space: return OJDLocalized.string("keyboard.space", fallback: "Space")
    case .returnKey: return OJDLocalized.string("keyboard.return", fallback: "Return")
    case .deleteBackward: return OJDLocalized.string("keyboard.delete", fallback: "Delete")
    case .deleteForward:
      return OJDLocalized.string("keyboard.forwardDelete", fallback: "Forward Delete")
    case .arrowUp: return OJDLocalized.string("keyboard.upArrow", fallback: "Up Arrow")
    case .arrowDown: return OJDLocalized.string("keyboard.downArrow", fallback: "Down Arrow")
    case .arrowLeft: return OJDLocalized.string("keyboard.leftArrow", fallback: "Left Arrow")
    case .arrowRight: return OJDLocalized.string("keyboard.rightArrow", fallback: "Right Arrow")
    case .pageUp: return OJDLocalized.string("keyboard.pageUp", fallback: "Page Up")
    case .pageDown: return OJDLocalized.string("keyboard.pageDown", fallback: "Page Down")
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
