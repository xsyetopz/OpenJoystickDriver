import Foundation
import OpenJoystickDriverKit

enum RuntimePresentation {
  static func permissionLabel(_ state: RuntimePermissionState) -> String {
    switch state {
    case .granted: return OJDLocalized.string("status.allowed", fallback: "Allowed")
    case .denied: return OJDLocalized.string("common.needsAttention", fallback: "Needs attention")
    case .unknown: return OJDLocalized.string("common.needsAttention", fallback: "Needs attention")
    case .unavailable: return OJDLocalized.string("common.unavailable", fallback: "Unavailable")
    }
  }

  static func readinessLabel(_ readiness: RuntimeReadiness) -> String {
    switch readiness {
    case .ready: return OJDLocalized.string("status.ready", fallback: "Ready")
    case .needsAttention:
      return OJDLocalized.string("common.needsAttention", fallback: "Needs attention")
    case .noController:
      return OJDLocalized.string("status.connectController", fallback: "Connect a controller")
    }
  }

  static func postEventAccessLabel(_ state: RemappingPostEventAccessState?) -> String {
    switch state {
    case .granted: return OJDLocalized.string("status.allowed", fallback: "Allowed")
    case .notAuthorized:
      return OJDLocalized.string("common.needsAttention", fallback: "Needs attention")
    case nil: return OJDLocalized.string("status.checking", fallback: "Checking")
    }
  }

  static func deviceCountLabel(_ count: Int) -> String {
    OJDLocalized.plural(
      "status.controllerConnected",
      count: count,
      fallback: "%d controllers connected"
    )
  }

  static func profileLabel(_ profile: RemappingProfile) -> String { profile.name }

  static func profileScopeLabel(_ scope: RemappingApplicationScope) -> String {
    switch scope {
    case .global: return OJDLocalized.string("mapping.allApps", fallback: "All apps")
    case .application: return OJDLocalized.string("mapping.specificApp", fallback: "A specific app")
    }
  }

  static func compatibilityLabel(_ identity: CompatibilityIdentity) -> String {
    switch identity {
    case .automatic: return OJDLocalized.string("mapping.automatic", fallback: "Automatic")
    case .genericHID:
      return OJDLocalized.string("compatibility.genericHID", fallback: "Generic HID")
    case .sdl2_3: return OJDLocalized.string("compatibility.sdl2_3", fallback: "SDL2/3")
    case .appleGameController:
      return OJDLocalized.string(
        "compatibility.appleGameController",
        fallback: "Apple GameController"
      )
    case .xbox360HID:
      return OJDLocalized.string("compatibility.xbox360HID", fallback: "Xbox 360 HID")
    }
  }

  static func sourceLabel(_ source: RemappingSource) -> String {
    switch source {
    case .button(let button): return buttonLabel(button)
    case .dpad(let direction):
      return OJDLocalized.formatted(
        "mapping.dpadDirection",
        fallback: "D-pad %@",
        humanized(direction.rawValue)
      )
    case .axis(let axis): return axisLabel(axis)
    case .axisDirection(let axis, let direction):
      return OJDLocalized.formatted(
        "mapping.axisDirection",
        fallback: "%@ %@",
        axisLabel(axis),
        humanized(direction.rawValue)
      )
    }
  }

  static func destinationLabel(_ destination: RemappingDestination) -> String {
    switch destination {
    case .keyboard(let key, let modifiers):
      let modifierLabel = modifiers.sorted { $0.rawValue < $1.rawValue }.map {
        humanized($0.rawValue)
      }.joined(separator: " + ")
      let keyLabel = keyboardKeyLabel(key)
      return modifierLabel.isEmpty ? keyLabel : "\(modifierLabel) + \(keyLabel)"
    case .mouseButton(let button):
      return OJDLocalized.formatted(
        "mapping.mouseButton",
        fallback: "Mouse %@ button",
        humanized(button.rawValue)
      )
    case .mouseMovement(let axis):
      return OJDLocalized.formatted(
        "mapping.pointerMovement",
        fallback: "Pointer %@ movement",
        humanized(axis.rawValue)
      )
    case .scroll(let axis):
      return OJDLocalized.formatted(
        "mapping.scroll",
        fallback: "Scroll %@",
        humanized(axis.rawValue)
      )
    }
  }

  static func detectedSource(from state: DeviceInputState) -> RemappingSource? {
    let pressed = Set(state.pressedButtons.map(normalizedInputName))
    var buttons: [(Set<String>, RemappingButton)] = []
    buttons.append((Set(["a", "cross", "south", "buttona", "buttoncross"]), .south))
    buttons.append((Set(["b", "circle", "east", "buttonb", "buttoncircle"]), .east))
    buttons.append((Set(["x", "square", "west", "buttonx", "buttonsquare"]), .west))
    buttons.append((Set(["y", "triangle", "north", "buttony", "buttontriangle"]), .north))
    buttons.append((Set(["lb", "l1", "leftshoulder", "leftbumper"]), .leftShoulder))
    buttons.append((Set(["rb", "r1", "rightshoulder", "rightbumper"]), .rightShoulder))
    buttons.append((Set(["ls", "l3", "leftstick", "leftstickclick"]), .leftStick))
    buttons.append((Set(["rs", "r3", "rightstick", "rightstickclick"]), .rightStick))
    buttons.append((Set(["start", "menu"]), .start))
    buttons.append((Set(["back", "select", "view"]), .back))
    // Guide/Home/logo is reserved for the operating system and is intentionally excluded from
    // automatic capture, just like the manual SourceOption catalog.
    buttons.append((Set(["share", "create"]), .share))
    buttons.append((Set(["options", "pause"]), .options))
    buttons.append((Set(["touchpad", "touchpadclick"]), .touchpad))
    buttons.append((Set(["mute", "micmute", "microphonemute"]), .mute))
    buttons.append((Set(["l2digital", "lefttriggerclick"]), .leftTriggerClick))
    buttons.append((Set(["r2digital", "righttriggerclick"]), .rightTriggerClick))
    for (aliases, button) in buttons where !pressed.isDisjoint(with: aliases) {
      return .button(button)
    }

    var dpad: [(Set<String>, RemappingDpadDirection)] = []
    dpad.append((Set(["dpadup", "hatup", "up"]), .up))
    dpad.append((Set(["dpaddown", "hatdown", "down"]), .down))
    dpad.append((Set(["dpadleft", "hatleft", "left"]), .left))
    dpad.append((Set(["dpadright", "hatright", "right"]), .right))
    for (aliases, direction) in dpad where !pressed.isDisjoint(with: aliases) {
      return .dpad(direction)
    }

    var axes: [(Double, RemappingAxis)] = []
    axes.append((Double(state.leftStickX), .leftStickX))
    axes.append((Double(state.leftStickY), .leftStickY))
    axes.append((Double(state.rightStickX), .rightStickX))
    axes.append((Double(state.rightStickY), .rightStickY))
    axes.append((Double(state.leftTrigger), .leftTrigger))
    axes.append((Double(state.rightTrigger), .rightTrigger))
    for (value, axis) in axes {
      guard value.isFinite, abs(value) >= 0.5 else { continue }
      let direction: RemappingAxisDirection = value < 0 ? .negative : .positive
      return .axisDirection(axis, direction)
    }
    return nil
  }

  static func detectedTransition(from previous: DeviceInputState, to current: DeviceInputState)
    -> RemappingSource?
  {
    let previousButtons = Set(previous.pressedButtons.map(normalizedInputName))
    let currentButtons = Set(current.pressedButtons.map(normalizedInputName))
    let newlyPressed = currentButtons.subtracting(previousButtons)
    if !newlyPressed.isEmpty {
      var newlyPressedState = current
      newlyPressedState.pressedButtons = Array(newlyPressed)
      if let source = detectedSource(from: newlyPressedState) { return source }
    }

    var axes: [(Float, Float, RemappingAxis)] = []
    axes.append((previous.leftStickX, current.leftStickX, .leftStickX))
    axes.append((previous.leftStickY, current.leftStickY, .leftStickY))
    axes.append((previous.rightStickX, current.rightStickX, .rightStickX))
    axes.append((previous.rightStickY, current.rightStickY, .rightStickY))
    axes.append((previous.leftTrigger, current.leftTrigger, .leftTrigger))
    axes.append((previous.rightTrigger, current.rightTrigger, .rightTrigger))
    for (previousValue, currentValue, axis) in axes {
      guard currentValue.isFinite, previousValue.isFinite else { continue }
      let crossedActivation = abs(currentValue) >= 0.5 && abs(previousValue) < 0.5
      let changedDirection =
        abs(currentValue) >= 0.5 && abs(previousValue) >= 0.5
        && (previousValue < 0) != (currentValue < 0)
      guard crossedActivation || changedDirection else { continue }
      let direction: RemappingAxisDirection = currentValue < 0 ? .negative : .positive
      return .axisDirection(axis, direction)
    }

    // A source becoming unrecognized or disappearing is a release, not a new assignment.  Only
    // newly pressed aliases and axis activation/direction transitions above count as input.
    return nil
  }

  static func outputDetail(enabled: Bool?, status: String?) -> String? {
    guard let enabled else { return nil }
    guard enabled else {
      return OJDLocalized.string(
        "mapping.outputUnavailable",
        fallback: "Controller output is unavailable"
      )
    }
    guard let status, !status.isEmpty else {
      return OJDLocalized.string("mapping.outputReady", fallback: "Controller output is ready")
    }
    return status.lowercased().hasPrefix("error:")
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
          fallback: "The profile library could not be saved."
        )
      case .unsupportedLibraryVersion:
        return OJDLocalized.string(
          "error.profileLibraryVersion",
          fallback:
            "This profile library needs an update. Create a new profile or remove the old library file."
        )
      case .corruptLibrary:
        return OJDLocalized.string(
          "error.profileLibraryCorrupt",
          fallback: "The profile library is damaged and could not be loaded."
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
          fallback: "OpenJoystickDriver couldn’t complete that action."
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
        fallback: "OpenJoystickDriver isn’t available right now."
      )
    case ApplicationServiceClientError.timeout:
      return OJDLocalized.string(
        "error.timeout",
        fallback: "OpenJoystickDriver is taking too long to respond."
      )
    case ApplicationServiceClientError.invalidResponse,
      ApplicationServiceGatewayError.invalidCompatibilityIdentity:
      return OJDLocalized.string(
        "error.unexpected",
        fallback: "OpenJoystickDriver returned an unexpected result."
      )
    case ApplicationServiceGatewayError.compatibilityIdentityChangeRejected:
      return OJDLocalized.string(
        "error.selectedOutputEnableFailed",
        fallback: "The selected controller output could not be enabled."
      )
    default:
      return OJDLocalized.string(
        "error.generic",
        fallback: "OpenJoystickDriver couldn’t complete that action."
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

  private static func buttonLabel(_ button: RemappingButton) -> String {
    switch button {
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

  private static func axisLabel(_ axis: RemappingAxis) -> String {
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

  private static func keyboardKeyLabel(_ key: RemappingKeyboardKey) -> String {
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

  private static func humanized(_ value: String) -> String {
    value.split(separator: "_").map { part in
      let value = String(part)
      return value.isEmpty ? value : value.prefix(1).uppercased() + value.dropFirst()
    }.joined(separator: " ")
  }

  private static func normalizedInputName(_ value: String) -> String {
    value.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(
      String.init
    ).joined()
  }
}
