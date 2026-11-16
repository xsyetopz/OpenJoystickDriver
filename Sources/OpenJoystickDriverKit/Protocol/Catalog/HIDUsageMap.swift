import Foundation

/// What a HID usage drives: the typed form of a record's `input.hidUsageMap`.
///
/// A map names each usage it reads by page and usage ID and binds it to a canonical control as a
/// button, an axis, one half of an axis or a hat switch. ``HIDDescriptorDriver`` folds IOKit's
/// decoded element values through it; a usage the map does not name is ignored.
struct HIDUsageMap: Equatable, Sendable {
  /// One side of an element's range, from its center to one end.
  enum Half: String, Sendable {
    /// From the center to the logical maximum.
    case positive = "Positive"
    /// From the center to the logical minimum.
    case negative = "Negative"
  }

  /// A usage bound to a button, an axis, one half of an axis or a hat switch.
  enum Binding: Equatable, Sendable {
    /// Pressed while the element value is nonzero.
    case button(Control)
    /// Drives a stick or trigger axis.
    case axis(Axis)
    /// Drives the hat switch.
    case hat(Hat)
    /// Drives a trigger from one half of the element's range.
    case halfAxis(HalfAxis)
    /// Presses a D-pad direction while the travel of one half is at or past a threshold.
    case axisDpad(HalfThreshold)
    /// Presses a button while the travel of one half is at or past a threshold.
    case axisButton(HalfThreshold)
    /// Drives a trigger to 1 while the element value is nonzero, else 0.
    case buttonTrigger(Control)

    /// The half the binding reads; nil for a binding that reads the whole element.
    var half: Half? {
      switch self {
      case .halfAxis(let binding): binding.half
      case .axisDpad(let binding), .axisButton(let binding): binding.half
      case .button, .axis, .hat, .buttonTrigger: nil
      }
    }
  }

  /// A stick or trigger axis.
  struct Axis: Equatable, Sendable {
    /// One of the four stick axes or a trigger.
    let control: Control
    /// Reverses the axis: a stick is negated, a trigger reads one minus its value.
    let isInverted: Bool
    /// The raw range that scales to the full axis; nil takes the element's logical range.
    let range: ClosedRange<Int>?
    /// A stick reads 0 while its magnitude is within this fraction of full deflection, and a
    /// trigger while it is within this fraction of full pull; the rest rescales to the full range.
    let deadZone: Float?

    /// Whether the axis is a trigger rather than a stick.
    var isTrigger: Bool { control == .leftTrigger || control == .rightTrigger }

    /// The element value on this axis: a stick in -1...1 and a trigger in 0...1.
    ///
    /// A span of zero reads 0.
    func value(of element: HIDElementValue) -> Float {
      let low = range?.lowerBound ?? element.logicalMinimum
      let high = range?.upperBound ?? element.logicalMaximum
      guard high > low else { return 0 }
      let unit = Float(element.integerValue - low) / Float(high - low)
      if isTrigger {
        let pull = min(1, max(0, unit))
        return Self.applying(deadZone, to: isInverted ? 1 - pull : pull)
      }
      let deflection = min(1, max(-1, unit * 2 - 1))
      return Self.applying(deadZone, to: isInverted ? -deflection : deflection)
    }

    /// Zeroes a `value` whose magnitude is within `deadZone` and rescales the rest to the full
    /// range; a nil dead zone leaves it unchanged.
    private static func applying(_ deadZone: Float?, to value: Float) -> Float {
      guard let deadZone else { return value }
      let magnitude = abs(value)
      guard magnitude > deadZone else { return 0 }
      let rescaled = (magnitude - deadZone) / (1 - deadZone)
      return value < 0 ? -rescaled : rescaled
    }
  }

  /// One half of an element's range, rescaled to a trigger's 0...1.
  struct HalfAxis: Equatable, Sendable {
    /// The half the trigger reads.
    let half: Half
    /// `LeftTrigger` or `RightTrigger`.
    let control: Control
    /// Whether the trigger reads one minus the travel.
    let isInverted: Bool

    /// The trigger position for `element`.
    func value(of element: HIDElementValue) -> Float {
      let travel = half.travel(of: element)
      return isInverted ? 1 - travel : travel
    }
  }

  /// One half of an element's range and the travel at which it presses a control.
  struct HalfThreshold: Equatable, Sendable {
    /// The half that presses the control.
    let half: Half
    /// The control the half presses.
    let control: Control
    /// The travel, above 0 and below 1, at or past which the control is pressed.
    let threshold: Float

    /// Whether the travel of `element` is at or past the threshold.
    func isPressed(by element: HIDElementValue) -> Bool { half.travel(of: element) >= threshold }
  }

  /// A hat switch: eight directions from north, clockwise, then a null state.
  struct Hat: Equatable, Sendable {
    /// The eight direction values plus the range's first as north: `0...7` or `1...8`.
    ///
    /// Nil takes the element's logical minimum as north.
    let range: ClosedRange<Int>?

    /// The hat direction of `element`; a value outside the eight direction values is neutral.
    func direction(of element: HIDElementValue) -> HatDirection {
      let position = element.integerValue - (range?.lowerBound ?? element.logicalMinimum)
      let directions: [HatDirection] = [
        .north, .northEast, .east, .southEast, .south, .southWest, .west, .northWest,
      ]
      guard position >= 0, position < directions.count else { return .neutral }
      return directions[position]
    }
  }

  /// A usage and the binding it drives.
  struct Entry: Equatable, Sendable {
    /// The HID usage the entry binds.
    let usage: HIDUsage
    /// What the usage drives.
    let binding: Binding
  }

  /// The only report the map reads, by report ID; nil reads every report.
  let reportID: UInt32?
  /// The bindings in the order the map lists them.
  let entries: [Entry]
  /// The bindings by usage, for lookup; a usage has several only when each reads its own half.
  private let bindings: [HIDUsage: [Binding]]

  /// Throws a ``ControllerRecordProblem`` for a usage named twice (two entries share a usage
  /// unless every one reads its own half), a button on an axis or hat control, an axis on any
  /// other control, an empty or reversed range, a dead zone or threshold outside the open interval
  /// from 0 to 1, or a half axis, axis dpad or button trigger on the wrong control.
  init(reportID: UInt32? = nil, entries: [Entry]) throws {
    guard !entries.isEmpty else {
      throw ControllerRecordProblem(
        code: .invalidControllerRecord,
        key: "error.E5007.usageMap.mapEmpty",
        "a usage map must not be empty"
      )
    }
    var seen: [HIDUsage: [Binding]] = [:]
    for entry in entries {
      let usage = "\(entry.usage.usagePage)/\(entry.usage.usage)"
      let name = "usage \(usage)"
      let others = seen[entry.usage, default: []]
      if let half = entry.binding.half, !others.isEmpty,
        others.allSatisfy({ $0.half != nil })
      {
        guard !others.contains(where: { $0.half == half }) else {
          throw ControllerRecordProblem(
            code: .invalidControllerRecord,
            key: "error.E5007.usageMap.halfTwice",
            arguments: [usage, half.rawValue],
            "\(name) names the \(half.rawValue) half twice"
          )
        }
      } else if !others.isEmpty {
        throw ControllerRecordProblem(
          code: .invalidControllerRecord,
          key: "error.E5007.usageMap.usageTwice",
          arguments: [usage],
          "\(name) is named twice"
        )
      }
      seen[entry.usage, default: []].append(entry.binding)
      switch entry.binding {
      case .button(let control):
        guard !Control.stickAxes.contains(control), !Control.dpad.contains(control) else {
          throw ControllerRecordProblem(
            code: .invalidControllerRecord,
            key: "error.E5007.usageMap.buttonControl",
            arguments: [usage, control.rawValue],
            "\(name) is a button; \(control.rawValue) is not"
          )
        }
      case .axis(let axis):
        guard Control.stickAxes.contains(axis.control) || axis.isTrigger else {
          throw ControllerRecordProblem(
            code: .invalidControllerRecord,
            key: "error.E5007.usageMap.axisControl",
            arguments: [usage, axis.control.rawValue],
            "\(name) is an axis; \(axis.control.rawValue) is not"
          )
        }
        if let range = axis.range, range.isEmpty || range.lowerBound == range.upperBound {
          throw ControllerRecordProblem(
            code: .invalidControllerRecord,
            key: "error.E5007.usageMap.rangeOrder",
            arguments: [usage],
            "\(name) range must have min below max"
          )
        }
        if let deadZone = axis.deadZone, !(deadZone > 0 && deadZone < 1) {
          throw ControllerRecordProblem(
            code: .invalidControllerRecord,
            key: "error.E5007.usageMap.deadZone",
            arguments: [usage],
            "\(name) deadZone must be above 0 and below 1"
          )
        }
      case .hat(let hat):
        if let range = hat.range, range != 0...7, range != 1...8 {
          throw ControllerRecordProblem(
            code: .invalidControllerRecord,
            key: "error.E5007.usageMap.hatRange",
            arguments: [usage],
            "\(name) hat range must be 0...7 or 1...8"
          )
        }
      case .halfAxis(let halfAxis):
        guard Self.triggers.contains(halfAxis.control) else {
          throw ControllerRecordProblem(
            code: .invalidControllerRecord,
            key: "error.E5007.usageMap.halfAxisControl",
            arguments: [usage, halfAxis.control.rawValue],
            "\(name) is a half axis; \(halfAxis.control.rawValue) is not a trigger"
          )
        }
      case .buttonTrigger(let control):
        guard Self.triggers.contains(control) else {
          throw ControllerRecordProblem(
            code: .invalidControllerRecord,
            key: "error.E5007.usageMap.buttonTriggerControl",
            arguments: [usage, control.rawValue],
            "\(name) is a button trigger; \(control.rawValue) is not a trigger"
          )
        }
      case .axisDpad(let binding):
        guard Control.dpad.contains(binding.control) else {
          throw ControllerRecordProblem(
            code: .invalidControllerRecord,
            key: "error.E5007.usageMap.axisDpadControl",
            arguments: [usage, binding.control.rawValue],
            "\(name) is an axis dpad; \(binding.control.rawValue) is not a D-pad direction"
          )
        }
        try Self.requireThreshold(binding, usage: usage)
      case .axisButton(let binding):
        guard !Control.stickAxes.contains(binding.control), !Control.dpad.contains(binding.control)
        else {
          throw ControllerRecordProblem(
            code: .invalidControllerRecord,
            key: "error.E5007.usageMap.axisButtonControl",
            arguments: [usage, binding.control.rawValue],
            "\(name) is an axis button; \(binding.control.rawValue) is not a button"
          )
        }
        try Self.requireThreshold(binding, usage: usage)
      }
    }
    self.reportID = reportID
    self.entries = entries
    self.bindings = seen
  }

  /// Throws unless the threshold of `binding`, the entry of `usage` as `page/usage`, is above 0
  /// and below 1.
  private static func requireThreshold(
    _ binding: HalfThreshold,
    usage: String
  ) throws(ControllerRecordProblem) {
    guard binding.threshold > 0, binding.threshold < 1 else {
      throw ControllerRecordProblem(
        code: .invalidControllerRecord,
        key: "error.E5007.usageMap.threshold",
        arguments: [usage],
        "usage \(usage) threshold must be above 0 and below 1"
      )
    }
  }

  /// The triggers.
  private static let triggers: Set<Control> = [.leftTrigger, .rightTrigger]

  /// The bindings of the usage on `page`; empty when the map does not bind it.
  func bindings(page: UInt32, usage: UInt32) -> [Binding] {
    bindings[HIDUsage(usagePage: Int(page), usage: Int(usage))] ?? []
  }

  /// The triggers the map reads as buttons: a physical digital trigger signal.
  var digitalTriggers: Set<Control> { digitalTriggers(declaring: nil) }

  /// The controls the map can drive.
  var controls: Set<Control> { controls(declaring: nil) }

  /// The triggers the map reads as buttons from usages in `usages`; every entry when nil.
  func digitalTriggers(declaring usages: Set<HIDUsage>?) -> Set<Control> {
    Set(
      entries(declaring: usages).compactMap { entry in
        let control: Control
        switch entry.binding {
        case .button(let pressed): control = pressed
        case .axisButton(let binding): control = binding.control
        default: return nil
        }
        return Self.triggers.contains(control) ? control : nil
      }
    )
  }

  /// The controls the map drives from usages in `usages`; every entry when nil.
  ///
  /// A map that is broader than a pad, such as the standard map, names usages the pad's report
  /// descriptor lacks; those controls are not the pad's.
  func controls(declaring usages: Set<HIDUsage>?) -> Set<Control> {
    var driven: Set<Control> = []
    for entry in entries(declaring: usages) {
      switch entry.binding {
      case .button(let control): driven.insert(control)
      case .axis(let axis): driven.insert(axis.control)
      case .hat: driven.formUnion(Control.dpad)
      case .halfAxis(let binding): driven.insert(binding.control)
      case .axisDpad(let binding), .axisButton(let binding): driven.insert(binding.control)
      case .buttonTrigger(let control): driven.insert(control)
      }
    }
    return driven
  }

  /// The entries whose usage is in `usages`; every entry when nil.
  private func entries(declaring usages: Set<HIDUsage>?) -> [Entry] {
    guard let usages else { return entries }
    return entries.filter { usages.contains($0.usage) }
  }
}

extension HIDUsageMap.Half {
  /// How far `element` has travelled from the center of its range toward this half's end, in
  /// 0...1; a half of zero span reads 0.
  func travel(of element: HIDElementValue) -> Float {
    let low = Double(element.logicalMinimum)
    let high = Double(element.logicalMaximum)
    let center = (low + high) / 2
    let span = self == .positive ? high - center : center - low
    guard span > 0 else { return 0 }
    let offset = Double(element.integerValue) - center
    return Float(max(0, min(1, (self == .positive ? offset : -offset) / span)))
  }
}

/// A descriptor shape and the usage map it selects: the `HIDDescriptor` description's way to
/// recognise a family of pads from their report descriptor alone.
struct HIDUsageShape: Equatable, Sendable {
  /// Usages the descriptor must declare.
  let present: Set<HIDUsage>
  /// Usages the descriptor must not declare.
  let absent: Set<HIDUsage>
  /// When nonempty, at least one of these usages the descriptor must declare.
  let anyOf: Set<HIDUsage>
  /// The usage map the shape selects.
  let map: HIDUsageMap

  /// Whether a descriptor that declares `usages` has the shape: all `present`, none `absent`, and
  /// one of `anyOf` when that is nonempty.
  func matches(_ usages: Set<HIDUsage>) -> Bool {
    usages.isSuperset(of: present) && usages.isDisjoint(with: absent)
      && (anyOf.isEmpty || !usages.isDisjoint(with: anyOf))
  }
}
