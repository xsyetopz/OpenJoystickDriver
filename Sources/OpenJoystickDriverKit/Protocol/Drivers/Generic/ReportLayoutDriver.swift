import Foundation

/// Driver for the `hid.report-layout` family: it decodes raw input reports by the byte offsets
/// and bit masks the controller record's ``ControllerInputLayout`` names, and drives rumble only
/// through the record's template. It sends nothing at startup.
public final class ReportLayoutDriver: PhysicalProtocolDriver {
  private let layout: ControllerInputLayout
  private let rumbleTemplate: RumbleOutputTemplate?
  /// Per hat source, whether its 8-way field has been nonzero in this session.
  private var hatSourceIsLive: [Bool]
  private var state = ControllerState.neutral

  /// Creates a driver for one record's input layout and optional rumble template.
  public init(layout: ControllerInputLayout, rumbleTemplate: RumbleOutputTemplate? = nil) {
    self.layout = layout
    self.rumbleTemplate = rumbleTemplate
    hatSourceIsLive = Array(repeating: false, count: layout.hat.count)
  }

  /// A new transport session starts from neutral input with no live hat.
  public func resetProtocolState() {
    state = .neutral
    hatSourceIsLive = Array(repeating: false, count: layout.hat.count)
  }

  public var sessionPlan: DriverSessionPlan { DriverSessionPlan() }
  public var outputCapabilities: PhysicalControllerOutputCapabilities {
    rumbleTemplate?.outputCapabilities ?? .none
  }
  public var defaultColor: ControllerColor? { nil }

  public func consumeInputConnectionStateChange() -> ControllerInputConnectionState? { nil }

  public var capabilities: ControllerCapabilities {
    ControllerCapabilities(controls: layout.controls)
  }

  public func encode(
    _ command: ControllerOutputCommand
  ) throws(ControllerOutputError) -> PhysicalOutputPlan {
    guard let rumbleTemplate else { throw .unsupportedCapability(command.capability) }
    return try rumbleTemplate.encode(command)
  }

  /// Decodes one input report into the full controller state; a report shorter than the layout
  /// or with another report ID is ignored.
  public func parse(report data: Data, receivedAt: MonotonicTimestamp) throws -> ControllerEvent? {
    let bytes = [UInt8](data)
    guard bytes.count >= layout.minimumLength,
      layout.reportID == nil || bytes[0] == layout.reportID
    else { return nil }
    var next = state
    for button in layout.buttons {
      next.set(button.control, pressed: button.fields.contains { $0.isSet(in: bytes) })
    }
    var sticks: [Float] = [0, 0, 0, 0]
    for axis in layout.axes {
      guard let index = ControllerInputLayout.stickAxes.firstIndex(of: axis.control) else {
        continue
      }
      sticks[index] = axis.value(in: bytes)
    }
    next.leftStick = StickPosition(x: sticks[0], yDown: sticks[1])
    next.rightStick = StickPosition(x: sticks[2], yDown: sticks[3])
    if !layout.hat.isEmpty { next.hat = hat(bytes) }
    if let trigger = layout.leftTrigger { next.leftTrigger = trigger.value(in: bytes) }
    if let trigger = layout.rightTrigger { next.rightTrigger = trigger.value(in: bytes) }
    state = next
    return ControllerEvent(timestamp: receivedAt, state: next)
  }

  /// The first source's direction that is not neutral. Every 8-way source is read, so each
  /// one's live flag tracks the whole session.
  private func hat(_ bytes: [UInt8]) -> HatDirection {
    var result = HatDirection.neutral
    for (index, source) in layout.hat.enumerated() {
      let direction: HatDirection
      switch source {
      case .eightWay(let field, let neutralUntilNonzero):
        let value = field.value(in: bytes)
        if value != 0 { hatSourceIsLive[index] = true }
        let directions = HatDirection.clockwiseFromNorth
        direction =
          (!neutralUntilNonzero || hatSourceIsLive[index]) && value < directions.count
          ? directions[value] : .neutral
      case .directions(let up, let right, let down, let left):
        direction = HatDirection(
          up: up.isSet(in: bytes),
          right: right.isSet(in: bytes),
          down: down.isSet(in: bytes),
          left: left.isSet(in: bytes)
        )
      }
      if result == .neutral { result = direction }
    }
    return result
  }
}
