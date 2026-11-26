public import Foundation

/// Driver for every family whose input is a fixed report layout: it decodes raw input reports by
/// the bit fields the ``ControllerInputLayouts`` name (a `HIDReportLayout` record's, or the family
/// description's) and drives rumble only through the rumble template.
///
/// It sends nothing at startup.
public final class ReportLayoutDriver: PhysicalProtocolDriver {
  /// Where a raw-USB rumble template sends its packets.
  public struct USBOutput: Equatable, Sendable {
    /// The OUT endpoint address of the packets.
    public let endpoint: UInt8
    /// The transfer timeout of the packets, in milliseconds.
    public let timeoutMilliseconds: Int

    /// Creates a description of the raw-USB output.
    public init(endpoint: UInt8, timeoutMilliseconds: Int) {
      self.endpoint = endpoint
      self.timeoutMilliseconds = timeoutMilliseconds
    }
  }

  /// The layouts; each input report is decoded by the one that selects it.
  let layouts: ControllerInputLayouts
  /// The rumble template; nil when the controller has no rumble.
  private let rumbleTemplate: RumbleOutputTemplate?
  /// The raw-USB output a raw-USB rumble template needs.
  private let usbOutput: USBOutput?
  /// What the family description advertises; a record layout advertises what it decodes.
  private let describedCapabilities: ControllerCapabilities?
  /// Per layout and hat source, whether its 8-way field has been nonzero in this session.
  private var hatSourceIsLive: [[Bool]]
  /// What each touching contact drives, by contact ID.
  private var touchRoles: [Int: ControllerInputLayout.Touch.Role] = [:]
  /// The state after the latest report.
  private var state = ControllerState.neutral
  /// The rumble of the latest rumble command, which a resend repeats.
  private var lastRumble = RumbleIntensities.off

  /// Creates a driver for the input layouts and an optional rumble template.
  ///
  /// A raw-USB template needs `usbOutput`; a HID template ignores it.
  public init(
    layouts: ControllerInputLayouts,
    rumbleTemplate: RumbleOutputTemplate? = nil,
    usbOutput: USBOutput? = nil,
    describedCapabilities: ControllerCapabilities? = nil
  ) {
    self.layouts = layouts
    self.rumbleTemplate = rumbleTemplate
    self.usbOutput = usbOutput
    self.describedCapabilities = describedCapabilities
    hatSourceIsLive = Self.idleHatSources(of: layouts)
  }

  /// Clears the state of the session: at-rest input, no rumble, no live hat source and no contact.
  public func resetProtocolState() {
    state = .neutral
    touchRoles = [:]
    lastRumble = .off
    hatSourceIsLive = Self.idleHatSources(of: layouts)
  }

  /// A live flag of `false` for every hat source of every layout.
  private static func idleHatSources(of layouts: ControllerInputLayouts) -> [[Bool]] {
    layouts.layouts.map { Array(repeating: false, count: $0.hat.count) }
  }

  /// The session plan: no startup, with a rumble resend when the template names an interval.
  public var sessionPlan: DriverSessionPlan {
    DriverSessionPlan().withRumbleResend(of: rumbleTemplate)
  }

  /// The last rumble again while a motor runs, when the template names a resend interval.
  public func keepAliveWrites() -> [PhysicalOutputWrite] {
    guard let rumbleTemplate else { return [] }
    return rumbleTemplate.resendWrites(after: lastRumble) { self.rumbleWrite(rumbleTemplate, $0) }
  }

  /// Builds the write of one template report: the template's own HID report, or a raw-USB packet
  /// to the driver's USB output.
  private func rumbleWrite(
    _ template: RumbleOutputTemplate,
    _ bytes: [UInt8]
  ) -> PhysicalOutputWrite {
    if case .hid(let report) = template.target { return report.write(bytes) }
    guard let usbOutput else {
      preconditionFailure("a raw-USB rumble template needs the driver's USB output")
    }
    return .usb(
      PhysicalUSBOutputPacket(
        endpoint: usbOutput.endpoint,
        bytes: bytes,
        timeoutMilliseconds: UInt32(usbOutput.timeoutMilliseconds)
      )
    )
  }
  /// The rumble motors of the template, or none without one.
  public var outputCapabilities: PhysicalControllerOutputCapabilities {
    rumbleTemplate?.outputCapabilities ?? .none
  }
  /// No default colour: the controller has no light.
  public var defaultColor: ControllerColor? { nil }

  /// Always nil: raw reports carry no logical connection.
  public func consumeInputConnectionStateChange() -> ControllerInputConnectionState? { nil }

  /// The family description's capabilities, or the controls of the layout.
  public var capabilities: ControllerCapabilities {
    describedCapabilities ?? ControllerCapabilities(controls: layouts.controls)
  }

  /// Encodes a rumble command through the rumble template; any other command, or any command
  /// without a template, is unsupported.
  public func encode(
    _ command: ControllerOutputCommand
  ) throws(ControllerOutputError) -> PhysicalOutputPlan {
    guard let rumbleTemplate else { throw .unsupportedCapability(command.capability) }
    let plan = try rumbleTemplate.encode(command) { self.rumbleWrite(rumbleTemplate, $0) }
    lastRumble = command.rumbleIntensities
    return plan
  }

  /// Decodes one input report into the full controller state by the layout that selects it.
  ///
  /// A report no layout selects is ignored. A layout changes only the controls it names; every
  /// other control keeps its last value.
  public func parse(report data: Data, receivedAt: MonotonicTimestamp) -> ControllerEvent? {
    let bytes = [UInt8](data)
    guard let layoutIndex = layouts.indexOfLayout(selecting: bytes) else { return nil }
    let layout = layouts.layouts[layoutIndex]
    var next = state
    for button in layout.buttons {
      next.set(button.control, pressed: button.fields.contains { $0.isSet(in: bytes) })
    }
    var sticks = [next.leftStick.x, next.leftStick.y, next.rightStick.x, next.rightStick.y]
    for axis in layout.axes {
      guard let index = Control.stickAxes.firstIndex(of: axis.control) else {
        continue
      }
      sticks[index] = BipolarValue(normalized: axis.value(in: bytes))
    }
    if !layout.hat.isEmpty { next.hat = hat(bytes, of: layout, at: layoutIndex) }
    if let trigger = layout.leftTrigger { next.leftTrigger = trigger.value(in: bytes) }
    if let trigger = layout.rightTrigger { next.rightTrigger = trigger.value(in: bytes) }
    if let touch = layout.touch { apply(touch, in: bytes, to: &next, sticks: &sticks) }
    next.leftStick = StickPosition(x: sticks[0], y: sticks[1])
    next.rightStick = StickPosition(x: sticks[2], y: sticks[3])
    state = next
    return ControllerEvent(timestamp: receivedAt, state: next)
  }

  /// Sets the controls the touch names from the contacts in `bytes`.
  ///
  /// A contact keeps the role of the place it first touched; a stick no contact drags centers.
  private func apply(
    _ touch: ControllerInputLayout.Touch,
    in bytes: [UInt8],
    to state: inout ControllerState,
    sticks: inout [BipolarValue]
  ) {
    let touches = touch.touches(in: bytes)
    touchRoles = touches.reduce(into: [:]) { roles, contact in
      roles[contact.id] =
        roles[contact.id] ?? touchRoles[contact.id] ?? touch.role(x: contact.x, y: contact.y)
    }
    let (held, deflection) = contactEffects(of: touch, touches: touches)
    for (slot, control) in Control.stickAxes.enumerated() {
      if let value = deflection[control] { sticks[slot] = BipolarValue(normalized: value) }
    }
    for control in Set(touch.spots.map(\.control)) {
      Self.setSpotControl(control, held: held, in: &state)
    }
  }

  /// The controls the contacts hold on spots, and each stick axis's deflection.
  private func contactEffects(
    of touch: ControllerInputLayout.Touch,
    touches: [(id: Int, x: Int, y: Int)]
  ) -> (held: Set<Control>, deflection: [Control: Float]) {
    var held: Set<Control> = []
    var deflection: [Control: Float] = [:]
    for stick in touch.sticks {
      deflection[stick.alongX.control] = 0
      deflection[stick.alongY.control] = 0
    }
    for contact in touches {
      switch touchRoles[contact.id, default: .none] {
      case .spot(let control): held.insert(control)
      case .stick(let index):
        let stick = touch.sticks[index]
        for (axis, offset) in [
          (stick.alongX, contact.x - stick.x), (stick.alongY, contact.y - stick.y),
        ] {
          let value = max(-1, min(1, Float(offset) / Float(stick.travel)))
          deflection[axis.control] = axis.isInverted ? -value : value
        }
      case .none: break
      }
    }
    return (held, deflection)
  }

  /// Sets `control` in `state` to whether a contact holds it.
  private static func setSpotControl(
    _ control: Control,
    held: Set<Control>,
    in state: inout ControllerState
  ) {
    switch control {
    case .leftTrigger:
      state.leftTrigger = UnipolarValue(normalized: held.contains(control) ? 1 : 0)
    case .rightTrigger:
      state.rightTrigger = UnipolarValue(normalized: held.contains(control) ? 1 : 0)
    case .dpadUp, .dpadDown, .dpadLeft, .dpadRight:
      state.hat = HatDirection(
        up: held.contains(.dpadUp),
        right: held.contains(.dpadRight),
        down: held.contains(.dpadDown),
        left: held.contains(.dpadLeft)
      )
    default: state.set(control, pressed: held.contains(control))
    }
  }

  /// The first source's direction that is not at rest.
  ///
  /// Every 8-way source is read, so each one's live flag tracks the whole session.
  private func hat(
    _ bytes: [UInt8],
    of layout: ControllerInputLayout,
    at layoutIndex: Int
  ) -> HatDirection {
    var result = HatDirection.neutral
    for (index, source) in layout.hat.enumerated() {
      let direction: HatDirection
      switch source {
      case .eightWay(let field, let neutralUntilNonzero):
        let value = field.value(in: bytes)
        if value != 0 { hatSourceIsLive[layoutIndex][index] = true }
        let directions = HatDirection.clockwiseFromNorth
        direction =
          (!neutralUntilNonzero || hatSourceIsLive[layoutIndex][index]) && value < directions.count
          ? directions[value] : .neutral
      case .directions(let up, let right, let down, let left):
        direction = HatDirection(
          up: up.isSet(in: bytes),
          right: right.isSet(in: bytes),
          down: down.isSet(in: bytes),
          left: left.isSet(in: bytes)
        )
      case .table(let field, let directions):
        direction = directions[field.value(in: bytes)] ?? .neutral
      }
      if result == .neutral { result = direction }
    }
    return result
  }
}

extension ReportLayoutDriver {
  /// Creates the driver of a family whose description holds the input layout.
  ///
  /// The rumble template is the record's when it sets one, otherwise the description's for
  /// `variant`; a raw-USB template sends to `outEndpoint` within the family's
  /// `usbTransferTimeoutMs`.
  public convenience init(
    describedBy family: PhysicalProtocolID,
    variant: PhysicalProtocolVariantID?,
    rumbleTemplate record: RumbleOutputTemplate?,
    outEndpoint: UInt8,
    tuning: ControllerTuning?
  ) {
    guard let layouts = family.protocolDescription.inputLayouts else {
      preconditionFailure("\(family.descriptionFileStem).plist sets no input layouts")
    }
    let template = family.rumbleTemplate(variant: variant, record: record)
    var usbOutput: USBOutput?
    if case .usb? = template?.target {
      usbOutput = USBOutput(
        endpoint: outEndpoint,
        timeoutMilliseconds: family.described(\.usbTransferTimeoutMilliseconds, in: tuning)
      )
    }
    self.init(
      layouts: layouts,
      rumbleTemplate: template,
      usbOutput: usbOutput,
      describedCapabilities: family.describedControls
    )
  }
}
