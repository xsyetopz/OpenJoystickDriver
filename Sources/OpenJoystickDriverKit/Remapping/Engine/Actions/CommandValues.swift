import Foundation

/// Error for a source or target operand of `ojd binding` that does not parse.
public enum RemappingCommandValueError: Error, Equatable, LocalizedError, Sendable {
  /// The source operand is invalid; the value is the operand.
  case invalidSource(String)
  /// The target operand is invalid; the value is the operand.
  case invalidDestination(String)

  /// Message that names the operand that does not parse.
  public var errorDescription: String? {
    switch self {
    case .invalidSource(let raw): "Invalid source '\(raw)'."
    case .invalidDestination(let raw): "Invalid target '\(raw)'."
    }
  }
}

/// Parses the colon-separated source and target operands of `ojd binding`.
///
/// Every part that is an enumerated value (control, axis, direction, key, modifier, surface, motor)
/// is the lowercase kebab-case form of its profile value (`CommandLineName`), such as
/// `axis:left-stick-x:negative`. Fixed words (`button`, `key`, `mods=`) and numbers are written as
/// they are.
public enum RemappingCommandValueParser {
  /// Parses a source operand.
  /// - Throws: ``RemappingCommandValueError/invalidSource(_:)`` when no source form matches.
  public static func source(_ raw: String) throws -> RemappingSource {
    let parts = raw.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
    if parts.count == 2, parts[0] == "button",
      let button = CommandLineName.value(of: parts[1], in: Control.self)
    {
      return .button(button)
    }
    if parts.count == 2, parts[0] == "dpad",
      let direction = CommandLineName.value(of: parts[1], in: RemappingDpadDirection.self)
    {
      return .dpad(direction)
    }
    if parts.count == 2, parts[0] == "axis",
      let axis = CommandLineName.value(of: parts[1], in: RemappingAxis.self)
    {
      return .axis(axis)
    }
    if parts.count == 3, parts[0] == "axis",
      let axis = CommandLineName.value(of: parts[1], in: RemappingAxis.self),
      let direction = CommandLineName.value(of: parts[2], in: RemappingAxisDirection.self)
    {
      return .axisDirection(axis, direction)
    }
    if parts.count == 3, parts[0] == "trigger",
      let trigger = CommandLineName.value(of: parts[1], in: RemappingTriggerSource.self),
      let stage = CommandLineName.value(of: parts[2], in: RemappingTriggerStage.self)
    {
      return .triggerStage(trigger, stage)
    }
    if parts.count == 3, parts[0] == "motion", parts[1] == "lean",
      let direction = CommandLineName.value(of: parts[2], in: RemappingMotionLeanDirection.self)
    {
      return .motionLean(direction)
    }
    if parts.count == 3, parts[0] == "touch",
      let surface = CommandLineName.value(of: parts[1], in: RemappingTouchSurface.self),
      parts[2] == "contact"
    {
      return .touchContact(surface)
    }
    if parts.count == 7, parts[0] == "touch",
      let surface = CommandLineName.value(of: parts[1], in: RemappingTouchSurface.self),
      parts[2] == "grid",
      let columns = Int(parts[3]), let rows = Int(parts[4]), let column = Int(parts[5]),
      let row = Int(parts[6])
    {
      return .touchGrid(
        RemappingTouchGridSource(
          surface: surface,
          columns: columns,
          rows: rows,
          column: column,
          row: row
        )
      )
    }
    if parts.count == 5, parts[0] == "touch",
      let surface = CommandLineName.value(of: parts[1], in: RemappingTouchSurface.self),
      parts[2] == "swipe",
      let direction = CommandLineName.value(of: parts[3], in: RemappingTouchSwipeDirection.self),
      let minimumDistance = Double(parts[4]), minimumDistance.isFinite
    {
      return .touchSwipe(
        RemappingTouchSwipeSource(
          surface: surface,
          direction: direction,
          minimumDistance: minimumDistance
        )
      )
    }
    if let region = regionSource(parts) { return region }
    throw RemappingCommandValueError.invalidSource(raw)
  }

  /// Parses the `stick-region`, `trigger-band` and `touch:SURFACE:area` forms.
  ///
  /// A range is two numbers joined by `-`. Hysteresis is the default of the source.
  private static func regionSource(_ parts: [String]) -> RemappingSource? {
    func range(_ text: String) -> (Double, Double)? {
      let ends = text.split(separator: "-", omittingEmptySubsequences: false).map { Double($0) }
      guard ends.count == 2, let low = ends[0], let high = ends[1], low.isFinite, high.isFinite
      else { return nil }
      return (low, high)
    }
    if parts.count == 3 || parts.count == 4, parts[0] == "stick-region",
      let stick = CommandLineName.value(of: parts[1], in: RemappingStickSource.self),
      let ring = range(parts[2])
    {
      let sector = parts.count == 4 ? range(parts[3]) : nil
      guard parts.count == 3 || sector != nil else { return nil }
      return .stickRegion(
        RemappingStickRegionSource(
          stick: stick,
          innerRadius: ring.0,
          outerRadius: ring.1,
          fromDegrees: sector?.0,
          toDegrees: sector?.1
        )
      )
    }
    if parts.count == 3, parts[0] == "trigger-band",
      let trigger = CommandLineName.value(of: parts[1], in: RemappingTriggerSource.self),
      let band = range(parts[2])
    {
      return .triggerBand(RemappingTriggerBandSource(trigger: trigger, from: band.0, to: band.1))
    }
    if parts.count == 7, parts[0] == "touch", parts[2] == "area",
      let surface = CommandLineName.value(of: parts[1], in: RemappingTouchSurface.self)
    {
      let values = parts[3...].compactMap { Double($0) }
      guard values.count == 4, values.allSatisfy(\.isFinite) else { return nil }
      return .touchArea(
        RemappingTouchAreaSource(
          surface: surface,
          x: values[0],
          y: values[1],
          width: values[2],
          height: values[3]
        )
      )
    }
    return nil
  }

  /// Parses `system-key:NAME`, `system:mission-control`, `open-app:BUNDLE-ID`, `open-url:URL`,
  /// `shortcut:NAME` and `text:STRING`, whose value keeps every colon after the first.
  private static func systemDestination(_ raw: String) -> RemappingDestination? {
    guard let colon = raw.firstIndex(of: ":") else { return nil }
    let value = String(raw[raw.index(after: colon)...])
    switch raw[..<colon] {
    case "system-key":
      return CommandLineName.value(of: value, in: RemappingSystemKey.self).map { .systemKey($0) }
    case "system":
      return CommandLineName.value(of: value, in: RemappingSystemActionKind.self)
        .map { .systemAction($0) }
    case "open-app": return .openApplication(bundleIdentifier: value)
    case "open-url": return .openURL(value)
    case "shortcut": return .runShortcut(value)
    case "text": return .typeText(value)
    default: return nil
    }
  }

  /// Parses a target operand.
  ///
  /// MIDI targets are `midi-note:CHANNEL:NOTE[:VELOCITY]` and `midi-cc:CHANNEL:CONTROLLER`.
  /// Keyboard modifiers follow `mods=` as a nonempty comma-separated list without repeats. Physical
  /// intensities, positions and strengths are numbers from 0 to 1.
  /// - Throws: ``RemappingCommandValueError/invalidDestination(_:)`` when no target form matches.
  public static func destination(_ raw: String) throws -> RemappingDestination {
    if let system = systemDestination(raw) { return system }
    let parts = raw.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
    if parts.count == 3, parts[0] == "gamepad", parts[1] == "axis",
      let axis = CommandLineName.value(of: parts[2], in: RemappingAxis.self)
    {
      return .gamepadAxis(axis)
    }
    if parts.count == 3, parts[0] == "gamepad", parts[1] == "dpad",
      let direction = CommandLineName.value(of: parts[2], in: RemappingDpadDirection.self)
    {
      return .gamepadDpad(direction)
    }
    if parts.count == 3, parts[0] == "gamepad", parts[1] == "button",
      let button = CommandLineName.value(of: parts[2], in: Control.self)
    {
      return .gamepadButton(button)
    }
    if parts.count == 2, parts[0] == "key",
      let key = CommandLineName.value(of: parts[1], in: RemappingKeyboardKey.self)
    {
      return .keyboard(key: key, modifiers: [])
    }
    if parts.count == 3, parts[0] == "key",
      let key = CommandLineName.value(of: parts[1], in: RemappingKeyboardKey.self),
      parts[2].hasPrefix("mods=")
    {
      let names = parts[2].dropFirst(5).split(separator: ",").map(String.init)
      let modifiers = names.compactMap {
        CommandLineName.value(of: $0, in: RemappingKeyModifier.self)
      }
      if !names.isEmpty, modifiers.count == names.count, Set(modifiers).count == modifiers.count {
        return .keyboard(key: key, modifiers: Set(modifiers))
      }
    }
    if parts.count == 2, parts[0] == "mouse",
      let button = CommandLineName.value(of: parts[1], in: RemappingMouseButton.self)
    {
      return .mouseButton(button)
    }
    if parts.count == 2, parts[0] == "move",
      let axis = CommandLineName.value(of: parts[1], in: RemappingPointerAxis.self)
    {
      return .mouseMovement(axis)
    }
    if parts.count == 2, parts[0] == "position",
      let axis = CommandLineName.value(of: parts[1], in: RemappingPointerAxis.self)
    {
      return .pointerPosition(axis)
    }
    if parts.count == 2, parts[0] == "scroll",
      let axis = CommandLineName.value(of: parts[1], in: RemappingPointerAxis.self)
    {
      return .scroll(axis)
    }
    if parts.count == 4, parts[0] == "physical", parts[1] == "rumble",
      let motor = CommandLineName.value(of: parts[2], in: PhysicalRumbleMotor.self),
      let intensity = boundedUnit(parts[3])
    {
      return .physical(.rumble(motor: motor, intensity: intensity))
    }
    if parts.count == 3, parts[0] == "physical", parts[1] == "player",
      let rawIndicator = Int(parts[2]),
      let indicator = PhysicalPlayerIndicator(rawValue: rawIndicator)
    {
      return .physical(.playerIndicator(indicator))
    }
    if parts.count == 5, parts[0] == "physical", parts[1] == "color", let red = UInt8(parts[2]),
      let green = UInt8(parts[3]), let blue = UInt8(parts[4])
    {
      return .physical(.color(ControllerColor(red: red, green: green, blue: blue)))
    }
    if parts.count == 3, parts[0] == "physical", parts[1] == "brightness",
      let intensity = boundedUnit(parts[2])
    {
      return .physical(.brightness(intensity))
    }
    if parts.count == 4, parts[0] == "physical", parts[1] == "adaptive",
      let trigger = CommandLineName.value(of: parts[2], in: PhysicalAdaptiveTrigger.self),
      parts[3] == "off"
    {
      return .physical(.adaptiveTrigger(trigger, .off))
    }
    if parts.count == 6, parts[0] == "physical", parts[1] == "adaptive",
      let trigger = CommandLineName.value(of: parts[2], in: PhysicalAdaptiveTrigger.self),
      parts[3] == "resistance",
      let startPosition = boundedUnit(parts[4]), let strength = boundedUnit(parts[5])
    {
      return .physical(
        .adaptiveTrigger(
          trigger,
          PhysicalAdaptiveTriggerEffect(
            kind: .resistance,
            startPosition: startPosition,
            strength: strength
          )
        )
      )
    }
    if parts.count == 2, parts[0] == "pause", let mode = switchMode(parts[1]) {
      return .pause(mode)
    }
    if parts.count == 3, parts[0] == "profile", parts[1] == "switch",
      let target = profileTarget(parts[2])
    {
      return .profileSwitch(target)
    }
    if let midi = midiDestination(parts) { return midi }
    throw RemappingCommandValueError.invalidDestination(raw)
  }

  /// Parses a layer target operand into the layer name and the mode, or returns `nil`.
  ///
  /// The form is `layer:NAME:on|off|toggle`. The name may hold colons; the mode follows the last.
  public static func layerTarget(_ raw: String) -> (name: String, mode: RemappingSwitchMode)? {
    guard raw.hasPrefix("layer:") else { return nil }
    let rest = raw.dropFirst("layer:".count)
    guard let colon = rest.lastIndex(of: ":"), colon != rest.startIndex,
      let mode = switchMode(String(rest[rest.index(after: colon)...]))
    else { return nil }
    return (String(rest[..<colon]), mode)
  }

  /// Parses `on`, `off` or `toggle`, or returns `nil`.
  private static func switchMode(_ raw: String) -> RemappingSwitchMode? {
    CommandLineName.value(of: raw, in: RemappingSwitchMode.self)
  }

  /// Parses a profile identifier, `next` or `previous`, or returns `nil`.
  private static func profileTarget(_ raw: String) -> RemappingProfileTarget? {
    switch raw {
    case "next": .next
    case "previous": .previous
    default: UUID(uuidString: raw).map { .profile($0) }
    }
  }

  /// Parses `midi-note:CHANNEL:NOTE[:VELOCITY]`, whose velocity is 127 when omitted, and
  /// `midi-cc:CHANNEL:CONTROLLER`; the numbers must be in range.
  private static func midiDestination(_ parts: [String]) -> RemappingDestination? {
    let numbers = parts.dropFirst().map { Int($0) }
    guard !numbers.contains(nil), let first = numbers.first, let channel = first else { return nil }
    let destination: RemappingDestination
    switch (parts[0], numbers.count) {
    case ("midi-note", 2...3):
      destination = .midiNote(
        channel: channel,
        note: numbers[1] ?? 0,
        velocity: numbers.count == 3 ? numbers[2] ?? 0 : RemappingDestination.midiMaxData
      )
    case ("midi-cc", 2):
      destination = .midiControlChange(channel: channel, controller: numbers[1] ?? 0)
    default: return nil
    }
    return destination.midiFieldsAreInRange ? destination : nil
  }

  /// Parses a finite number from 0 to 1, or returns `nil`.
  private static func boundedUnit(_ raw: String) -> Double? {
    guard let value = Double(raw), value.isFinite, (0...1).contains(value) else { return nil }
    return value
  }
}
