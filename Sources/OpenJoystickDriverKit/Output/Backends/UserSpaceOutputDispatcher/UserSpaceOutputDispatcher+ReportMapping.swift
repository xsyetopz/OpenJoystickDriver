import Foundation

extension UserSpaceOutputDispatcher {
  struct StickTransfer: Equatable, Sendable {
    let deadzone: Float
    let rescalesDeadzone: Bool
  }

  static func stickTransfer(for identifier: DeviceIdentifier) -> StickTransfer {
    if identifier.controllerIdentity.vendorID == 0x11C1
      && identifier.controllerIdentity.productID == 0x5600
    {
      return StickTransfer(deadzone: 0.02, rescalesDeadzone: true)
    }
    return StickTransfer(deadzone: 0, rescalesDeadzone: false)
  }

  // MARK: - State mapping (called inside reportLock.withLock)

  /// Replaces every input field of `state` with `input`. This is the one canonical-state
  /// mapping; the dispatcher and the `VirtualHIDProfile` encoders share it.
  static func apply(
    _ input: ControllerState,
    labels: ControllerButtonLabels,
    stickTransfer: StickTransfer,
    to state: inout VirtualGamepadState
  ) {
    let hat = hatValue(for: input.hat)
    state.buttons = GamepadHIDDescriptor.dpadButtonBits(for: hat)
    for control in input.pressed {
      if let bit = buttonBit(for: control, labels: labels) { state.buttons |= 1 << bit }
    }
    state.hat = hat
    state.leftTriggerPressed = input.pressed.contains(.leftTriggerButton)
    state.rightTriggerPressed = input.pressed.contains(.rightTriggerButton)
    // The report's Y points down; the canonical state's Y points up.
    state.leftStickX = Self.axisValue(input.leftStick.x, transfer: stickTransfer)
    state.leftStickY = Self.axisValue(
      BipolarValue(-input.leftStick.y.rawValue),
      transfer: stickTransfer
    )
    state.rightStickX = Self.axisValue(input.rightStick.x, transfer: stickTransfer)
    state.rightStickY = Self.axisValue(
      BipolarValue(-input.rightStick.y.rawValue),
      transfer: stickTransfer
    )
    state.leftTrigger = Self.triggerValue(input.leftTrigger)
    state.rightTrigger = Self.triggerValue(input.rightTrigger)
  }

  /// Replaces every input field of `state` with a remapped gamepad state; remapped sticks pass
  /// through without a dead zone. A digital trigger flag follows its click or, by the
  /// normalization rule, its remapped axis, with `state`'s flag as the previous.
  func apply(_ remapped: RemappingGamepadState, to state: inout VirtualGamepadState) {
    let hat = Self.hatValue(for: remapped.dpadDirection)
    state.buttons = GamepadHIDDescriptor.dpadButtonBits(for: hat)
    for button in remapped.buttons {
      if let bit = buttonBit(for: button) { state.buttons |= 1 << bit }
    }
    state.hat = hat
    state.leftTriggerPressed = Self.remappedTriggerPressed(
      remapped.value(for: .leftTrigger),
      click: remapped.buttons.contains(.leftTriggerClick),
      wasPressed: state.leftTriggerPressed
    )
    state.rightTriggerPressed = Self.remappedTriggerPressed(
      remapped.value(for: .rightTrigger),
      click: remapped.buttons.contains(.rightTriggerClick),
      wasPressed: state.rightTriggerPressed
    )
    state.leftStickX = Self.remappedAxisValue(remapped.value(for: .leftStickX))
    state.leftStickY = Self.remappedAxisValue(remapped.value(for: .leftStickY))
    state.rightStickX = Self.remappedAxisValue(remapped.value(for: .rightStickX))
    state.rightStickY = Self.remappedAxisValue(remapped.value(for: .rightStickY))
    state.leftTrigger = Self.remappedTriggerValue(remapped.value(for: .leftTrigger))
    state.rightTrigger = Self.remappedTriggerValue(remapped.value(for: .rightTrigger))
  }

  // MARK: - Button mapping (XInput semantic order)

  /// PlayStation Share (Create) reads as View and Nintendo Capture as Capture; both keep Share's
  /// bit 15, while standard View keeps Back's bit 9.
  static func buttonBit(for control: ControlID, labels: ControllerButtonLabels) -> UInt32? {
    switch control {
    case .faceSouth: return 0
    case .faceEast: return 1
    case .faceWest: return 2
    case .faceNorth: return 3
    case .leftShoulder: return 4
    case .rightShoulder: return 5
    case .leftStickClick: return 6
    case .rightStickClick, .rightTrackpadClick: return 7
    case .menu: return 8
    case .view: return labels == .playStation ? 15 : 9
    case .guide: return 10
    case .share, .capture: return 15
    case .dpad, .leftStickX, .leftStickY, .rightStickX, .rightStickY, .leftTrigger, .rightTrigger,
      .leftTriggerButton, .rightTriggerButton, .touchpadClick, .microphone, .paddleLeft1,
      .paddleLeft2, .paddleRight1, .paddleRight2, .auxiliary1, .auxiliary2, .auxiliary3,
      .auxiliary4, .auxiliary5, .auxiliary6, .auxiliary7, .auxiliary8, .leftStickTouch,
      .rightStickTouch, .leftTrackpadClick, .leftTrackpadTouch, .rightTrackpadTouch:
      return nil
    }
  }

  func buttonBit(for button: RemappingButton) -> UInt32? {
    switch button {
    case .south: return 0
    case .east: return 1
    case .west: return 2
    case .north: return 3
    case .leftShoulder: return 4
    case .rightShoulder: return 5
    case .leftStick: return 6
    case .rightStick: return 7
    case .start, .options: return 8
    case .back: return 9
    case .guide: return 10
    case .share: return 15
    case .touchpad, .mute, .leftTriggerClick, .rightTriggerClick, .leftGrip, .rightGrip,
      .leftPadClick, .rightPadClick, .leftSL, .leftSR, .rightSL, .rightSR, .leftFunction,
      .rightFunction, .leftPaddle, .rightPaddle:
      return nil
    }
  }

  // MARK: - Axis + hat helpers

  static func axisValue(_ value: BipolarValue, transfer: StickTransfer) -> Int16 {
    let normalized = value.normalized
    let magnitude = abs(normalized)
    guard magnitude > transfer.deadzone else { return 0 }
    guard transfer.rescalesDeadzone else { return value.rawValue }
    let rescaled = (magnitude - transfer.deadzone) / (1 - transfer.deadzone)
    return Int16(copysignf(rescaled, normalized) * 32_767)
  }

  /// The report's 15-bit trigger, scaled down with truncation. Every 8-bit source (`u = v * 257`)
  /// reaches exactly the value the float path gave it.
  static func triggerValue(_ value: UnipolarValue) -> Int16 {
    Int16(UInt32(value.rawValue) * UInt32(Int16.max) / UInt32(UInt16.max))
  }

  static func remappedAxisValue(_ value: Double) -> Int16 {
    let clamped = Float(value).clamped(to: -1...1)
    guard clamped != 0 else { return 0 }
    return Int16(clamped * 32_767)
  }

  static func remappedTriggerPressed(_ value: Double, click: Bool, wasPressed: Bool) -> Bool {
    click
      || TriggerButtonDerivation.isPressed(
        UnipolarValue(normalized: Float(value)),
        wasPressed: wasPressed
      )
  }

  static func remappedTriggerValue(_ value: Double) -> Int16 {
    Int16(Float(value).clamped(to: 0...1) * 32_767)
  }

  static func hatValue(for direction: HatDirection) -> GamepadHIDDescriptor.Hat {
    switch direction {
    case .neutral: return .neutral
    case .north: return .north
    case .northEast: return .northEast
    case .east: return .east
    case .southEast: return .southEast
    case .south: return .south
    case .southWest: return .southWest
    case .west: return .west
    case .northWest: return .northWest
    }
  }
}
