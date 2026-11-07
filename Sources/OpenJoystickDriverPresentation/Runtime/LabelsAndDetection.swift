import Foundation
import OpenJoystickDriverKit

/// Localized text for runtime states, remapping sources and destinations, and the detection of the
/// control that the user presses.
enum RuntimePresentation {
  /// Returns Allowed for a granted permission, and Needs Attention for any other.
  static func permissionLabel(_ state: RuntimePermissionState) -> String {
    switch state {
    case .granted: return OJDLocalized.string("status.allowed")
    case .denied: return OJDLocalized.string("status.needsAttention")
    case .unknown: return OJDLocalized.string("status.needsAttention")
    }
  }

  /// Returns the label of the readiness: Ready, Needs Attention or Connect a Controller.
  static func readinessLabel(_ readiness: RuntimeReadiness) -> String {
    switch readiness {
    case .ready: return OJDLocalized.string("status.ready")
    case .needsAttention:
      return OJDLocalized.string("status.needsAttention")
    case .noController:
      return OJDLocalized.string("status.connectController")
    }
  }

  /// Returns the label of the Post Event access: Allowed, Needs Attention, or Checking for nil.
  static func postEventAccessLabel(_ state: RemappingPostEventAccessState?) -> String {
    switch state {
    case .granted: return OJDLocalized.string("status.allowed")
    case .notAuthorized:
      return OJDLocalized.string("status.needsAttention")
    case nil: return OJDLocalized.string("status.checking")
    }
  }

  /// Returns the phrase for the number of connected controllers.
  static func deviceCountLabel(_ count: Int) -> String {
    OJDLocalized.plural(
      "status.controllerConnected",
      count: count
    )
  }

  /// Returns the name of the profile.
  static func profileLabel(_ profile: RemappingProfile) -> String { profile.name }

  /// Returns the label of the scope of a profile: all apps or a specific app.
  static func profileScopeLabel(_ scope: RemappingApplicationScope) -> String {
    switch scope {
    case .global: return OJDLocalized.string("ui.mapping.allApps")
    case .application: return OJDLocalized.string("ui.mapping.specificApp")
    }
  }

  /// The label for no virtual HID profile.
  static var noVirtualHIDProfileLabel: String {
    OJDLocalized.string("ui.virtualProfile.none")
  }

  /// Returns the label of how a virtual HID profile is selected: automatically, by an override, or
  /// automatically after an override is rejected.
  static func virtualHIDProfileSourceLabel(_ source: VirtualHIDProfileSource) -> String {
    switch source {
    case .automatic: OJDLocalized.string("ui.mapping.automatic")
    case .override: OJDLocalized.string("ui.virtualProfile.sourceOverride")
    case .automaticAfterRejecting:
      OJDLocalized.string("ui.virtualProfile.sourceAutomaticAfterRejecting")
    }
  }

  /// Returns the message of a failed virtual HID profile override request, which says whether the
  /// override is stored.
  static func virtualHIDProfileOverrideFailure(
    _ failure: VirtualHIDProfileOverrideFailure
  ) -> String {
    switch failure {
    case .unknownProfile:
      return OJDLocalized.string(
        "ui.virtualProfile.failure.unknownProfile"
      )
    case .controllerNotFound:
      return OJDLocalized.string(
        "ui.virtualProfile.failure.controllerNotFound"
      )
    case .overrideRejectedByController:
      return OJDLocalized.string(
        "ui.virtualProfile.failure.overrideRejected"
      )
    case .activationFailed(let detail):
      return OJDLocalized.formatted(
        "ui.virtualProfile.failure.activationFailed",
        detail
      )
    case .outputDisabled:
      return OJDLocalized.string(
        "ui.virtualProfile.failure.outputDisabled"
      )
    case .serverStopped:
      return OJDLocalized.string(
        "ui.virtualProfile.failure.serverStopped"
      )
    case .persistenceFailed:
      return OJDLocalized.string(
        "ui.virtualProfile.failure.persistenceFailed"
      )
    case .overrideFileKept(let path):
      return OJDLocalized.formatted(
        "ui.virtualProfile.failure.overrideFileKept",
        path
      )
    }
  }

  /// Returns the message of a refused controller server change, followed by the detail of the
  /// service when it has one.
  static func controllerServerFailure(
    _ failure: ControllerServerFailure,
    detail: String?
  ) -> String {
    let message: String
    switch failure {
    case .rawUSB, .notNative: message = OJDLocalized.string("error.E2023.message")
    case .noRecord: message = OJDLocalized.string("ui.controllers.server.noRecord")
    case .invalidRequest: message = OJDLocalized.string("ui.controllers.invalidRequest")
    case .invalidRecord: message = OJDLocalized.string("ui.controllers.server.invalidRecord")
    case .persistenceFailed:
      message = OJDLocalized.string("ui.controllers.server.persistenceFailed")
    }
    return [message, detail].compactMap { $0 }.joined(separator: " ")
  }

  /// Returns the message of a refused controller tuning change, followed by the detail of the
  /// service when it has one.
  static func controllerTuningFailure(
    _ failure: ControllerTuningFailure,
    detail: String?
  ) -> String {
    let message: String
    switch failure {
    case .noRecord: message = OJDLocalized.string("ui.controllers.server.noRecord")
    case .invalidRecord: message = OJDLocalized.string("ui.controllers.server.invalidRecord")
    case .notSet: message = OJDLocalized.string("ui.controllers.stickDeadzone.notSet")
    case .invalidRequest: message = OJDLocalized.string("ui.controllers.invalidRequest")
    case .persistenceFailed:
      message = OJDLocalized.string("ui.controllers.server.persistenceFailed")
    }
    return [message, detail].compactMap { $0 }.joined(separator: " ")
  }

  /// Returns the label of a remapping source.
  static func sourceLabel(_ source: RemappingSource) -> String {
    switch source {
    case .button(let button): return buttonLabel(button)
    case .dpad(let direction):
      return OJDLocalized.formatted(
        "ui.mapping.dpadDirection",
        humanized(direction.rawValue)
      )
    case .axis(let axis): return axisLabel(axis)
    case .axisDirection(let axis, let direction):
      return OJDLocalized.formatted(
        "ui.mapping.axisDirection",
        axisLabel(axis),
        humanized(direction.rawValue)
      )
    case .triggerStage(let trigger, let stage):
      return OJDLocalized.formatted(
        "ui.mapping.triggerStage",
        humanized(trigger.rawValue),
        humanized(stage.rawValue)
      )
    case .motionLean(let direction):
      return OJDLocalized.formatted(
        "ui.mapping.motionLean",
        humanized(direction.rawValue)
      )
    case .touchContact(let surface):
      return OJDLocalized.formatted(
        "ui.mapping.touchContact",
        touchSurfaceLabel(surface)
      )
    case .touchGrid(let grid):
      return OJDLocalized.formatted(
        "ui.mapping.touchGridCell",
        touchSurfaceLabel(grid.surface),
        grid.columns,
        grid.rows,
        grid.column + 1,
        grid.row + 1
      )
    case .touchSwipe(let swipe):
      return OJDLocalized.formatted(
        "ui.mapping.touchSwipe",
        touchSurfaceLabel(swipe.surface),
        humanized(swipe.direction.rawValue)
      )
    case .stickRegion(let region):
      let stick = OJDLocalized.string(
        region.stick == .left ? "ui.profiles.gyro.leftStick" : "ui.profiles.gyro.rightStick"
      )
      guard let from = region.fromDegrees, let to = region.toDegrees else {
        return OJDLocalized.formatted(
          "ui.mapping.stickRegion",
          stick,
          region.innerRadius,
          region.outerRadius
        )
      }
      return OJDLocalized.formatted(
        "ui.mapping.stickRegionSector",
        stick,
        region.innerRadius,
        region.outerRadius,
        from,
        to
      )
    case .triggerBand(let band):
      return OJDLocalized.formatted(
        "ui.mapping.triggerBand",
        OJDLocalized.string(
          band.trigger == .left ? "ui.profiles.trigger.left" : "ui.profiles.trigger.right"
        ),
        band.from,
        band.to
      )
    case .touchArea(let area):
      return OJDLocalized.formatted(
        "ui.mapping.touchArea",
        touchSurfaceLabel(area.surface),
        area.x,
        area.y,
        area.width,
        area.height
      )
    }
  }

  /// Returns the label of a touch surface.
  static func touchSurfaceLabel(_ surface: RemappingTouchSurface) -> String {
    switch surface {
    case .primary: OJDLocalized.string("ui.mapping.touchSurfacePrimary")
    case .left: OJDLocalized.string("ui.mapping.touchSurfaceLeft")
    case .right: OJDLocalized.string("ui.mapping.touchSurfaceRight")
    }
  }

  /// Returns the label of a remapping destination.
  ///
  /// A macro shows its name when `macros` holds it, and a layer when `layers` does.
  static func destinationLabel(
    _ destination: RemappingDestination,
    macros: [RemappingMacro] = [],
    layers: [RemappingLayer] = []
  ) -> String {
    switch destination {
    case .macro(let id):
      return macros.first { $0.id == id }?.name ?? OJDLocalized.string("term.macro")
    case .profileSwitch(.next): return OJDLocalized.string("ui.mapping.profileNext")
    case .profileSwitch(.previous): return OJDLocalized.string("ui.mapping.profilePrevious")
    case .profileSwitch(.profile): return OJDLocalized.string("ui.mapping.profileSwitch")
    case .layerSet(let layer, let mode):
      let key =
        switch mode {
        case .on: "ui.mapping.layerOn"
        case .off: "ui.mapping.layerOff"
        case .toggle: "ui.mapping.layerToggle"
        }
      return OJDLocalized.formatted(
        key,
        layers.first { $0.id == layer }?.name ?? OJDLocalized.string("term.layer")
      )
    case .pause(.on): return OJDLocalized.string("ui.mapping.pauseOn")
    case .pause(.off): return OJDLocalized.string("ui.mapping.pauseOff")
    case .pause(.toggle): return OJDLocalized.string("ui.mapping.pauseToggle")
    case .systemKey(let key): return key.rawValue
    case .systemAction(let action): return action.rawValue
    case .openApplication(let identifier): return identifier
    case .openURL(let url): return url
    case .runShortcut(let name): return name
    case .typeText(let text): return text
    case .gamepadAxis(let axis): return axisLabel(axis)
    case .gamepadDpad(let direction): return sourceLabel(.dpad(direction))
    case .gamepadButton(let button): return buttonLabel(button)
    case .keyboard(let key, let modifiers):
      let modifierLabel = modifiers.sorted { $0.rawValue < $1.rawValue }.map(Self.modifierLabel)
        .joined(separator: " + ")
      let keyLabel = keyboardKeyLabel(key)
      return modifierLabel.isEmpty ? keyLabel : "\(modifierLabel) + \(keyLabel)"
    case .mouseButton(let button):
      return OJDLocalized.formatted(
        "ui.mapping.mouseButton",
        humanized(button.rawValue)
      )
    case .mouseMovement(let axis):
      return OJDLocalized.formatted(
        "ui.mapping.pointerMovement",
        humanized(axis.rawValue)
      )
    case .scroll(let axis):
      return OJDLocalized.formatted(
        "ui.mapping.scroll",
        humanized(axis.rawValue)
      )
    case .physical(let output): return physicalOutputLabel(output)
    }
  }

  /// Returns the label of a physical output.
  static func physicalOutputLabel(_ output: RemappingPhysicalOutput) -> String {
    switch output {
    case .rumble(let motor, let intensity):
      return OJDLocalized.formatted(
        "ui.mapping.physicalRumble",
        upperCamelWords(motor.rawValue),
        String(Int((intensity * 100).rounded()))
      )
    case .playerIndicator(let indicator):
      return OJDLocalized.formatted(
        "ui.mapping.physicalPlayerIndicator",
        indicator == .off
          ? OJDLocalized.string("status.disabled")
          : String(indicator.rawValue)
      )
    case .color(let color):
      return OJDLocalized.formatted(
        "ui.mapping.physicalColor",
        String(format: "#%02X%02X%02X", color.red, color.green, color.blue)
      )
    case .brightness(let intensity):
      return OJDLocalized.formatted(
        "ui.mapping.physicalBrightness",
        String(Int((intensity * 100).rounded()))
      )
    case .adaptiveTrigger(let trigger, let effect):
      return OJDLocalized.formatted(
        "ui.mapping.physicalAdaptiveTrigger",
        humanized(trigger.rawValue),
        humanized(effect.kind.rawValue)
      )
    }
  }

  /// The buttons that automatic capture considers, in priority order.
  ///
  /// Guide, Home and the logo button are reserved for the operating system and are left out, as in
  /// the manual list of sources.
  private static let captureButtonOrder: [Control] = [
    .auxiliary1, .auxiliary2, .leftPaddle1, .rightPaddle1, .auxiliary3, .auxiliary4, .auxiliary5,
    .auxiliary6, .leftPaddle2, .rightPaddle2, .leftTrackpadClick, .rightTrackpadClick, .south,
    .east, .west, .north, .leftShoulder, .rightShoulder, .leftStickClick, .rightStickClick,
    .start, .back, .capture, .touchpadClick, .microphone, .leftTrigger, .rightTrigger,
  ]

  /// Returns the source that the state shows in use: an active touch, a pressed button or D-pad
  /// direction, or an axis moved at least half its range; nil when there is none.
  static func detectedSource(
    from state: ControllerState
  ) -> RemappingSource? {
    if let sample = state.touch.first(where: { $0.contacts.contains(where: \.isActive) }) {
      return .touchContact(RemappingTouchSurface(sample.surface))
    }
    return detectedButton(pressed: state.pressed, dpad: dpadDirections(state.hat))
      ?? detectedAxis(in: state)
  }

  /// Returns the source that the state `current` adds to `previous`: a touch that starts, a button
  /// or D-pad direction pressed since, or an axis that crosses half its range or reverses past it.
  ///
  /// A release gives nil.
  static func detectedTransition(
    from previous: ControllerState,
    to current: ControllerState
  ) -> RemappingSource? {
    let previousTouches = activeTouchSurfaces(previous)
    let currentTouches = activeTouchSurfaces(current)
    if let surface = RemappingTouchSurface.allCases.first(where: {
      currentTouches.contains($0) && !previousTouches.contains($0)
    }) {
      return .touchContact(surface)
    }
    if let source = detectedButton(
      pressed: current.pressed.subtracting(previous.pressed),
      dpad: dpadDirections(current.hat).subtracting(dpadDirections(previous.hat))
    ) {
      return source
    }
    let previousAxes = axisValues(previous)
    for (index, (currentValue, axis)) in axisValues(current).enumerated() {
      let previousValue = previousAxes[index].value
      let crossedActivation = abs(currentValue) >= 0.5 && abs(previousValue) < 0.5
      let changedDirection =
        abs(currentValue) >= 0.5 && abs(previousValue) >= 0.5
        && (previousValue < 0) != (currentValue < 0)
      guard crossedActivation || changedDirection else { continue }
      let direction: RemappingAxisDirection = currentValue < 0 ? .negative : .positive
      return .axisDirection(axis, direction)
    }

    // A source that becomes unrecognized or disappears is a release, not an assignment. Only
    // controls pressed since `previous` and axis activation or direction transitions count.
    return nil
  }

  /// Returns the first pressed button in capture order, else the first D-pad direction in the order
  /// up, down, left, right; nil when there is none.
  private static func detectedButton(
    pressed: Set<Control>,
    dpad: Set<RemappingDpadDirection>
  ) -> RemappingSource? {
    if let button = captureButtonOrder.first(where: pressed.contains) {
      return .button(button)
    }
    let order: [RemappingDpadDirection] = [.up, .down, .left, .right]
    return order.first(where: dpad.contains).map(RemappingSource.dpad)
  }

  /// Returns the first axis moved at least half its range, in the direction of the movement.
  private static func detectedAxis(in state: ControllerState) -> RemappingSource? {
    for (value, axis) in axisValues(state) where abs(value) >= 0.5 {
      let direction: RemappingAxisDirection = value < 0 ? .negative : .positive
      return .axisDirection(axis, direction)
    }
    return nil
  }

  /// Returns the axis values in the remapping frame; stick Y points down, as in the controller
  /// state.
  private static func axisValues(_ state: ControllerState) -> [(value: Float, axis: RemappingAxis)]
  {
    [
      (state.leftStick.x.normalized, .leftStickX), (state.leftStick.y.normalized, .leftStickY),
      (state.rightStick.x.normalized, .rightStickX), (state.rightStick.y.normalized, .rightStickY),
      (state.leftTrigger.normalized, .leftTrigger), (state.rightTrigger.normalized, .rightTrigger),
    ]
  }

  /// Returns the touch surfaces with an active contact.
  private static func activeTouchSurfaces(_ state: ControllerState) -> Set<RemappingTouchSurface> {
    Set(
      state.touch.compactMap { sample in
        sample.contacts.contains(where: \.isActive) ? RemappingTouchSurface(sample.surface) : nil
      }
    )
  }

  /// Returns the D-pad directions that the hat direction presses.
  static func dpadDirections(_ hat: HatDirection) -> Set<RemappingDpadDirection> {
    switch hat {
    case .neutral: []
    case .north: [.up]
    case .northEast: [.up, .right]
    case .east: [.right]
    case .southEast: [.down, .right]
    case .south: [.down]
    case .southWest: [.down, .left]
    case .west: [.left]
    case .northWest: [.up, .left]
    }
  }

}
