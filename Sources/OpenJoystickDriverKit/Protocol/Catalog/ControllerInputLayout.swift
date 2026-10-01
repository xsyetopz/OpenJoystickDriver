/// The bits `mask` selects in byte `byte` of an input report.
public struct ReportBitField: Hashable, Sendable {
  public let byte: Int
  public let mask: UInt8

  func isSet(in bytes: [UInt8]) -> Bool { bytes[byte] & mask != 0 }

  /// The selected bits shifted down to bit 0.
  func value(in bytes: [UInt8]) -> Int { Int((bytes[byte] & mask) >> mask.trailingZeroBitCount) }
}

/// A controller record's fixed input-report layout, for a pad whose reports no protocol driver
/// decodes and whose HID descriptor does not describe them. ``ReportLayoutDriver`` reads it.
public struct ControllerInputLayout: Equatable, Sendable {
  /// A digital control, pressed while any of its fields has a set bit.
  public struct Button: Equatable, Sendable {
    public let control: ControlID
    public let fields: [ReportBitField]
  }

  /// One stick axis. The raw value grows right on X and down on Y, as in HID.
  public struct Axis: Equatable, Sendable {
    public let control: ControlID
    public let byte: Int
    /// 8, or 16 for a little-endian value in `byte` and `byte + 1`.
    public let bits: Int
    public let isSigned: Bool
    public let minimum: Int
    public let maximum: Int
    public let isInverted: Bool

    /// The representable range of a raw value of this width and signedness.
    var fullRange: ClosedRange<Int> { Self.fullRange(bits: bits, isSigned: isSigned) }

    static func fullRange(bits: Int, isSigned: Bool) -> ClosedRange<Int> {
      switch (bits == 16, isSigned) {
      case (false, false): 0...255
      case (false, true): -128...127
      case (true, false): 0...65_535
      case (true, true): -32_768...32_767
      }
    }

    /// The raw value scaled to -1...1 around the middle of `minimum...maximum`, clamped. For
    /// 0...255 the center is 128, 0 reads -1 and 255 reads 1.
    func value(in bytes: [UInt8]) -> Float {
      var raw = Int(bytes[byte])
      if bits == 16 { raw |= Int(bytes[byte + 1]) << 8 }
      if isSigned {
        raw = bits == 16 ? Int(Int16(truncatingIfNeeded: raw)) : Int(Int8(truncatingIfNeeded: raw))
      }
      let center = Float(minimum) + Float(maximum - minimum + 1) / 2
      let offset = Float(raw) - center
      let span = offset >= 0 ? Float(maximum) - center : center - Float(minimum)
      let normalized = max(-1, min(1, offset / span))
      return isInverted ? -normalized : normalized
    }
  }

  /// One source of the hat; the first source that reads a direction wins.
  public enum HatSource: Equatable, Sendable {
    /// Values 0–7 read north, then clockwise to north-west; any other value is neutral. With
    /// `neutralUntilNonzero`, 0 also reads neutral until the field has been nonzero in the
    /// session, for a pad that sends 0 before its hat is live.
    case eightWay(ReportBitField, neutralUntilNonzero: Bool)
    /// One field per direction; opposing directions cancel.
    case directions(
      up: ReportBitField,
      right: ReportBitField,
      down: ReportBitField,
      left: ReportBitField
    )
  }

  /// An analog byte read as 0–255, a button that reads as fully pulled, or both.
  public struct Trigger: Equatable, Sendable {
    public let byte: Int?
    public let button: ReportBitField?

    func value(in bytes: [UInt8]) -> UnipolarValue {
      if button?.isSet(in: bytes) == true { return UnipolarValue(normalized: 1) }
      return UnipolarValue(normalized: byte.map { Float(bytes[$0]) / 255 } ?? 0)
    }
  }

  static let stickAxes: [ControlID] = [.leftStickX, .leftStickY, .rightStickX, .rightStickY]
  /// Controls a button may not name: the hat, the stick axes and the analog triggers.
  static let nonButtonControls: Set<ControlID> = Set(
    stickAxes + [.dpad, .leftTrigger, .rightTrigger]
  )

  /// The ID byte 0 must carry; nil for a report without an ID.
  public let reportID: UInt8?
  /// Shorter reports are ignored. With a report ID, the length counts the ID byte.
  public let minimumLength: Int
  public let buttons: [Button]
  public let axes: [Axis]
  public let hat: [HatSource]
  public let leftTrigger: Trigger?
  public let rightTrigger: Trigger?

  /// Fails unless every field lies after the report ID inside the minimum length, every mask
  /// selects at least one bit, and each control is named where its kind belongs.
  init(
    reportID: UInt8?,
    minimumLength: Int,
    buttons: [(ControlID, ReportBitField)],
    axes: [Axis],
    hat: [HatSource],
    leftTrigger: Trigger?,
    rightTrigger: Trigger?
  ) throws(ControllerRecordProblem) {
    guard reportID != 0 else { throw ControllerRecordProblem("an input report ID is 1...255") }
    guard (1...64).contains(minimumLength), reportID == nil || minimumLength >= 2 else {
      throw ControllerRecordProblem("an input report is 1...64 bytes long, with its ID byte")
    }
    let readable = (reportID == nil ? 0 : 1)..<minimumLength
    var fields = buttons.map(\.1) + [leftTrigger, rightTrigger].compactMap { $0?.button }
    for source in hat {
      switch source {
      case .eightWay(let field, _):
        let shifted = field.mask >> field.mask.trailingZeroBitCount
        guard shifted >= 0x07, shifted & (shifted &+ 1) == 0 else {
          throw ControllerRecordProblem("an 8-way hat mask is at least 3 adjacent bits")
        }
        fields.append(field)
      case .directions(let up, let right, let down, let left): fields += [up, right, down, left]
      }
    }
    let bytes =
      fields.map(\.byte) + [leftTrigger, rightTrigger].compactMap { $0?.byte }
      + axes.flatMap { $0.bits == 16 ? [$0.byte, $0.byte + 1] : [$0.byte] }
    guard fields.allSatisfy({ $0.mask != 0 }), bytes.allSatisfy(readable.contains) else {
      throw ControllerRecordProblem(
        "input fields must select at least one bit after the report ID inside the report"
      )
    }
    guard buttons.allSatisfy({ !Self.nonButtonControls.contains($0.0) }) else {
      throw ControllerRecordProblem(
        "a button names a digital control, not the hat, a stick or a trigger"
      )
    }
    guard axes.allSatisfy({ Self.stickAxes.contains($0.control) }),
      Set(axes.map(\.control)).count == axes.count
    else { throw ControllerRecordProblem("axes name distinct stick axes") }
    guard
      axes.allSatisfy({
        ($0.bits == 8 || $0.bits == 16) && $0.maximum - $0.minimum >= 2
          && $0.fullRange.contains($0.minimum) && $0.fullRange.contains($0.maximum)
      })
    else {
      throw ControllerRecordProblem("an axis is 8 or 16 bits with min below max inside its range")
    }
    guard
      [leftTrigger, rightTrigger].allSatisfy({ $0 == nil || $0?.byte != nil || $0?.button != nil })
    else { throw ControllerRecordProblem("a trigger names an analog byte, a button, or both") }
    guard
      !buttons.isEmpty || !axes.isEmpty || !hat.isEmpty || leftTrigger != nil
        || rightTrigger != nil
    else { throw ControllerRecordProblem("an input layout decodes at least one control") }

    var grouped: [Button] = []
    for (control, field) in buttons {
      if let index = grouped.firstIndex(where: { $0.control == control }) {
        grouped[index] = Button(control: control, fields: grouped[index].fields + [field])
      } else {
        grouped.append(Button(control: control, fields: [field]))
      }
    }
    self.reportID = reportID
    self.minimumLength = minimumLength
    self.buttons = grouped
    self.axes = axes
    self.hat = hat
    self.leftTrigger = leftTrigger
    self.rightTrigger = rightTrigger
  }

  /// Every control the layout decodes.
  var controls: Set<ControlID> {
    var controls = Set(buttons.map(\.control)).union(axes.map(\.control))
    if !hat.isEmpty { controls.insert(.dpad) }
    if leftTrigger != nil { controls.insert(.leftTrigger) }
    if rightTrigger != nil { controls.insert(.rightTrigger) }
    return controls
  }
}

extension HatDirection {
  /// The direction four D-pad flags hold; opposing directions cancel to neutral.
  init(up: Bool, right: Bool, down: Bool, left: Bool) {
    self =
      switch (up && !down, right && !left, down && !up, left && !right) {
      case (true, false, false, false): .north
      case (true, true, false, false): .northEast
      case (false, true, false, false): .east
      case (false, true, true, false): .southEast
      case (false, false, true, false): .south
      case (false, false, true, true): .southWest
      case (false, false, false, true): .west
      case (true, false, false, true): .northWest
      default: .neutral
      }
  }

  /// The eight directions from north clockwise, indexed by an 8-way hat value.
  static let clockwiseFromNorth: [HatDirection] = [
    .north, .northEast, .east, .southEast, .south, .southWest, .west, .northWest,
  ]
}
