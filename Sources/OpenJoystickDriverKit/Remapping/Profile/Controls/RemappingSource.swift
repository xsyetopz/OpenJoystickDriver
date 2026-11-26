import Foundation

/// The controller-side origin of a binding.
public enum RemappingSource: Codable, Equatable, Hashable, Sendable {
  /// A button or other digital control.
  case button(Control)
  /// A d-pad direction.
  case dpad(RemappingDpadDirection)
  /// An analog axis, as a continuous value.
  case axis(RemappingAxis)
  /// One direction of an analog axis, as a digital press.
  case axisDirection(RemappingAxis, RemappingAxisDirection)
  /// The soft or full stage of a dual-stage trigger.
  case triggerStage(RemappingTriggerSource, RemappingTriggerStage)
  /// A lean of the controller to the left or right.
  case motionLean(RemappingMotionLeanDirection)
  /// Any contact on a touch surface.
  case touchContact(RemappingTouchSurface)
  /// One cell of a touch-surface grid.
  case touchGrid(RemappingTouchGridSource)
  /// A swipe on a touch surface.
  case touchSwipe(RemappingTouchSwipeSource)
  /// A ring and optional sector of a stick.
  case stickRegion(RemappingStickRegionSource)
  /// A pressure band of a trigger.
  case triggerBand(RemappingTriggerBandSource)
  /// A rectangle of a touch surface.
  case touchArea(RemappingTouchAreaSource)

  /// Whether this source reads a pointer axis.
  public var isPointer: Bool {
    switch self {
    case .axis(let axis), .axisDirection(let axis, _): axis.isPointer
    default: false
    }
  }

  /// Value of the `type` field that selects the case in a profile document.
  private enum Kind: String, Codable {
    case button = "Button"
    case dpad = "Dpad"
    case axis = "Axis"
    case axisDirection = "AxisDirection"
    case triggerStage = "TriggerStage"
    case motionLean = "MotionLean"
    case touchContact = "TouchContact"
    case touchGrid = "TouchGrid"
    case touchSwipe = "TouchSwipe"
    case stickRegion = "StickRegion"
    case triggerBand = "TriggerBand"
    case touchArea = "TouchArea"

    /// Keys that a profile document may give for this case, which `type` selects.
    var fields: [CodingKeys] {
      switch self {
      case .button: [.type, .button]
      case .dpad, .motionLean: [.type, .direction]
      case .axis: [.type, .axis]
      case .axisDirection: [.type, .axis, .direction]
      case .triggerStage: [.type, .trigger, .stage]
      case .touchContact: [.type, .surface]
      case .touchGrid: [.type, .surface, .columns, .rows, .column, .row]
      case .touchSwipe: [.type, .surface, .direction, .minimumDistance]
      case .stickRegion:
        [.type, .stick, .innerRadius, .outerRadius, .fromDegrees, .toDegrees, .hysteresis]
      case .triggerBand: [.type, .trigger, .from, .to, .hysteresis]
      case .touchArea: [.type, .surface, .x, .y, .width, .height]
      }
    }
  }

  /// Profile document keys of a source, merged across all cases.
  private enum CodingKeys: String, CodingKey, CaseIterable {
    case type
    case button
    case direction
    case axis
    case surface
    case columns
    case rows
    case column
    case row
    case minimumDistance
    case trigger
    case stage
    case stick
    case innerRadius
    case outerRadius
    case fromDegrees
    case toDegrees
    case hysteresis
    case from
    case to
    case x
    case y
    case width
    case height
  }

  /// Decodes a source from a profile document.
  ///
  /// The `type` field selects the case, and keys that belong to another case are rejected.
  /// - Throws: `DecodingError` for an unknown or misplaced key, a missing key or a bad value.
  public init(from decoder: any Decoder) throws {
    try decoder.rejectUnknownKeys(CodingKeys.self)
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let kind = try container.decode(Kind.self, forKey: .type)
    try container.rejectKeys(otherThan: kind.fields)
    switch kind {
    case .button: self = .button(try container.decode(Control.self, forKey: .button))
    case .dpad: self = .dpad(try container.decode(RemappingDpadDirection.self, forKey: .direction))
    case .axis: self = .axis(try container.decode(RemappingAxis.self, forKey: .axis))
    case .axisDirection:
      self = .axisDirection(
        try container.decode(RemappingAxis.self, forKey: .axis),
        try container.decode(RemappingAxisDirection.self, forKey: .direction)
      )
    case .triggerStage:
      self = .triggerStage(
        try container.decode(RemappingTriggerSource.self, forKey: .trigger),
        try container.decode(RemappingTriggerStage.self, forKey: .stage)
      )
    case .motionLean:
      self = .motionLean(
        try container.decode(RemappingMotionLeanDirection.self, forKey: .direction)
      )
    case .touchContact:
      self = .touchContact(try container.decode(RemappingTouchSurface.self, forKey: .surface))
    case .touchGrid:
      self = .touchGrid(
        RemappingTouchGridSource(
          surface: try container.decode(RemappingTouchSurface.self, forKey: .surface),
          columns: try container.decode(Int.self, forKey: .columns),
          rows: try container.decode(Int.self, forKey: .rows),
          column: try container.decode(Int.self, forKey: .column),
          row: try container.decode(Int.self, forKey: .row)
        )
      )
    case .touchSwipe:
      self = .touchSwipe(
        RemappingTouchSwipeSource(
          surface: try container.decode(RemappingTouchSurface.self, forKey: .surface),
          direction: try container.decode(RemappingTouchSwipeDirection.self, forKey: .direction),
          minimumDistance: try container.decode(Double.self, forKey: .minimumDistance)
        )
      )
    case .stickRegion:
      let from = try container.decodeIfPresent(Double.self, forKey: .fromDegrees)
      let to = try container.decodeIfPresent(Double.self, forKey: .toDegrees)
      guard (from == nil) == (to == nil) else {
        throw DecodingError.dataCorruptedError(
          forKey: .toDegrees,
          in: container,
          debugDescription: "fromDegrees and toDegrees come together."
        )
      }
      self = .stickRegion(
        RemappingStickRegionSource(
          stick: try container.decode(RemappingStickSource.self, forKey: .stick),
          innerRadius: try container.decode(Double.self, forKey: .innerRadius),
          outerRadius: try container.decode(Double.self, forKey: .outerRadius),
          fromDegrees: from,
          toDegrees: to,
          hysteresis: try container.decode(Double.self, forKey: .hysteresis)
        )
      )
    case .triggerBand:
      self = .triggerBand(
        RemappingTriggerBandSource(
          trigger: try container.decode(RemappingTriggerSource.self, forKey: .trigger),
          from: try container.decode(Double.self, forKey: .from),
          to: try container.decode(Double.self, forKey: .to),
          hysteresis: try container.decode(Double.self, forKey: .hysteresis)
        )
      )
    case .touchArea:
      self = .touchArea(
        RemappingTouchAreaSource(
          surface: try container.decode(RemappingTouchSurface.self, forKey: .surface),
          x: try container.decode(Double.self, forKey: .x),
          y: try container.decode(Double.self, forKey: .y),
          width: try container.decode(Double.self, forKey: .width),
          height: try container.decode(Double.self, forKey: .height)
        )
      )
    }
  }

  /// Encodes the case under its `type` value with only its own keys.
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .button(let button):
      try container.encode(Kind.button, forKey: .type)
      try container.encode(button, forKey: .button)
    case .dpad(let direction):
      try container.encode(Kind.dpad, forKey: .type)
      try container.encode(direction, forKey: .direction)
    case .axis(let axis):
      try container.encode(Kind.axis, forKey: .type)
      try container.encode(axis, forKey: .axis)
    case .axisDirection(let axis, let direction):
      try container.encode(Kind.axisDirection, forKey: .type)
      try container.encode(axis, forKey: .axis)
      try container.encode(direction, forKey: .direction)
    case .triggerStage(let trigger, let stage):
      try container.encode(Kind.triggerStage, forKey: .type)
      try container.encode(trigger, forKey: .trigger)
      try container.encode(stage, forKey: .stage)
    case .motionLean(let direction):
      try container.encode(Kind.motionLean, forKey: .type)
      try container.encode(direction, forKey: .direction)
    case .touchContact(let surface):
      try container.encode(Kind.touchContact, forKey: .type)
      try container.encode(surface, forKey: .surface)
    case .touchGrid(let source):
      try container.encode(Kind.touchGrid, forKey: .type)
      try container.encode(source.surface, forKey: .surface)
      try container.encode(source.columns, forKey: .columns)
      try container.encode(source.rows, forKey: .rows)
      try container.encode(source.column, forKey: .column)
      try container.encode(source.row, forKey: .row)
    case .touchSwipe(let source):
      try container.encode(Kind.touchSwipe, forKey: .type)
      try container.encode(source.surface, forKey: .surface)
      try container.encode(source.direction, forKey: .direction)
      try container.encode(source.minimumDistance, forKey: .minimumDistance)
    case .stickRegion(let source):
      try container.encode(Kind.stickRegion, forKey: .type)
      try container.encode(source.stick, forKey: .stick)
      try container.encode(source.innerRadius, forKey: .innerRadius)
      try container.encode(source.outerRadius, forKey: .outerRadius)
      try container.encodeIfPresent(source.fromDegrees, forKey: .fromDegrees)
      try container.encodeIfPresent(source.toDegrees, forKey: .toDegrees)
      try container.encode(source.hysteresis, forKey: .hysteresis)
    case .triggerBand(let source):
      try container.encode(Kind.triggerBand, forKey: .type)
      try container.encode(source.trigger, forKey: .trigger)
      try container.encode(source.from, forKey: .from)
      try container.encode(source.to, forKey: .to)
      try container.encode(source.hysteresis, forKey: .hysteresis)
    case .touchArea(let source):
      try container.encode(Kind.touchArea, forKey: .type)
      try container.encode(source.surface, forKey: .surface)
      try container.encode(source.x, forKey: .x)
      try container.encode(source.y, forKey: .y)
      try container.encode(source.width, forKey: .width)
      try container.encode(source.height, forKey: .height)
    }
  }
}
