/// One fixed input-report layout and the reports it selects.
public struct ControllerInputLayout: Equatable, Sendable {
  /// The longest report a layout selects, counting the report ID byte.
  public static let maximumReportLength = 64

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
  /// The touch contacts that stand for controls; nil when the layout has none.
  ///
  /// They decide the controls they name after every other part of the layout.
  public let touch: Touch?

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
    rightTrigger: Trigger?,
    touch: Touch?
  ) throws(ControllerRecordProblem) {
    guard reportID != 0 else {
      throw ControllerRecordProblem(
        code: .invalidControllerRecord,
        key: "error.E5007.inputLayout.reportIdRange",
        "an input report ID is 1...255"
      )
    }
    guard (1...Self.maximumReportLength).contains(minimumLength),
      reportID == nil || minimumLength >= 2
    else {
      throw ControllerRecordProblem(
        code: .invalidControllerRecord,
        key: "error.E5007.inputLayout.reportLength",
        arguments: ["\(Self.maximumReportLength)"],
        "an input report is 1...\(Self.maximumReportLength) bytes long, with its ID byte: "
          + "the \(Self.maximumReportLength)-byte ceiling for a layout report"
      )
    }
    let fields =
      try buttons.map(\.1) + [leftTrigger, rightTrigger].compactMap { $0?.button }
      + (touch?.contacts.fields ?? [])
      + Self.hatFields(of: hat)
    let valueFields = axes.map(\.field) + [leftTrigger, rightTrigger].compactMap { $0?.analog }
    try Self.checkFieldPlacement(
      fields: fields,
      valueFields: valueFields,
      reportID: reportID,
      minimumLength: minimumLength
    )
    try Self.checkControlNames(buttons: buttons, axes: axes, touch: touch)
    try Self.checkValueRanges(axes: axes, leftTrigger: leftTrigger, rightTrigger: rightTrigger)
    guard
      !buttons.isEmpty || !axes.isEmpty || !hat.isEmpty || leftTrigger != nil
        || rightTrigger != nil || touch != nil
    else {
      throw ControllerRecordProblem(
        code: .invalidControllerRecord,
        key: "error.E5007.inputLayout.noControls",
        "an input layout decodes at least one control"
      )
    }

    self.reportID = reportID
    self.minimumLength = minimumLength
    self.requiresExactLength = requiresExactLength
    self.buttons = Self.groupedByControl(buttons)
    self.axes = axes
    self.hat = hat
    self.leftTrigger = leftTrigger
    self.rightTrigger = rightTrigger
    self.touch = touch
  }

  /// Every control the layout decodes.
  var controls: Set<Control> {
    var decoded = Set(buttons.map(\.control)).union(axes.map(\.control))
    if !hat.isEmpty { decoded.formUnion(Control.dpad) }
    if leftTrigger != nil { decoded.insert(.leftTrigger) }
    if rightTrigger != nil { decoded.insert(.rightTrigger) }
    return decoded.union(touch?.controls ?? [])
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

extension ControllerInputLayout {
  /// The bit fields the hat sources read, after checking that each source is well formed.
  fileprivate static func hatFields(
    of hat: [HatSource]
  ) throws(ControllerRecordProblem) -> [ReportBitField] {
    var fields: [ReportBitField] = []
    for source in hat {
      switch source {
      case .eightWay(let field, _):
        guard (3...8).contains(field.bitSize) else {
          throw ControllerRecordProblem(
            code: .invalidControllerRecord,
            key: "error.E5007.inputLayout.hatBits",
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
            key: "error.E5007.inputLayout.hatTable",
            "a table hat names directions for values its bits hold, and no neutral entry"
          )
        }
        fields.append(field)
      }
    }
    return fields
  }

  /// Fails unless every field is 1 to 32 bits, lies after the report ID and inside the report,
  /// and every value field has a valid byte order.
  fileprivate static func checkFieldPlacement(
    fields: [ReportBitField],
    valueFields: [ReportValueField],
    reportID: UInt8?,
    minimumLength: Int
  ) throws(ControllerRecordProblem) {
    let spans =
      fields.map { ($0.bitOffset, $0.bitSize) } + valueFields.map { ($0.bitOffset, $0.bitSize) }
    let readable = (reportID == nil ? 0 : 8)..<(minimumLength * 8)
    guard spans.allSatisfy({ (1...ReportBitField.maximumBitSize).contains($0.1) }) else {
      throw ControllerRecordProblem(
        code: .invalidControllerRecord,
        key: "error.E5007.inputLayout.fieldBits",
        arguments: ["\(ReportBitField.maximumBitSize)"],
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
        key: "error.E5007.inputLayout.fieldOutside",
        "input fields must lie after the report ID byte and inside the report length"
      )
    }
    guard valueFields.allSatisfy(\.hasValidByteOrder) else {
      throw ControllerRecordProblem(
        code: .invalidControllerRecord,
        key: "error.E5007.inputLayout.bigEndian",
        "a BigEndian field starts on a byte boundary and is 16, 24 or 32 bits"
      )
    }
  }

  /// Fails unless buttons, axes, and touch spots name the kind of control that belongs to them.
  fileprivate static func checkControlNames(
    buttons: [(Control, ReportBitField)],
    axes: [Axis],
    touch: Touch?
  ) throws(ControllerRecordProblem) {
    guard buttons.allSatisfy({ !nonButtonControls.contains($0.0) }) else {
      throw ControllerRecordProblem(
        code: .invalidControllerRecord,
        key: "error.E5007.inputLayout.buttonControl",
        "a button names a digital control, not the D-pad or a stick axis"
      )
    }
    let axisControls =
      axes.map(\.control)
      + (touch?.sticks ?? []).flatMap { [$0.alongX.control, $0.alongY.control] }
    guard axisControls.allSatisfy(Control.stickAxes.contains),
      Set(axisControls).count == axisControls.count
    else {
      throw ControllerRecordProblem(
        code: .invalidControllerRecord,
        key: "error.E5007.inputLayout.axesDistinct",
        "axes name distinct stick axes"
      )
    }
    guard (touch?.spots ?? []).allSatisfy({ !Control.stickAxes.contains($0.control) }) else {
      throw ControllerRecordProblem(
        code: .invalidControllerRecord,
        key: "error.E5007.inputLayout.touchSpotControl",
        "a touch spot names a button, a D-pad direction or a trigger, not a stick axis"
      )
    }
  }

  /// Fails unless axis and trigger value ranges fit their fields and each trigger has a source.
  fileprivate static func checkValueRanges(
    axes: [Axis],
    leftTrigger: Trigger?,
    rightTrigger: Trigger?
  ) throws(ControllerRecordProblem) {
    guard
      axes.map(\.field).allSatisfy({
        $0.maximum - $0.minimum >= 2 && $0.fullRange.contains($0.minimum)
          && $0.fullRange.contains($0.maximum)
      })
    else {
      throw ControllerRecordProblem(
        code: .invalidControllerRecord,
        key: "error.E5007.inputLayout.axisRange",
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
        key: "error.E5007.inputLayout.triggerRange",
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
        key: "error.E5007.inputLayout.axisSymmetric",
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
        key: "error.E5007.inputLayout.triggerSources",
        "a trigger names an analog value, a button, or both"
      )
    }
  }

  /// One button per control, in first-seen order, holding every field that names the control.
  fileprivate static func groupedByControl(_ buttons: [(Control, ReportBitField)]) -> [Button] {
    var grouped: [Button] = []
    for (control, field) in buttons {
      if let index = grouped.firstIndex(where: { $0.control == control }) {
        grouped[index] = Button(control: control, fields: grouped[index].fields + [field])
      } else {
        grouped.append(Button(control: control, fields: [field]))
      }
    }
    return grouped
  }
}
