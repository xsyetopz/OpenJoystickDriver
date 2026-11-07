import Foundation

/// Why a database line cannot drive a pad.
struct SDLMappingRejection: Error, Equatable, CustomStringConvertible {
  /// The reason, as a fragment that follows "SDL_GameControllerDB line rejected" in each message.
  let reason: String

  /// The reason.
  var description: String { reason }
}

/// A database line converted against a pad's element list.
struct SDLConvertedMapping: Equatable, Sendable {
  /// The usage map that drives the pad.
  let usageMap: HIDUsageMap
  /// The fields of the line the conversion cannot express, as the line names them, in line order.
  let unmapped: [String]
}

/// Converts the fields of an SDL_GameControllerDB line to a ``HIDUsageMap``.
///
/// `b#`, `a#` and `h#.#` index the lists of ``SDLElementLists``. An axis that presses a button or
/// a D-pad direction presses it when its travel from the center of its range reaches
/// ``sdlAxisButtonThreshold``. A `b#` that names a D-pad direction reads the element as the
/// positive half of its range, so a one-bit button and a pressure byte both press it.
enum SDLMappingConverter {
  /// The fraction of a half range at which an axis presses a button, as SDL reads it.
  static let sdlAxisButtonThreshold: Float = 0.5

  /// The OJD control each database control name drives.
  ///
  /// `paddle1` and `paddle2` are SDL's upper right and upper left paddles, `paddle3` and `paddle4`
  /// the lower right and lower left. `misc1` is the share or capture button; the other `misc`
  /// buttons have no id of their own.
  static let controlNames: [String: Control] = [
    "a": .south, "b": .east, "x": .west, "y": .north, "back": .back, "start": .start,
    "guide": .guide, "leftstick": .leftStickClick, "rightstick": .rightStickClick,
    "leftshoulder": .leftShoulder, "rightshoulder": .rightShoulder, "dpup": .dpadUp,
    "dpdown": .dpadDown, "dpleft": .dpadLeft, "dpright": .dpadRight, "leftx": .leftStickX,
    "lefty": .leftStickY, "rightx": .rightStickX, "righty": .rightStickY,
    "lefttrigger": .leftTrigger, "righttrigger": .rightTrigger, "misc1": .capture,
    "paddle1": .rightPaddle1, "paddle2": .leftPaddle1, "paddle3": .rightPaddle2,
    "paddle4": .leftPaddle2, "touchpad": .touchpadClick, "misc2": .auxiliary1,
    "misc3": .auxiliary2, "misc4": .auxiliary3, "misc5": .auxiliary4, "misc6": .auxiliary5,
  ]

  /// The hat direction bit each D-pad direction reads.
  private static let hatBits: [Control: Int] = [
    .dpadUp: 1, .dpadRight: 2, .dpadDown: 4, .dpadLeft: 8,
  ]

  /// What a field's right-hand side names.
  private enum Source {
    /// `b#`: the button at an index.
    case button(Int)
    /// `a#`: the axis at an index, or one half of it, possibly inverted.
    case axis(Int, half: HIDUsageMap.Half?, inverted: Bool)
    /// `h#.#`: one direction bit of the hat at an index.
    case hat(Int, bit: Int)
  }

  /// Converts `fields` (`key:binding`) against the pad's `elements`.
  ///
  /// A field the conversion cannot express is returned in ``SDLConvertedMapping/unmapped`` and the
  /// rest still apply. Throws when a binding is unreadable, indexes an element the pad lacks, names
  /// a hat that does not have eight positions, collides with another field on one usage, or leaves
  /// nothing to map.
  static func convert(
    fields: [String],
    elements: [HIDElementDescription]
  ) throws(SDLMappingRejection) -> SDLConvertedMapping {
    let lists = SDLElementLists(elements: elements)
    var entries: [HIDUsageMap.Entry] = []
    var unmapped: [String] = []
    var boundHats: Set<HIDUsage> = []
    for field in fields {
      let pair = field.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
      guard pair.count == 2 else {
        throw SDLMappingRejection(reason: "the field \"\(field)\" has no binding")
      }
      let key = String(pair[0])
      guard key != "platform" else { continue }
      let source = try parse(String(pair[1]), field: field)
      let element = try element(of: source, in: lists, field: field)
      guard let control = controlNames[key],
        let binding = binding(for: control, source: source)
      else {
        unmapped.append(key)
        continue
      }
      let usage = HIDUsage(usagePage: Int(element.usagePage), usage: Int(element.usage))
      if case .hat = binding {
        guard boundHats.insert(usage).inserted else { continue }
      }
      entries.append(HIDUsageMap.Entry(usage: usage, binding: binding))
    }
    guard !entries.isEmpty else { throw SDLMappingRejection(reason: "no control can be mapped") }
    do {
      return SDLConvertedMapping(usageMap: try HIDUsageMap(entries: entries), unmapped: unmapped)
    } catch let problem as ControllerRecordProblem {
      throw SDLMappingRejection(reason: problem.description)
    } catch {
      throw SDLMappingRejection(reason: "\(error)")
    }
  }

  /// Reads `b#`, `a#`, `+a#`, `-a#` (each with an optional `~`) and `h#.#`.
  private static func parse(_ text: String, field: String) throws(SDLMappingRejection) -> Source {
    var body = Substring(text)
    let inverted = body.last == "~"
    if inverted { body = body.dropLast() }
    var half: HIDUsageMap.Half?
    if let sign = body.first, sign == "+" || sign == "-" {
      half = sign == "+" ? .positive : .negative
      body = body.dropFirst()
    }
    let unreadable = SDLMappingRejection(reason: "the field \"\(field)\" has an unreadable binding")
    guard let kind = body.first else { throw unreadable }
    let number = body.dropFirst()
    switch kind {
    case "b" where half == nil && !inverted:
      guard let index = Int(number) else { throw unreadable }
      return .button(index)
    case "a":
      guard let index = Int(number) else { throw unreadable }
      return .axis(index, half: half, inverted: inverted)
    case "h" where half == nil && !inverted:
      let parts = number.split(separator: ".", omittingEmptySubsequences: false)
      guard parts.count == 2, let index = Int(parts[0]), let bit = Int(parts[1]),
        [1, 2, 4, 8].contains(bit)
      else { throw unreadable }
      return .hat(index, bit: bit)
    default: throw unreadable
    }
  }

  /// The element `source` indexes.
  private static func element(
    of source: Source,
    in lists: SDLElementLists,
    field: String
  ) throws(SDLMappingRejection) -> HIDElementDescription {
    let (name, index, list): (String, Int, [HIDElementDescription]) =
      switch source {
      case .button(let index): ("b\(index)", index, lists.buttons)
      case .axis(let index, _, _): ("a\(index)", index, lists.axes)
      case .hat(let index, _): ("h\(index)", index, lists.hats)
      }
    guard list.indices.contains(index) else {
      throw SDLMappingRejection(
        reason: "the field \"\(field)\" names \(name) but the pad lists \(list.count)"
      )
    }
    let element = list[index]
    if case .hat = source, element.logicalMaximum - element.logicalMinimum != 7 {
      throw SDLMappingRejection(reason: "the hat of \"\(field)\" does not have eight positions")
    }
    return element
  }

  /// The binding of `control` to `source`, or nil when no binding kind expresses it.
  private static func binding(
    for control: Control,
    source: Source
  ) -> HIDUsageMap.Binding? {
    let isTrigger = control == .leftTrigger || control == .rightTrigger
    switch source {
    case .hat(_, let bit):
      return hatBits[control] == bit ? .hat(HIDUsageMap.Hat(range: nil)) : nil
    case .button:
      if isTrigger { return .buttonTrigger(control) }
      if Control.dpad.contains(control) {
        return .axisDpad(
          HIDUsageMap.HalfThreshold(
            half: .positive,
            control: control,
            threshold: sdlAxisButtonThreshold
          )
        )
      }
      return Control.stickAxes.contains(control) ? nil : .button(control)
    case .axis(_, let half, let inverted):
      if Control.stickAxes.contains(control) {
        guard half == nil else { return nil }
        return .axis(
          HIDUsageMap.Axis(control: control, isInverted: inverted, range: nil, deadZone: nil)
        )
      }
      if isTrigger, half == nil {
        return .axis(
          HIDUsageMap.Axis(control: control, isInverted: inverted, range: nil, deadZone: nil)
        )
      }
      let base: HIDUsageMap.Half = half ?? .positive
      let side: HIDUsageMap.Half = inverted ? (base == .positive ? .negative : .positive) : base
      if isTrigger {
        return .halfAxis(HIDUsageMap.HalfAxis(half: side, control: control, isInverted: false))
      }
      let threshold = HIDUsageMap.HalfThreshold(
        half: side,
        control: control,
        threshold: sdlAxisButtonThreshold
      )
      return Control.dpad.contains(control) ? .axisDpad(threshold) : .axisButton(threshold)
    }
  }
}
