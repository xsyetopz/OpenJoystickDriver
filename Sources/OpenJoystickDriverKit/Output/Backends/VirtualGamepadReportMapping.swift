import Foundation

/// The mapping from canonical and remapped controller state to the virtual gamepad state, shared
/// by the user-space dispatcher and the `VirtualHIDProfile` encoders.
enum VirtualGamepadReportMapping {
  /// The deadzone treatment of a controller's sticks.
  struct StickTransfer: Equatable, Sendable {
    /// The radius of the deadzone, as a share of full deflection.
    let deadzone: Float
    /// Whether the deflection past the deadzone is scaled up to the full range.
    let rescalesDeadzone: Bool
  }

  /// The stick treatment of `identifier`: the deadzone of its controller record with rescaling, or
  /// none.
  static func stickTransfer(for identifier: LogicalControllerID) -> StickTransfer {
    let catalog = DeviceCatalog.current.withLock { $0 }
    if let deadzone = catalog.record(for: identifier.model)?.tuning.stickDeadzone {
      return StickTransfer(deadzone: deadzone, rescalesDeadzone: true)
    }
    return StickTransfer(deadzone: 0, rescalesDeadzone: false)
  }

  /// How many frames may wait behind a send for the virtual device of `identifier`.
  static func frameQueueCapacity(for identifier: LogicalControllerID) -> Int {
    let catalog = DeviceCatalog.current.withLock { $0 }
    return frameQueueCapacity(of: catalog.record(for: identifier.model))
  }

  /// The effective `frameQueueCapacity` of `record`, else the `defaults.tuning` of its family's
  /// protocol description, else ``ControllerTuning/defaultFrameQueueCapacity``.
  ///
  /// A controller with no record gets the default.
  static func frameQueueCapacity(
    of record: DeviceRuntimeProfile?,
    descriptions: [PhysicalProtocolID: ProtocolDescription] = ProtocolDescription.bundled
  ) -> Int {
    guard let record else { return ControllerTuning.defaultFrameQueueCapacity }
    return record.tuning.frameQueueCapacity
      ?? descriptions[record.physicalProtocolID]?.tuning?.frameQueueCapacity
      ?? ControllerTuning.defaultFrameQueueCapacity
  }

  // MARK: - State mapping (called inside reportLock.withLock)

  /// Replaces every input field of `state` with `input`.
  ///
  /// This is the one canonical-state mapping; the dispatcher and the `VirtualHIDProfile` encoders
  /// share it.
  static func apply(
    _ input: ControllerState,
    stickTransfer: StickTransfer,
    rightPadIsRightStick: Bool = false,
    to state: inout VirtualGamepadState
  ) {
    let hat = hatValue(for: input.hat)
    state.buttons = GamepadHIDDescriptor.dpadButtonBits(for: hat)
    for control in input.pressed {
      let carried = virtualControl(control, rightPadIsRightStick: rightPadIsRightStick)
      if let bit = Self.buttonBit(for: carried) { state.buttons |= 1 << bit }
    }
    state.hat = hat
    state.leftTriggerPressed = input.pressed.contains(.leftTrigger)
    state.rightTriggerPressed = input.pressed.contains(.rightTrigger)
    // The report's Y and the canonical state's Y both point down.
    (state.leftStickX, state.leftStickY) = Self.stickValues(
      input.leftStick.x,
      input.leftStick.y,
      transfer: stickTransfer
    )
    (state.rightStickX, state.rightStickY) = Self.stickValues(
      input.rightStick.x,
      input.rightStick.y,
      transfer: stickTransfer
    )
    state.leftTrigger = Self.triggerValue(input.leftTrigger)
    state.rightTrigger = Self.triggerValue(input.rightTrigger)
  }

  /// Replaces every input field of `state` with a remapped gamepad state; remapped sticks pass
  /// through without a dead zone. A digital trigger flag follows its click or, by the
  /// normalization rule, its remapped axis, with `state`'s flag as the previous.
  static func apply(_ remapped: RemappingGamepadState, to state: inout VirtualGamepadState) {
    let hat = Self.hatValue(for: remapped.dpadDirection)
    state.buttons = GamepadHIDDescriptor.dpadButtonBits(for: hat)
    for button in remapped.buttons {
      if let bit = Self.buttonBit(for: button) { state.buttons |= 1 << bit }
    }
    state.hat = hat
    state.leftTriggerPressed = Self.remappedTriggerPressed(
      remapped.value(for: .leftTrigger),
      click: remapped.buttons.contains(.leftTrigger),
      wasPressed: state.leftTriggerPressed
    )
    state.rightTriggerPressed = Self.remappedTriggerPressed(
      remapped.value(for: .rightTrigger),
      click: remapped.buttons.contains(.rightTrigger),
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

  /// Whether the controller's right pad is its right stick, read from its resolved record: the
  /// controls it has (the family's, corrected by the record's `capabilityDelta`) include a right
  /// pad click and no right stick click.
  ///
  /// The classic Steam Controller's record (`remove: ["RightStickClick"]`) is that, so its pad
  /// click is R3. A Steam Deck or Triton has both controls, so its pad click stays its own control,
  /// which no virtual persona carries. A record or patch that adds or removes either control
  /// changes the answer.
  static func rightPadIsRightStick(_ identifier: LogicalControllerID) -> Bool {
    let catalog = DeviceCatalog.current.withLock { $0 }
    return rightPadIsRightStick(record: catalog.record(for: identifier.model))
  }

  /// ``rightPadIsRightStick(_:)`` for an already resolved record; false without one.
  static func rightPadIsRightStick(record: DeviceRuntimeProfile?) -> Bool {
    guard let record, let family = record.physicalProtocolID.protocolDescription.controls?.controls
    else { return false }
    let delta = record.capabilityDelta
    let controls = family.subtracting(delta.absentControls).union(delta.presentControls)
    return controls.contains(.rightTrackpadClick) && !controls.contains(.rightStickClick)
  }

  /// The control a virtual persona carries for `control`.
  ///
  /// This is the one rule the report mapping and the remapping passthrough share.
  static func virtualControl(_ control: Control, rightPadIsRightStick: Bool) -> Control {
    control == .rightTrackpadClick && rightPadIsRightStick ? .rightStickClick : control
  }

  /// The one control-to-bit table.
  ///
  /// A control is the same bit whatever the physical label: PS4 Share, PS Create and Xbox View
  /// are `back` (bit 9); PS Options, Xbox Menu and Switch Plus are `start` (bit 8); Xbox Share and
  /// Switch Capture are `capture` (bit 15).
  ///
  /// Carried by neither persona, so `nil`, for these reasons:
  /// - `touchpadClick`, `microphone`, paddles, `auxiliary1...8`, stick and trackpad touch,
  ///   `leftTrackpadClick`: no free button. The generic descriptor's 16 buttons are all used and
  ///   it is a published contract for 1209:4A4F, so another button needs a new PID. The
  ///   sdl-compatible Xbox One report has no slot SDL names for them.
  /// - `rightTrackpadClick`: a pad click is R3 only where the right pad is the right stick
  ///   (``virtualControl(_:rightPadIsRightStick:)``); elsewhere it has no slot.
  /// - `capture` is bit 15 in the generic persona only. The sdl-compatible report is the 18-byte
  ///   Xbox One GIP packet (``XboxOneGIPHIDReportFormat``), which has no Share field and clears
  ///   that bit.
  static func buttonBit(for control: Control) -> UInt32? {
    switch control {
    case .south: return 0
    case .east: return 1
    case .west: return 2
    case .north: return 3
    case .leftShoulder: return 4
    case .rightShoulder: return 5
    case .leftStickClick: return 6
    case .rightStickClick: return 7
    case .start: return 8
    case .back: return 9
    case .guide: return 10
    case .capture: return 15
    case .dpadUp, .dpadDown, .dpadLeft, .dpadRight, .leftStickX, .leftStickY, .rightStickX,
      .rightStickY, .leftTrigger, .rightTrigger, .rightTrackpadClick, .touchpadClick, .microphone,
      .leftPaddle1,
      .leftPaddle2, .rightPaddle1, .rightPaddle2, .auxiliary1, .auxiliary2, .auxiliary3,
      .auxiliary4, .auxiliary5, .auxiliary6, .auxiliary7, .auxiliary8, .leftStickTouch,
      .rightStickTouch, .leftTrackpadClick, .leftTrackpadTouch, .rightTrackpadTouch:
      return nil
    }
  }

  // MARK: - Axis + hat helpers

  /// Both axes of one stick through the radial deadzone: a stick whose deflection is inside it
  /// reads zero, and deflection past it is rescaled to the full range along the same direction.
  static func stickValues(
    _ x: BipolarValue,
    _ y: BipolarValue,
    transfer: StickTransfer
  ) -> (x: Int16, y: Int16) {
    let magnitude = hypotf(x.normalized, y.normalized)
    guard magnitude > transfer.deadzone else { return (0, 0) }
    guard transfer.rescalesDeadzone else { return (x.rawValue, y.rawValue) }
    let scale = (magnitude - transfer.deadzone) / (1 - transfer.deadzone) / magnitude
    func axis(_ value: BipolarValue) -> Int16 {
      Int16((value.normalized * scale).clamped(to: -1...1) * 32_767)
    }
    return (axis(x), axis(y))
  }

  /// The report's 15-bit trigger, scaled down with truncation.
  ///
  /// Every 8-bit source (`u = v * 257`) reaches exactly the value the float path gave it.
  static func triggerValue(_ value: UnipolarValue) -> Int16 {
    Int16(UInt32(value.rawValue) * UInt32(Int16.max) / UInt32(UInt16.max))
  }

  /// The 16-bit axis value of a remapped axis value, limited to -1...1.
  static func remappedAxisValue(_ value: Double) -> Int16 {
    let clamped = Float(value).clamped(to: -1...1)
    guard clamped != 0 else { return 0 }
    return Int16(clamped * 32_767)
  }

  /// Whether a remapped trigger counts as pressed: when `click` is set, or when the trigger button
  /// derivation reads `value` as pressed given `wasPressed`.
  static func remappedTriggerPressed(_ value: Double, click: Bool, wasPressed: Bool) -> Bool {
    click
      || TriggerButtonDerivation.isPressed(
        UnipolarValue(normalized: Float(value)),
        wasPressed: wasPressed
      )
  }

  /// The 15-bit trigger value of a remapped trigger value, limited to 0...1.
  static func remappedTriggerValue(_ value: Double) -> Int16 {
    Int16(Float(value).clamped(to: 0...1) * 32_767)
  }

  /// The descriptor's hat value for `direction`.
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
