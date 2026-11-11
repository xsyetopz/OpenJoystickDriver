import Foundation

/// Descriptor-driven driver for the `HIDDescriptor` protocol: HID controllers whose
/// report descriptor satisfies ``HIDDescriptorContract``.
///
/// Raw report layouts vary between devices, so IOKit decodes descriptor elements and this driver
/// folds them through a ``HIDUsageMap``: the record's, else the one the `HIDDescriptor`
/// description selects for the report descriptor's shape, else the description's standard map.
public final class HIDDescriptorDriver: PhysicalProtocolDriver {
  /// The controller model, named in the log.
  private let model: ControllerModelID
  /// The state after the latest element value.
  private var state = ControllerState.neutral
  /// Stick axes as decoded.
  ///
  /// HID Generic Desktop Y and Ry (and a Z/Rz layout's right-stick Rz) put the logical minimum up,
  /// so the decoded value is already Y down. An element carries one axis, so each keeps its pair's
  /// other.
  private var leftX: Float = 0
  /// The left stick Y position of the latest state.
  private var leftY: Float = 0
  /// The right stick X position of the latest state.
  private var rightX: Float = 0
  /// The right stick Y position of the latest state.
  private var rightY: Float = 0
  /// The direction of the latest hat usage value.
  private var hatDirection = HatDirection.neutral
  /// The D-pad directions the latest axis values press.
  private var axisDpadPressed: Set<Control> = []
  /// The usage map that binds HID usages to controls.
  let usageMap: HIDUsageMap
  /// The controls the map drives from usages the report descriptor declares.
  ///
  /// With no descriptor, the Xbox layout, with Guide unless the map reads the triggers as buttons.
  private let declaredControls: Set<Control>
  /// The triggers the map reads as buttons.
  private let declaredDigitalTriggers: Set<Control>
  /// The rumble template the record declares; nil for a record with no rumble write shown on
  /// hardware.
  private let rumbleTemplate: RumbleOutputTemplate?
  /// The rumble of the latest rumble command, which a resend repeats.
  private var lastRumble = RumbleIntensities.off

  /// Creates a driver whose usage map the `HIDDescriptor` description selects.
  public convenience init(model: ControllerModelID, reportDescriptor: Data? = nil) {
    self.init(model: model, reportDescriptor: reportDescriptor, usageMap: nil)
  }

  /// Creates the driver for a controller of `model`.
  ///
  /// `reportDescriptor` is the bound interface's HID report descriptor, when observed.
  /// `usageMap` is the record's map, if it declares one. Without one, the description's first
  /// shape that the descriptor's usages match selects the map, so a descriptor with Z and Rz, a
  /// Brake or Accelerator, and no Rx or Ry gets the Z/Rz layout (xpadneo
  /// `docs/descriptors/xb1s_linux.md`, `xbxs.md`, and `incompat/gamesir_g7_se.md`). Otherwise the
  /// description's standard map applies. `rumbleTemplate` is the record's rumble report.
  init(
    model: ControllerModelID,
    reportDescriptor: Data? = nil,
    usageMap: HIDUsageMap?,
    rumbleTemplate: RumbleOutputTemplate? = nil
  ) {
    self.model = model
    self.rumbleTemplate = rumbleTemplate
    let fields =
      reportDescriptor.flatMap { HIDReportDescriptorParser.parse(descriptor: Array($0))?.fields }
      ?? []
    let usages = Set(fields.map { HIDUsage(usagePage: $0.usagePage, usage: $0.usage) })
    let description = ProtocolDescription.bundled[.hidDescriptor]
    guard
      let resolved = usageMap
        ?? description?.hidUsageShapes.first(where: { $0.matches(usages) })?.map
        ?? description?.hidUsageMap
    else { preconditionFailure("Resources/Protocols/hid-descriptor.json declares no usage map") }
    self.usageMap = resolved
    if fields.isEmpty {
      // A broad map names usages, such as Capture, that most pads lack, so with no descriptor to
      // check them against the driver claims only the Xbox layout.
      let digital = resolved.digitalTriggers.contains(.leftTrigger)
      declaredControls = Control.xboxLayout.union(digital ? [] : [.guide])
      declaredDigitalTriggers = digital ? [.leftTrigger, .rightTrigger] : []
    } else {
      declaredControls = resolved.controls(declaring: usages)
      declaredDigitalTriggers = resolved.digitalTriggers(declaring: usages)
    }
  }

  /// Clears the state of the session: neutral input.
  public func resetProtocolState() {
    state = .neutral
    lastRumble = .off
    (leftX, leftY, rightX, rightY) = (0, 0, 0, 0)
    hatDirection = .neutral
    axisDpadPressed = []
  }

  /// The session plan: the driver parses IOKit-decoded element values, and repeats the rumble when
  /// the template names a resend interval.
  public var sessionPlan: DriverSessionPlan {
    DriverSessionPlan(parsesHIDElementValues: true).withRumbleResend(of: rumbleTemplate)
  }
  /// The rumble motors of the template, or none without one: the driver has no lighting or
  /// adaptive triggers.
  public var outputCapabilities: PhysicalControllerOutputCapabilities {
    rumbleTemplate?.outputCapabilities ?? .none
  }

  /// The last rumble again while a motor runs, when the template names a resend interval.
  public func keepAliveWrites() -> [PhysicalOutputWrite] {
    guard let rumbleTemplate, let intensities = rumbleTemplate.resendIntensities(after: lastRumble)
    else { return [] }
    return [rumbleTemplate.write(intensities)]
  }

  /// Encodes a rumble command through the rumble template; any other command, or any command
  /// without a template, is unsupported.
  public func encode(
    _ command: ControllerOutputCommand
  ) throws(ControllerOutputError) -> PhysicalOutputPlan {
    guard let rumbleTemplate else { throw .unsupportedCapability(command.capability) }
    let plan = try rumbleTemplate.encode(command) { rumbleTemplate.write($0) }
    lastRumble = command.rumbleIntensities
    return plan
  }
  /// No default colour: the controller has no light.
  public var defaultColor: ControllerColor? { nil }

  /// Always nil: element values carry no logical connection.
  public func consumeInputConnectionStateChange() -> ControllerInputConnectionState? { nil }

  /// The controls the usage map drives from usages the report descriptor declares, with the
  /// triggers the map reads as buttons as digital triggers.
  public var capabilities: ControllerCapabilities {
    ControllerCapabilities(
      controls: declaredControls,
      digitalTriggers: declaredDigitalTriggers
    )
  }

  /// Raw reports are handled through IOKit's descriptor-decoded element callback.
  public func parse(report _: Data, receivedAt _: MonotonicTimestamp) throws -> ControllerEvent? {
    nil
  }

  /// Folds one HID usage into the state through the usage map, preserving paired stick coordinates.
  ///
  /// A usage the map does not name, or one from another report than the map's, is ignored.
  public func parse(
    elementValue value: HIDElementValue,
    receivedAt: MonotonicTimestamp
  ) -> ControllerEvent? {
    let bindings = usageMap.bindings(page: value.usagePage, usage: value.usage)
    guard usageMap.reportID == nil || usageMap.reportID == value.reportID, !bindings.isEmpty
    else { return nil }
    var next = state
    for binding in bindings {
      switch binding {
      case .button(let control): next.set(control, pressed: value.integerValue != 0)
      case .hat(let hat):
        hatDirection = hat.direction(of: value)
        next.hat = combinedHat
      case .axis(let axis):
        let position = axis.value(of: value)
        switch axis.control {
        case .leftStickX: leftX = position
        case .leftStickY: leftY = position
        case .rightStickX: rightX = position
        case .rightStickY: rightY = position
        case .leftTrigger: next.leftTrigger = UnipolarValue(normalized: position)
        default: next.rightTrigger = UnipolarValue(normalized: position)
        }
        if !axis.isTrigger {
          next.leftStick = StickPosition(x: leftX, y: leftY)
          next.rightStick = StickPosition(x: rightX, y: rightY)
        }
      case .halfAxis(let halfAxis):
        let trigger = UnipolarValue(normalized: halfAxis.value(of: value))
        if halfAxis.control == .leftTrigger {
          next.leftTrigger = trigger
        } else {
          next.rightTrigger = trigger
        }
      case .axisDpad(let binding):
        if binding.isPressed(by: value) {
          axisDpadPressed.insert(binding.control)
        } else {
          axisDpadPressed.remove(binding.control)
        }
        next.hat = combinedHat
      case .axisButton(let binding):
        next.set(binding.control, pressed: binding.isPressed(by: value))
      case .buttonTrigger(let control):
        let trigger = UnipolarValue(normalized: value.integerValue != 0 ? 1 : 0)
        if control == .leftTrigger {
          next.leftTrigger = trigger
        } else {
          next.rightTrigger = trigger
        }
      }
    }
    state = next
    return ControllerEvent(timestamp: receivedAt, state: next)
  }

  /// The hat usage's direction with the directions the axes press: a direction either presses is
  /// pressed.
  private var combinedHat: HatDirection {
    let hat = hatDirection.components
    return HatDirection(
      up: hat.up || axisDpadPressed.contains(.dpadUp),
      right: hat.right || axisDpadPressed.contains(.dpadRight),
      down: hat.down || axisDpadPressed.contains(.dpadDown),
      left: hat.left || axisDpadPressed.contains(.dpadLeft)
    )
  }
}
