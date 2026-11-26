public import Foundation

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
    let parsed: RemappingSource? =
      switch parts[0] {
      case "button", "dpad", "axis", "trigger", "motion": controlSource(parts)
      case "touch": touchSource(parts) ?? regionSource(parts)
      default: regionSource(parts)
      }
    guard let parsed else { throw RemappingCommandValueError.invalidSource(raw) }
    return parsed
  }

  /// Parses the `button`, `dpad`, `axis`, `trigger:TRIGGER:STAGE` and `motion:lean` forms.
  private static func controlSource(_ parts: [String]) -> RemappingSource? {
    switch (parts[0], parts.count) {
    case ("button", 2): CommandLineName.value(of: parts[1], in: Control.self).map { .button($0) }
    case ("dpad", 2):
      CommandLineName.value(of: parts[1], in: RemappingDpadDirection.self).map { .dpad($0) }
    case ("axis", 2): CommandLineName.value(of: parts[1], in: RemappingAxis.self).map { .axis($0) }
    case ("axis", 3): axisDirectionSource(parts)
    case ("trigger", 3): triggerStageSource(parts)
    case ("motion", 3): motionLeanSource(parts)
    default: nil
    }
  }

  private static func axisDirectionSource(_ parts: [String]) -> RemappingSource? {
    guard let axis = CommandLineName.value(of: parts[1], in: RemappingAxis.self),
      let direction = CommandLineName.value(of: parts[2], in: RemappingAxisDirection.self)
    else { return nil }
    return .axisDirection(axis, direction)
  }

  private static func triggerStageSource(_ parts: [String]) -> RemappingSource? {
    guard let trigger = CommandLineName.value(of: parts[1], in: RemappingTriggerSource.self),
      let stage = CommandLineName.value(of: parts[2], in: RemappingTriggerStage.self)
    else { return nil }
    return .triggerStage(trigger, stage)
  }

  private static func motionLeanSource(_ parts: [String]) -> RemappingSource? {
    guard parts[1] == "lean",
      let direction = CommandLineName.value(of: parts[2], in: RemappingMotionLeanDirection.self)
    else { return nil }
    return .motionLean(direction)
  }

  /// Parses the `touch:SURFACE:contact`, `grid` and `swipe` forms.
  private static func touchSource(_ parts: [String]) -> RemappingSource? {
    guard parts[0] == "touch", parts.count >= 3,
      let surface = CommandLineName.value(of: parts[1], in: RemappingTouchSurface.self)
    else { return nil }
    switch (parts.count, parts[2]) {
    case (3, "contact"): return .touchContact(surface)
    case (7, "grid"): return touchGridSource(surface, parts)
    case (5, "swipe"): return touchSwipeSource(surface, parts)
    default: return nil
    }
  }

  private static func touchGridSource(
    _ surface: RemappingTouchSurface,
    _ parts: [String]
  ) -> RemappingSource? {
    guard let columns = Int(parts[3]), let rows = Int(parts[4]), let column = Int(parts[5]),
      let row = Int(parts[6])
    else { return nil }
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

  private static func touchSwipeSource(
    _ surface: RemappingTouchSurface,
    _ parts: [String]
  ) -> RemappingSource? {
    guard
      let direction = CommandLineName.value(of: parts[3], in: RemappingTouchSwipeDirection.self),
      let minimumDistance = Double(parts[4]), minimumDistance.isFinite
    else { return nil }
    return .touchSwipe(
      RemappingTouchSwipeSource(
        surface: surface,
        direction: direction,
        minimumDistance: minimumDistance
      )
    )
  }

  /// Parses the `stick-region`, `trigger-band` and `touch:SURFACE:area` forms.
  ///
  /// A range is two numbers joined by `-`. Hysteresis is the default of the source.
  private static func regionSource(_ parts: [String]) -> RemappingSource? {
    switch (parts[0], parts.count) {
    case ("stick-region", 3), ("stick-region", 4): stickRegionSource(parts)
    case ("trigger-band", 3): triggerBandSource(parts)
    case ("touch", 7): touchAreaSource(parts)
    default: nil
    }
  }

  private static func range(_ text: String) -> (Double, Double)? {
    let ends = text.split(separator: "-", omittingEmptySubsequences: false).map { Double($0) }
    guard ends.count == 2, let low = ends[0], let high = ends[1], low.isFinite, high.isFinite
    else { return nil }
    return (low, high)
  }

  private static func stickRegionSource(_ parts: [String]) -> RemappingSource? {
    guard let stick = CommandLineName.value(of: parts[1], in: RemappingStickSource.self),
      let ring = range(parts[2])
    else { return nil }
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

  private static func triggerBandSource(_ parts: [String]) -> RemappingSource? {
    guard let trigger = CommandLineName.value(of: parts[1], in: RemappingTriggerSource.self),
      let band = range(parts[2])
    else { return nil }
    return .triggerBand(RemappingTriggerBandSource(trigger: trigger, from: band.0, to: band.1))
  }

  private static func touchAreaSource(_ parts: [String]) -> RemappingSource? {
    guard parts[2] == "area",
      let surface = CommandLineName.value(of: parts[1], in: RemappingTouchSurface.self)
    else { return nil }
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
    let parsed: RemappingDestination? =
      switch parts[0] {
      case "gamepad": gamepadDestination(parts)
      case "key": keyboardDestination(parts)
      case "mouse", "move", "position", "scroll": pointerDestination(parts)
      case "physical": physicalDestination(parts)
      case "pause": parts.count == 2 ? switchMode(parts[1]).map { .pause($0) } : nil
      case "profile":
        parts.count == 3 && parts[1] == "switch"
          ? profileTarget(parts[2]).map { .profileSwitch($0) } : nil
      default: midiDestination(parts)
      }
    guard let parsed else { throw RemappingCommandValueError.invalidDestination(raw) }
    return parsed
  }

  /// Parses the `gamepad:axis`, `gamepad:dpad` and `gamepad:button` forms.
  private static func gamepadDestination(_ parts: [String]) -> RemappingDestination? {
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
    return nil
  }

  /// Parses `key:KEY` and `key:KEY:mods=MODIFIERS`.
  private static func keyboardDestination(_ parts: [String]) -> RemappingDestination? {
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
    return nil
  }

  /// Parses the `mouse`, `move`, `position` and `scroll` forms.
  private static func pointerDestination(_ parts: [String]) -> RemappingDestination? {
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
    return nil
  }

  /// Parses the `physical:rumble`, `player`, `color`, `brightness` and `adaptive` forms.
  private static func physicalDestination(_ parts: [String]) -> RemappingDestination? {
    guard parts.count >= 3, parts[0] == "physical" else { return nil }
    let output: RemappingPhysicalOutput? =
      switch (parts[1], parts.count) {
      case ("rumble", 4):
        CommandLineName.value(of: parts[2], in: PhysicalRumbleMotor.self).flatMap { motor in
          boundedUnit(parts[3]).map { .rumble(motor: motor, intensity: $0) }
        }
      case ("player", 3):
        Int(parts[2]).flatMap(PhysicalPlayerIndicator.init(rawValue:)).map { .playerIndicator($0) }
      case ("color", 5): colorOutput(parts[2], parts[3], parts[4])
      case ("brightness", 3): boundedUnit(parts[2]).map { .brightness($0) }
      case ("adaptive", 4), ("adaptive", 6): adaptiveTriggerOutput(parts)
      default: nil
      }
    return output.map { .physical($0) }
  }

  /// Parses `physical:color:R:G:B`, each channel 0 to 255.
  private static func colorOutput(
    _ redText: String,
    _ greenText: String,
    _ blueText: String
  ) -> RemappingPhysicalOutput? {
    guard let red = UInt8(redText), let green = UInt8(greenText), let blue = UInt8(blueText)
    else { return nil }
    return .color(ControllerColor(red: red, green: green, blue: blue))
  }

  /// Parses `physical:adaptive:TRIGGER:off` and
  /// `physical:adaptive:TRIGGER:resistance:START:STRENGTH`.
  private static func adaptiveTriggerOutput(_ parts: [String]) -> RemappingPhysicalOutput? {
    guard let trigger = CommandLineName.value(of: parts[2], in: PhysicalAdaptiveTrigger.self)
    else { return nil }
    switch (parts[3], parts.count) {
    case ("off", 4): return .adaptiveTrigger(trigger, .off)
    case ("resistance", 6):
      guard let startPosition = boundedUnit(parts[4]), let strength = boundedUnit(parts[5])
      else { return nil }
      return .adaptiveTrigger(
        trigger,
        PhysicalAdaptiveTriggerEffect(
          kind: .resistance,
          startPosition: startPosition,
          strength: strength
        )
      )
    default: return nil
    }
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
