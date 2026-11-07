import Foundation
import OpenJoystickDriverKit

extension RuntimePresentation {
  /// Returns the sentence about the virtual controller output: unavailable while it is off,
  /// otherwise needs attention for a backend error, or ready; nil when `enabled` is nil.
  static func outputDetail(enabled: Bool?, status: VirtualOutputBackendStatus?) -> String? {
    guard let enabled else { return nil }
    guard enabled else {
      return OJDLocalized.string(
        "ui.mapping.outputUnavailable"
      )
    }
    return status?.isError == true
      ? OJDLocalized.string(
        "ui.mapping.outputNeedsAttention"
      ) : OJDLocalized.string("ui.mapping.outputReady")
  }

  /// Returns the message for `error`.
  ///
  /// A remapping error from the service ends with its code, such as "(E3013)", so that a report
  /// names it and `ojd explain` can look it up.
  static func userFacingError(_ error: Error) -> String {
    let message = userFacingMessage(error)
    guard let error = error as? ApplicationServiceRemappingRPCError else { return message }
    return OJDLocalized.formatted(
      "ui.error.withCode",
      message,
      error.code.errorCode.rawValue
    )
  }

  /// Returns the message for `error` without a code.
  private static func userFacingMessage(_ error: Error) -> String {
    if let error = error as? ApplicationServiceRemappingRPCError {
      switch error.code {
      case .profileUpdateConflict:
        return OJDLocalized.string(
          "ui.error.profileChanged"
        )
      case .duplicateName:
        return OJDLocalized.string(
          "ui.error.duplicateProfile"
        )
      case .profileNotFound:
        return OJDLocalized.string(
          "ui.error.profileMissing"
        )
      case .invalidProfile, .invalidArguments:
        return OJDLocalized.string(
          "ui.error.reviewAssignments"
        )
      case .unwritableLibrary, .librarySizeExceeded, .profileCountExceeded:
        return OJDLocalized.string(
          "ui.error.profileLibrarySave"
        )
      case .corruptLibrary:
        return OJDLocalized.string(
          "ui.error.profileLibraryCorrupt"
        )
      case .joyConPairUnavailable:
        return OJDLocalized.string(
          "ui.error.joyConPairUnavailable"
        )
      case .packageProfileReadOnly:
        return OJDLocalized.string(
          "error.E3029.message"
        )
      case .routerEngineUnavailable, .routerLibraryUnavailable, .routerLibraryAndEngineUnavailable,
        .routerShutDown:
        return OJDLocalized.string(
          "ui.error.remappingUnavailable"
        )
      default:
        return OJDLocalized.string(
          "ui.error.generic"
        )
      }
    }
    if error is RuntimeProfileDraftError || error is RemappingValidationError {
      return OJDLocalized.string(
        "ui.error.reviewAssignments"
      )
    }
    switch error {
    case ApplicationServiceClientError.notConnected:
      return OJDLocalized.string(
        "ui.error.notAvailable"
      )
    case ApplicationServiceClientError.timeout:
      return OJDLocalized.string(
        "ui.error.timeout"
      )
    case ApplicationServiceClientError.invalidResponse:
      return OJDLocalized.string(
        "ui.error.unexpected"
      )
    default:
      return OJDLocalized.string(
        "ui.error.generic"
      )
    }
  }

  /// Returns whether the error means that the service or the profile engine cannot be reached: not
  /// connected, timed out, or a stopped or unavailable router.
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

  /// Returns the label of a control, or its raw name for a control without a label.
  static func buttonLabel(_ button: Control) -> String {
    switch button {
    case .auxiliary1:
      return OJDLocalized.string("ui.mapping.leftFunctionButton")
    case .auxiliary2:
      return OJDLocalized.string("ui.mapping.rightFunctionButton")
    case .leftPaddle1: return OJDLocalized.string("ui.mapping.leftPaddle")
    case .rightPaddle1: return OJDLocalized.string("ui.mapping.rightPaddle")
    case .auxiliary3: return OJDLocalized.string("ui.mapping.leftJoyConSL")
    case .auxiliary4: return OJDLocalized.string("ui.mapping.leftJoyConSR")
    case .auxiliary5: return OJDLocalized.string("ui.mapping.rightJoyConSL")
    case .auxiliary6: return OJDLocalized.string("ui.mapping.rightJoyConSR")
    case .leftPaddle2: return OJDLocalized.string("ui.mapping.leftGrip")
    case .rightPaddle2: return OJDLocalized.string("ui.mapping.rightGrip")
    case .leftTrackpadClick:
      return OJDLocalized.string("ui.mapping.leftPadClick")
    case .rightTrackpadClick:
      return OJDLocalized.string("ui.mapping.rightPadClick")
    case .south: return OJDLocalized.string("ui.mapping.buttonSouth")
    case .east: return OJDLocalized.string("ui.mapping.buttonEast")
    case .west: return OJDLocalized.string("ui.mapping.buttonWest")
    case .north: return OJDLocalized.string("ui.mapping.buttonNorth")
    case .leftShoulder:
      return OJDLocalized.string("ui.mapping.leftShoulder")
    case .rightShoulder:
      return OJDLocalized.string("ui.mapping.rightShoulder")
    case .leftStickClick:
      return OJDLocalized.string("ui.mapping.leftStickClick")
    case .rightStickClick:
      return OJDLocalized.string("ui.mapping.rightStickClick")
    case .start: return OJDLocalized.string("ui.mapping.start")
    case .back: return OJDLocalized.string("ui.mapping.back")
    case .guide: return OJDLocalized.string("ui.mapping.guide")
    case .capture: return OJDLocalized.string("ui.mapping.share")
    case .touchpadClick: return OJDLocalized.string("ui.mapping.touchpadClick")
    case .microphone: return OJDLocalized.string("ui.mapping.mute")
    case .leftTrigger:
      return OJDLocalized.string("ui.mapping.leftTriggerClick")
    case .rightTrigger:
      return OJDLocalized.string("ui.mapping.rightTriggerClick")
    case .dpadUp, .dpadDown, .dpadLeft, .dpadRight, .leftStickX, .leftStickY, .rightStickX,
      .rightStickY, .auxiliary7, .auxiliary8, .leftStickTouch, .rightStickTouch,
      .leftTrackpadTouch, .rightTrackpadTouch, .pointerX, .pointerY, .pointerTracking:
      return button.rawValue
    }
  }

  /// Returns the label of an axis.
  static func axisLabel(_ axis: RemappingAxis) -> String {
    switch axis {
    case .leftStickX:
      return OJDLocalized.string("ui.mapping.leftStickHorizontal")
    case .leftStickY:
      return OJDLocalized.string("ui.mapping.leftStickVertical")
    case .rightStickX:
      return OJDLocalized.string("ui.mapping.rightStickHorizontal")
    case .rightStickY:
      return OJDLocalized.string("ui.mapping.rightStickVertical")
    case .leftTrigger: return OJDLocalized.string("ui.mapping.leftTrigger")
    case .rightTrigger:
      return OJDLocalized.string("ui.mapping.rightTrigger")
    }
  }

  /// Returns the label of a key modifier.
  static func modifierLabel(_ modifier: RemappingKeyModifier) -> String {
    switch modifier {
    case .meta: return OJDLocalized.string("term.key.meta")
    case .control: return OJDLocalized.string("term.key.control")
    case .alt: return OJDLocalized.string("term.key.alt")
    case .shift: return OJDLocalized.string("term.key.shift")
    }
  }

  /// Returns the SF Symbol name of a key modifier.
  static func modifierSystemSymbolName(_ modifier: RemappingKeyModifier) -> String {
    switch modifier {
    case .meta: return "command"
    case .control: return "control"
    case .alt: return "option"
    case .shift: return "shift"
    }
  }

  /// Returns the SF Symbol name of a key that has one, or nil.
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

  /// Returns an alternative SF Symbol name to try when the preferred symbol does not exist on this
  /// macOS, or nil.
  static func keyboardSystemSymbolFallbackName(_ key: RemappingKeyboardKey) -> String? {
    switch key {
    case .deleteBackward: return "delete.backward"
    case .deleteForward: return "delete.right"
    case .returnKey: return "return.left"
    case .capsLock: return "capslock.fill"
    default: return nil
    }
  }

  /// Returns the label of a key: its name for the special keys, otherwise its humanized raw value.
  static func keyboardKeyLabel(_ key: RemappingKeyboardKey) -> String {
    switch key {
    case .escape: return OJDLocalized.string("term.key.escape")
    case .tab: return OJDLocalized.string("term.key.tab")
    case .capsLock: return OJDLocalized.string("term.key.capsLock")
    case .space: return OJDLocalized.string("term.key.space")
    case .returnKey: return OJDLocalized.string("term.key.return")
    case .deleteBackward: return OJDLocalized.string("term.key.delete")
    case .deleteForward:
      return OJDLocalized.string("term.key.forwardDelete")
    case .arrowUp: return OJDLocalized.string("term.key.upArrow")
    case .arrowDown: return OJDLocalized.string("term.key.downArrow")
    case .arrowLeft: return OJDLocalized.string("term.key.leftArrow")
    case .arrowRight: return OJDLocalized.string("term.key.rightArrow")
    case .pageUp: return OJDLocalized.string("term.key.pageUp")
    case .pageDown: return OJDLocalized.string("term.key.pageDown")
    default: return humanized(key.rawValue)
    }
  }

  /// Returns an UpperCamelCase value as words: a word starts at each capital that follows a
  /// lowercase letter or digit, so `LowFrequency` is "Low Frequency".
  static func upperCamelWords(_ value: String) -> String {
    humanized(
      value.replacingOccurrences(
        of: "([a-z0-9])([A-Z])",
        with: "$1_$2",
        options: .regularExpression
      )
    )
  }

  /// Returns an underscore-separated value as capitalized words.
  static func humanized(_ value: String) -> String {
    value.split(separator: "_").map { part in
      let value = String(part)
      return value.isEmpty ? value : value.prefix(1).uppercased() + value.dropFirst()
    }.joined(separator: " ")
  }
}
