import Foundation
import OpenJoystickDriverKit

enum RuntimePresentation {
  static func permissionLabel(_ state: RuntimePermissionState) -> String {
    switch state {
    case .granted: return "Allowed"
    case .denied: return "Needs attention"
    case .unknown: return "Needs attention"
    case .unavailable: return "Unavailable"
    }
  }

  static func readinessLabel(_ readiness: RuntimeReadiness) -> String {
    switch readiness {
    case .ready: return "Ready"
    case .needsAttention: return "Needs attention"
    case .noController: return "Connect a controller"
    }
  }

  static func postEventAccessLabel(_ state: RemappingPostEventAccessState?) -> String {
    switch state {
    case .granted: return "Allowed"
    case .notAuthorized: return "Needs attention"
    case nil: return "Checking"
    }
  }

  static func deviceCountLabel(_ count: Int) -> String {
    count == 1 ? "1 controller connected" : "\(count) controllers connected"
  }

  static func profileLabel(_ profile: RemappingProfile) -> String { profile.name }

  static func profileScopeLabel(_ scope: RemappingApplicationScope) -> String {
    switch scope {
    case .global: return "All apps"
    case .application: return "A specific app"
    }
  }

  static func compatibilityLabel(_ identity: CompatibilityIdentity) -> String {
    switch identity {
    case .genericHID: return "Generic HID"
    case .sdl2_3: return "SDL2/3"
    case .appleGameController: return "Apple GameController"
    case .x360HID: return "Xbox 360 HID"
    case .xoneHID: return "Xbox One HID"
    }
  }

  static func sourceLabel(_ source: RemappingSource) -> String {
    switch source {
    case .button(let button): return buttonLabel(button)
    case .dpad(let direction): return "D-pad \(humanized(direction.rawValue))"
    case .axis(let axis): return axisLabel(axis)
    case .axisDirection(let axis, let direction):
      return "\(axisLabel(axis)) \(humanized(direction.rawValue))"
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
    case .mouseButton(let button): return "Mouse \(humanized(button.rawValue)) button"
    case .mouseMovement(let axis): return "Pointer \(humanized(axis.rawValue)) movement"
    case .scroll(let axis): return "Scroll \(humanized(axis.rawValue))"
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
    buttons.append(
      (Set(["auxiliary1", "aux1", "genericbutton1", "button1", "l2digital"]), .auxiliary1)
    )
    buttons.append(
      (Set(["auxiliary2", "aux2", "genericbutton2", "button2", "r2digital"]), .auxiliary2)
    )
    buttons.append((Set(["auxiliary3", "aux3", "genericbutton3", "button3"]), .auxiliary3))
    buttons.append((Set(["auxiliary4", "aux4", "genericbutton4", "button4"]), .auxiliary4))
    buttons.append((Set(["auxiliary5", "aux5", "genericbutton5", "button5"]), .auxiliary5))
    buttons.append((Set(["auxiliary6", "aux6", "genericbutton6", "button6"]), .auxiliary6))
    buttons.append((Set(["auxiliary7", "aux7", "genericbutton7", "button7"]), .auxiliary7))
    buttons.append((Set(["auxiliary8", "aux8", "genericbutton8", "button8"]), .auxiliary8))
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
    guard enabled else { return "Controller output is unavailable" }
    guard let status, !status.isEmpty else { return "Controller output is ready" }
    return status.lowercased().hasPrefix("error:")
      ? "Controller output needs attention" : "Controller output is ready"
  }

  static func userFacingError(_ error: Error) -> String {
    if let error = error as? ApplicationServiceRemappingRPCError {
      switch error.code {
      case .profileUpdateConflict: return "This profile changed elsewhere. Reload or keep editing."
      case .duplicateName: return "A profile with that name already exists."
      case .profileNotFound: return "That profile is no longer available."
      case .invalidProfile, .invalidArguments:
        return "Review the profile assignments and try again."
      case .unwritableLibrary, .librarySizeExceeded, .profileCountExceeded:
        return "The profile library could not be saved."
      case .routerEngineUnavailable, .routerLibraryUnavailable, .routerLibraryAndEngineUnavailable,
        .routerShutDown:
        return "Controller remapping is temporarily unavailable."
      default: return "OpenJoystickDriver couldn’t complete that action."
      }
    }
    if error is RuntimeProfileDraftError || error is RemappingValidationError {
      return "Review the profile assignments and try again."
    }
    switch error {
    case ApplicationServiceClientError.notConnected:
      return "OpenJoystickDriver isn’t available right now."
    case ApplicationServiceClientError.timeout:
      return "OpenJoystickDriver is taking too long to respond."
    case ApplicationServiceClientError.invalidResponse,
      ApplicationServiceGatewayError.invalidCompatibilityIdentity:
      return "OpenJoystickDriver returned an unexpected result."
    case ApplicationServiceGatewayError.compatibilityIdentityChangeRejected:
      return "The selected controller output could not be enabled."
    default: return "OpenJoystickDriver couldn’t complete that action."
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
    case .south: return "A / Cross"
    case .east: return "B / Circle"
    case .west: return "X / Square"
    case .north: return "Y / Triangle"
    case .leftShoulder: return "Left shoulder"
    case .rightShoulder: return "Right shoulder"
    case .leftStick: return "Left stick click"
    case .rightStick: return "Right stick click"
    case .start: return "Start"
    case .back: return "Back"
    case .guide: return "Guide"
    case .share: return "Share"
    case .options: return "Options"
    case .touchpad: return "Touchpad click"
    case .auxiliary1: return "Auxiliary 1"
    case .auxiliary2: return "Auxiliary 2"
    case .auxiliary3: return "Auxiliary 3"
    case .auxiliary4: return "Auxiliary 4"
    case .auxiliary5: return "Auxiliary 5"
    case .auxiliary6: return "Auxiliary 6"
    case .auxiliary7: return "Auxiliary 7"
    case .auxiliary8: return "Auxiliary 8"
    }
  }

  private static func axisLabel(_ axis: RemappingAxis) -> String {
    switch axis {
    case .leftStickX: return "Left stick horizontal"
    case .leftStickY: return "Left stick vertical"
    case .rightStickX: return "Right stick horizontal"
    case .rightStickY: return "Right stick vertical"
    case .leftTrigger: return "Left trigger"
    case .rightTrigger: return "Right trigger"
    }
  }

  private static func keyboardKeyLabel(_ key: RemappingKeyboardKey) -> String {
    switch key {
    case .escape: return "Escape"
    case .tab: return "Tab"
    case .capsLock: return "Caps Lock"
    case .space: return "Space"
    case .returnKey: return "Return"
    case .deleteBackward: return "Delete"
    case .deleteForward: return "Forward Delete"
    case .arrowUp: return "Up Arrow"
    case .arrowDown: return "Down Arrow"
    case .arrowLeft: return "Left Arrow"
    case .arrowRight: return "Right Arrow"
    case .pageUp: return "Page Up"
    case .pageDown: return "Page Down"
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
