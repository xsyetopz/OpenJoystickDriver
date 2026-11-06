import Foundation

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

  /// Clears the state of the session: neutral input, no rumble and no live hat source.
  public func resetProtocolState() {
    state = .neutral
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
    guard let rumbleTemplate, let intensities = rumbleTemplate.resendIntensities(after: lastRumble)
    else { return [] }
    return [rumbleWrite(rumbleTemplate, intensities)]
  }

  /// Builds the write of `intensities`: the template's own HID report, or a raw-USB packet to the
  /// driver's USB output.
  private func rumbleWrite(
    _ template: RumbleOutputTemplate,
    _ intensities: RumbleIntensities
  ) -> PhysicalOutputWrite {
    guard case .usb = template.target else { return template.write(intensities) }
    guard let usbOutput else {
      preconditionFailure("a raw-USB rumble template needs the driver's USB output")
    }
    return .usb(
      PhysicalUSBOutputPacket(
        endpoint: usbOutput.endpoint,
        bytes: template.reportBytes(intensities),
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
  public func parse(report data: Data, receivedAt: MonotonicTimestamp) throws -> ControllerEvent? {
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
    next.leftStick = StickPosition(x: sticks[0], y: sticks[1])
    next.rightStick = StickPosition(x: sticks[2], y: sticks[3])
    if !layout.hat.isEmpty { next.hat = hat(bytes, of: layout, at: layoutIndex) }
    if let trigger = layout.leftTrigger { next.leftTrigger = trigger.value(in: bytes) }
    if let trigger = layout.rightTrigger { next.rightTrigger = trigger.value(in: bytes) }
    state = next
    return ControllerEvent(timestamp: receivedAt, state: next)
  }

  /// The first source's direction that is not neutral.
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
      preconditionFailure("\(family.descriptionFileStem).json sets no input layouts")
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
