/// The byte order of a multi-byte input field.
public enum ReportByteOrder: String, Sendable {
  /// The first byte holds the least significant bits, as HID packs a field.
  case littleEndian = "LittleEndian"
  /// The first byte holds the most significant bits; only a byte-aligned field of 16, 24 or 32
  /// bits has this order.
  case bigEndian = "BigEndian"
}

/// The `bitSize` bits from `bitOffset` of an input report, counted from the least significant bit
/// of byte 0.
public struct ReportBitField: Hashable, Sendable {
  /// The widest field, in bits.
  static let maximumBitSize = 32

  /// The index of the first bit of the field.
  public let bitOffset: Int
  /// The number of bits of the field, 1 to 32.
  public let bitSize: Int

  /// Whether any bit of the field is set in `bytes`.
  func isSet(in bytes: [UInt8]) -> Bool {
    Self.bits(in: bytes, offset: bitOffset, size: bitSize) != 0
  }

  /// The field as an unsigned little-endian number.
  func value(in bytes: [UInt8]) -> Int {
    Int(Self.bits(in: bytes, offset: bitOffset, size: bitSize))
  }

  /// The `size` bits from `offset` as an unsigned little-endian number: bit `offset` of the report
  /// is bit 0 of the result.
  static func bits(in bytes: [UInt8], offset: Int, size: Int) -> UInt64 {
    var value: UInt64 = 0
    for index in 0..<size {
      let bit = offset + index
      if bytes[bit >> 3] >> UInt8(bit & 7) & 1 != 0 { value |= 1 << UInt64(index) }
    }
    return value
  }
}

/// A numeric input field: the bits, their byte order and signedness, and the raw range that
/// scales to the full travel.
public struct ReportValueField: Hashable, Sendable {
  /// The index of the first bit of the field.
  public let bitOffset: Int
  /// The number of bits of the field, 1 to 32.
  public let bitSize: Int
  /// The byte order of the field.
  public let byteOrder: ReportByteOrder
  /// Whether the raw value is two's complement over `bitSize`.
  public let isSigned: Bool
  /// The raw value that reads as the lowest position.
  public let minimum: Int
  /// The raw value that reads as the highest position.
  public let maximum: Int

  /// The representable range of a raw value of this size and signedness.
  var fullRange: ClosedRange<Int> { Self.fullRange(bitSize: bitSize, isSigned: isSigned) }

  /// The representable range of a raw value of `bitSize` bits and the given signedness.
  static func fullRange(bitSize: Int, isSigned: Bool) -> ClosedRange<Int> {
    isSigned
      ? -(1 << (bitSize - 1))...((1 << (bitSize - 1)) - 1)
      : 0...((1 << bitSize) - 1)
  }

  /// Whether the byte order, offset and size agree: a big-endian field starts on a byte boundary
  /// and holds 16, 24 or 32 bits.
  var hasValidByteOrder: Bool {
    byteOrder == .littleEndian || (bitOffset.isMultiple(of: 8) && [16, 24, 32].contains(bitSize))
  }

  /// The raw value in `bytes`, sign-extended when the field is signed.
  func raw(in bytes: [UInt8]) -> Int {
    var value: UInt64
    switch byteOrder {
    case .littleEndian: value = ReportBitField.bits(in: bytes, offset: bitOffset, size: bitSize)
    case .bigEndian:
      value = 0
      for index in 0..<(bitSize / 8) { value = value << 8 | UInt64(bytes[bitOffset / 8 + index]) }
    }
    let number = Int(value)
    guard isSigned, number >= 1 << (bitSize - 1) else { return number }
    return number - (1 << bitSize)
  }
}

/// A controller record's fixed input-report layouts, for a pad whose reports no protocol driver
/// decodes and whose HID descriptor does not describe them. ``ReportLayoutDriver`` reads them.
///
/// Each report is decoded by the one layout that selects it. A report that no layout selects is
/// ignored. A layout changes only the controls it names; every other control keeps its last value.
public struct ControllerInputLayouts: Equatable, Sendable {
  /// The layouts, in the order the record lists them.
  public let layouts: [ControllerInputLayout]

  /// Fails unless there is at least one layout and no two layouts select the same report.
  init(layouts: [ControllerInputLayout]) throws(ControllerRecordProblem) {
    guard !layouts.isEmpty else {
      throw ControllerRecordProblem(
        code: .invalidControllerRecord,
        "input lists at least one layout"
      )
    }
    for (index, layout) in layouts.enumerated() {
      for other in layouts[(index + 1)...] where layout.selectsSameReport(as: other) {
        throw ControllerRecordProblem(
          code: .invalidControllerRecord,
          "two input layouts select the same report: \(layout.selectorDescription) and "
            + other.selectorDescription
        )
      }
    }
    self.layouts = layouts
  }

  /// Every control any layout decodes.
  var controls: Set<Control> { layouts.reduce(into: []) { $0.formUnion($1.controls) } }

  /// The index of the layout that selects `bytes`; nil when none does.
  func indexOfLayout(selecting bytes: [UInt8]) -> Int? {
    layouts.firstIndex { $0.selects(bytes) }
  }
}

/// One fixed input-report layout and the reports it selects.
public struct ControllerInputLayout: Equatable, Sendable {
  /// The longest report a layout selects, counting the report ID byte.
  public static let maximumReportLength = 64

  /// A digital control, pressed while any of its fields has a set bit.
  public struct Button: Equatable, Sendable {
    /// The control the button drives.
    public let control: Control
    /// The bit fields of which any set bit presses the button.
    public let fields: [ReportBitField]
  }

  /// One stick axis.
  ///
  /// The raw value grows right on X and down on Y, as in HID.
  public struct Axis: Equatable, Sendable {
    /// The stick axis the value drives.
    public let control: Control
    /// The bits of the value and the raw range that scales to -1...1.
    public let field: ReportValueField
    /// Whether the normalized value is negated.
    public let isInverted: Bool
    /// A signed axis centered on 0 whose positive and negative sides share one divisor,
    /// `maximum`: the raw value divided by `maximum`, clamped, so the lowest value reads -1.
    public let isSymmetric: Bool

    /// The raw value scaled to -1...1 around the middle of `minimum...maximum`, clamped.
    ///
    /// For 0...255 the center is 128, 0 reads -1 and 255 reads 1. A symmetric axis divides by
    /// `maximum` instead. The arithmetic is in `Double`, which holds every 32-bit raw value.
    func value(in bytes: [UInt8]) -> Float {
      let raw = Double(field.raw(in: bytes))
      let low = Double(field.minimum)
      let high = Double(field.maximum)
      let normalized: Double
      if isSymmetric {
        normalized = max(-1, min(1, raw / high))
      } else {
        let center = low + (high - low + 1) / 2
        let offset = raw - center
        let span = offset >= 0 ? high - center : center - low
        normalized = max(-1, min(1, offset / span))
      }
      return Float(isInverted ? -normalized : normalized)
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
    /// The field, as a number, names a direction; a value the table lacks is neutral.
    case table(ReportBitField, [Int: HatDirection])
  }

  /// An analog value scaled to 0–1, a button that reads as fully pulled, or both.
  public struct Trigger: Equatable, Sendable {
    /// The analog value; nil when the trigger has none.
    public let analog: ReportValueField?
    /// The bit field that reads as a fully pulled trigger; nil when the trigger has none.
    public let button: ReportBitField?

    /// The trigger position in `bytes`, fully pulled when its button is set.
    ///
    /// The analog value scales from `minimum` to `maximum` and is clamped to 0...1.
    func value(in bytes: [UInt8]) -> UnipolarValue {
      if button?.isSet(in: bytes) == true { return UnipolarValue(normalized: 1) }
      guard let analog else { return UnipolarValue(normalized: 0) }
      let low = Double(analog.minimum)
      let unit = (Double(analog.raw(in: bytes)) - low) / (Double(analog.maximum) - low)
      return UnipolarValue(normalized: Float(max(0, min(1, unit))))
    }
  }

  /// Controls a button may not name: the D-pad, which the hat drives, and the stick axes.
  static let nonButtonControls: Set<Control> = Control.dpad.union(Control.stickAxes)

  /// The ID byte 0 must carry; nil for a report without an ID.
  public let reportID: UInt8?
  /// Shorter reports are ignored.
  ///
  /// With a report ID, the length counts the ID byte.
  public let minimumLength: Int
  /// Whether a report longer than `minimumLength` is ignored too.
  public let requiresExactLength: Bool
  /// The digital controls, each pressed while any of its fields has a set bit.
  public let buttons: [Button]
  /// The stick axes.
  public let axes: [Axis]
  /// The hat sources; the first one that reads a direction wins.
  public let hat: [HatSource]
  /// The left trigger; nil when the layout has none.
  public let leftTrigger: Trigger?
  /// The right trigger; nil when the layout has none.
  public let rightTrigger: Trigger?

  /// Fails unless every field lies after the report ID inside the minimum length, every field is
  /// 1 to 32 bits, and each control is named where its kind belongs.
  init(
    reportID: UInt8?,
    minimumLength: Int,
    requiresExactLength: Bool,
    buttons: [(Control, ReportBitField)],
    axes: [Axis],
    hat: [HatSource],
    leftTrigger: Trigger?,
    rightTrigger: Trigger?
  ) throws(ControllerRecordProblem) {
    guard reportID != 0 else {
      throw ControllerRecordProblem(code: .invalidControllerRecord, "an input report ID is 1...255")
    }
    guard (1...Self.maximumReportLength).contains(minimumLength),
      reportID == nil || minimumLength >= 2
    else {
      throw ControllerRecordProblem(
        code: .invalidControllerRecord,
        "an input report is 1...\(Self.maximumReportLength) bytes long, with its ID byte: "
          + "the \(Self.maximumReportLength)-byte ceiling for a layout report"
      )
    }
    var fields = buttons.map(\.1) + [leftTrigger, rightTrigger].compactMap { $0?.button }
    for source in hat {
      switch source {
      case .eightWay(let field, _):
        guard (3...8).contains(field.bitSize) else {
          throw ControllerRecordProblem(
            code: .invalidControllerRecord,
            "an 8-way hat is 3 to 8 bits"
          )
        }
        fields.append(field)
      case .directions(let up, let right, let down, let left): fields += [up, right, down, left]
      case .table(let field, let directions):
        let largest = (1 << min(field.bitSize, ReportBitField.maximumBitSize)) - 1
        guard !directions.isEmpty, directions.keys.allSatisfy({ (0...largest).contains($0) }),
          !directions.values.contains(.neutral)
        else {
          throw ControllerRecordProblem(
            code: .invalidControllerRecord,
            "a table hat names directions for values its bits hold, and no neutral entry"
          )
        }
        fields.append(field)
      }
    }
    let valueFields = axes.map(\.field) + [leftTrigger, rightTrigger].compactMap { $0?.analog }
    let spans =
      fields.map { ($0.bitOffset, $0.bitSize) } + valueFields.map { ($0.bitOffset, $0.bitSize) }
    let readable = (reportID == nil ? 0 : 8)..<(minimumLength * 8)
    guard spans.allSatisfy({ (1...ReportBitField.maximumBitSize).contains($0.1) }) else {
      throw ControllerRecordProblem(
        code: .invalidControllerRecord,
        "an input field is 1 to \(ReportBitField.maximumBitSize) bits"
      )
    }
    guard
      spans.allSatisfy({
        $0.0 >= readable.lowerBound && $0.0 + $0.1 <= readable.upperBound
      })
    else {
      throw ControllerRecordProblem(
        code: .invalidControllerRecord,
        "input fields must lie after the report ID byte and inside the report length"
      )
    }
    guard valueFields.allSatisfy(\.hasValidByteOrder) else {
      throw ControllerRecordProblem(
        code: .invalidControllerRecord,
        "a BigEndian field starts on a byte boundary and is 16, 24 or 32 bits"
      )
    }
    guard buttons.allSatisfy({ !Self.nonButtonControls.contains($0.0) }) else {
      throw ControllerRecordProblem(
        code: .invalidControllerRecord,
        "a button names a digital control, not the D-pad or a stick axis"
      )
    }
    guard axes.allSatisfy({ Control.stickAxes.contains($0.control) }),
      Set(axes.map(\.control)).count == axes.count
    else {
      throw ControllerRecordProblem(code: .invalidControllerRecord, "axes name distinct stick axes")
    }
    guard
      axes.map(\.field).allSatisfy({
        $0.maximum - $0.minimum >= 2 && $0.fullRange.contains($0.minimum)
          && $0.fullRange.contains($0.maximum)
      })
    else {
      throw ControllerRecordProblem(
        code: .invalidControllerRecord,
        "an axis has min below max inside the range of its size"
      )
    }
    guard
      [leftTrigger, rightTrigger].compactMap({ $0?.analog }).allSatisfy({
        $0.maximum > $0.minimum && $0.fullRange.contains($0.minimum)
          && $0.fullRange.contains($0.maximum)
      })
    else {
      throw ControllerRecordProblem(
        code: .invalidControllerRecord,
        "a trigger value has min below max inside the range of its size"
      )
    }
    guard
      axes.allSatisfy({
        !$0.isSymmetric || ($0.field.isSigned && $0.field.minimum < 0 && $0.field.maximum > 0)
      })
    else {
      throw ControllerRecordProblem(
        code: .invalidControllerRecord,
        "a symmetric axis is signed with min below 0 below max"
      )
    }
    guard
      [leftTrigger, rightTrigger].allSatisfy({
        $0 == nil || $0?.analog != nil || $0?.button != nil
      })
    else {
      throw ControllerRecordProblem(
        code: .invalidControllerRecord,
        "a trigger names an analog value, a button, or both"
      )
    }
    guard
      !buttons.isEmpty || !axes.isEmpty || !hat.isEmpty || leftTrigger != nil
        || rightTrigger != nil
    else {
      throw ControllerRecordProblem(
        code: .invalidControllerRecord,
        "an input layout decodes at least one control"
      )
    }

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
    self.requiresExactLength = requiresExactLength
    self.buttons = grouped
    self.axes = axes
    self.hat = hat
    self.leftTrigger = leftTrigger
    self.rightTrigger = rightTrigger
  }

  /// Every control the layout decodes.
  var controls: Set<Control> {
    var controls = Set(buttons.map(\.control)).union(axes.map(\.control))
    if !hat.isEmpty { controls.formUnion(Control.dpad) }
    if leftTrigger != nil { controls.insert(.leftTrigger) }
    if rightTrigger != nil { controls.insert(.rightTrigger) }
    return controls
  }

  /// Whether the layout selects `bytes`: the report is long enough (or exactly as long, when the
  /// layout requires it) and carries the layout's report ID.
  func selects(_ bytes: [UInt8]) -> Bool {
    bytes.count >= minimumLength && (!requiresExactLength || bytes.count == minimumLength)
      && (reportID == nil || bytes[0] == reportID)
  }

  /// Whether some report is selected by both this layout and `other`.
  ///
  /// A layout without a report ID selects reports of every ID.
  func selectsSameReport(as other: Self) -> Bool {
    if let id = reportID, let otherID = other.reportID, id != otherID { return false }
    switch (requiresExactLength, other.requiresExactLength) {
    case (true, true): return minimumLength == other.minimumLength
    case (true, false): return minimumLength >= other.minimumLength
    case (false, true): return other.minimumLength >= minimumLength
    case (false, false): return true
    }
  }

  /// The selector as the record states it, for a problem message.
  var selectorDescription: String {
    "report \(reportID.map { "ID \($0)" } ?? "without ID") "
      + "\(requiresExactLength ? "exactly" : "at least") \(minimumLength) bytes"
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

  /// The four D-pad flags the direction presses.
  var components: (up: Bool, right: Bool, down: Bool, left: Bool) {
    switch self {
    case .neutral: (false, false, false, false)
    case .north: (true, false, false, false)
    case .northEast: (true, true, false, false)
    case .east: (false, true, false, false)
    case .southEast: (false, true, true, false)
    case .south: (false, false, true, false)
    case .southWest: (false, false, true, true)
    case .west: (false, false, false, true)
    case .northWest: (true, false, false, true)
    }
  }

  /// The eight directions from north clockwise, indexed by an 8-way hat value.
  static let clockwiseFromNorth: [HatDirection] = [
    .north, .northEast, .east, .southEast, .south, .southWest, .west, .northWest,
  ]
}
