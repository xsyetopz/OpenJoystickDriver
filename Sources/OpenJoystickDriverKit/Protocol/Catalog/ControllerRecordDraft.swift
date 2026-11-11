import Foundation

/// A starting controller record for one connected controller, from its HID report descriptor
/// and the input reports it sent while you pressed its controls.
///
/// The draft maps what the descriptor states plainly: one-bit buttons 1 to 11 in the order the
/// `HIDDescriptor` family reads them, byte-aligned X, Y, Rx, and Ry sticks, byte-aligned Z and
/// Rz triggers, and a hat whose value starts at 0. It does not guess at anything else; the bytes
/// that changed during the capture show where the remaining controls sit.
public struct ControllerRecordDraft: Sendable {
  /// One report byte that took more than one value during the capture.
  public struct ChangedByte: Codable, Equatable, Sendable {
    /// The index of the report byte.
    public let byte: Int
    /// The lowest value the byte took during the capture.
    public let minimum: Int
    /// The highest value the byte took during the capture.
    public let maximum: Int
  }

  /// `Add`, a Controller document, for a model without a bundled record, otherwise `Patch`, a
  /// ControllerPatch document.
  public let operation: ControllerRecordOperation
  /// The protocol family the draft names: `HIDReportLayout` when a control mapped, otherwise
  /// `HIDDescriptor`.
  public let family: PhysicalProtocolID
  /// The input report the draft reads, or nil when nothing chose one.
  public let reportID: UInt8?
  /// The length of the chosen input report, or nil when nothing chose one.
  public let reportLength: Int?
  /// The number of reports captured with the chosen ID and at least the chosen length.
  public let capturedReports: Int
  /// The report bytes that took more than one value, in byte order.
  public let changedBytes: [ChangedByte]
  /// The record document as an XML property list, in the text of ``OrderedJSON/plistData()``, as
  /// `ojd record install` reads it.
  public let text: String
  /// ``text`` as UTF-8.
  public var document: Data { Data(text.utf8) }

  /// Builds the draft for `model`. `reports` are the captured input reports as macOS
  /// delivered them, with the report ID in byte 0 of a numbered report.
  ///
  /// Returns nil for a model with a bundled record when no control mapped, because a patch
  /// that only names `HIDDescriptor` would replace the bundled family with nothing better.
  public init?(
    model: ControllerModelID,
    bundled: Bool,
    descriptor: [UInt8]?,
    reports: [[UInt8]]
  ) {
    let parsed = descriptor.flatMap(HIDReportDescriptorParser.parse(descriptor:))
      .flatMap { $0.containsUnsupportedItem ? nil : $0 }
    let layout = parsed.flatMap(Self.bestLayout(in:))
    guard layout != nil || !bundled else { return nil }
    operation = bundled ? .patch : .add
    family = layout == nil ? .hidDescriptor : .hidReportLayout

    let chosen: (id: UInt8?, length: Int)?
    if let layout {
      chosen = (layout.reportID, layout.length)
    } else {
      chosen = Self.commonLength(of: reports).map { (nil, $0) }
    }
    reportID = chosen?.id
    reportLength = chosen?.length
    let matching =
      chosen.map { chosen in
        reports.filter { report in
          report.count >= chosen.length && chosen.id.map { report.first == $0 } ?? true
        }
      } ?? []
    capturedReports = matching.count
    changedBytes = Self.changedBytes(in: matching, length: chosen?.length ?? 0)

    let defaultMode: [String: Any] = ["id": "default", "protocol": ["family": family.rawValue]]
    var fields: [String: Any] = ["modes": [defaultMode]]
    if let layout { fields["input"] = layout.json }
    let body: [String: Any]
    if bundled {
      var removed: [String] = []
      let record = ControllerRecordSet.bundled.records[model]
      if record?.family != family.rawValue {
        // The default mode of the drafted family replaces the bundled one instead of merging.
        removed.append("modes.default")
        if record?.profile.hidUsageMap != nil, fields["input"] != nil {
          // The byte layout replaces the old record's usage map instead of merging into it.
          removed.append("input.hidUsageMap")
        }
      }
      body = ControllerPatch.document(selector: .identity(model), body: fields, remove: removed)
    } else {
      fields["apiVersion"] = OpenJoystickDriverAPI.version
      fields["kind"] = ControllerRecordDocument.kind
      fields["vendorID"] = Int(model.vendorID)
      fields["productID"] = Int(model.productID)
      body = fields
    }
    guard let json = try? OrderedJSON(foundation: body),
      let data = try? json.plistData()
    else { return nil }
    text = String(decoding: data, as: UTF8.self)
  }

  /// The most common length among `reports`, the longest on a tie, or nil when none is 1 to 64
  /// bytes long.
  private static func commonLength(of reports: [[UInt8]]) -> Int? {
    var counts: [Int: Int] = [:]
    for report in reports where (1...64).contains(report.count) {
      counts[report.count, default: 0] += 1
    }
    return counts.max { ($0.value, $0.key) < ($1.value, $1.key) }?.key
  }

  /// Finds the bytes of `reports` that took more than one value, with the lowest and highest value
  /// of each; `length` bytes are compared.
  private static func changedBytes(in reports: [[UInt8]], length: Int) -> [ChangedByte] {
    guard let first = reports.first else { return [] }
    return (0..<length).compactMap { index in
      var low = first[index]
      var high = first[index]
      for report in reports.dropFirst() {
        low = min(low, report[index])
        high = max(high, report[index])
      }
      return low == high ? nil : ChangedByte(byte: index, minimum: Int(low), maximum: Int(high))
    }
  }

  /// The input report with the most mapped controls, the lowest ID on a tie.
  private static func bestLayout(in parsed: HIDParsedDescriptor) -> DraftLayout? {
    parsed.inputReportIDs.sorted().compactMap { DraftLayout(parsed, reportID: $0) }
      .max { ($0.controlCount, $1.reportID ?? 0) < ($1.controlCount, $0.reportID ?? 0) }
  }
}

/// The `input` section of a draft for one report of a parsed descriptor.
private struct DraftLayout {
  /// The report ID, or nil when the descriptor uses no report IDs.
  let reportID: UInt8?
  /// The report length in bytes, including the ID byte.
  let length: Int
  /// The mapped buttons, as `input.buttons` entries.
  private var buttons: [[String: Any]] = []
  /// The mapped stick axes, as `input.axes` entries.
  private var axes: [[String: Any]] = []
  /// The mapped hat, as an `input.hat` entry; nil when none maps.
  private var hat: [String: Any]?
  /// The mapped triggers, by their `input` key.
  private var triggers: [String: [String: Any]] = [:]

  /// The number of controls that mapped.
  var controlCount: Int { buttons.count + axes.count + (hat == nil ? 0 : 1) + triggers.count }

  /// The layout as the `input` section of a record.
  var json: [String: Any] {
    var report: [String: Any] = ["length": ["atLeast": length]]
    if let reportID { report["id"] = Int(reportID) }
    var input: [String: Any] = ["report": report]
    if !buttons.isEmpty { input["buttons"] = buttons }
    if !axes.isEmpty { input["axes"] = axes }
    if let hat { input["hat"] = [hat] }
    for (key, trigger) in triggers { input[key] = trigger }
    return ["layouts": [input]]
  }

  /// The button order the `HIDDescriptor` family reads in its standard layout.
  private static let standardButtons: [Control] = [
    .south, .east, .west, .north, .leftShoulder, .rightShoulder, .back, .start,
    .leftStickClick, .rightStickClick, .guide,
  ]
  /// The Generic Desktop usages of the stick axes (X, Y, Rx, Ry) and the controls they map to.
  private static let stickAxes: [Int: Control] = [
    0x30: .leftStickX, 0x31: .leftStickY, 0x33: .rightStickX, 0x34: .rightStickY,
  ]
  /// The Generic Desktop usages of the trigger axes (Z, Rz) and their `input` keys.
  private static let triggerAxes = [0x32: "leftTrigger", 0x35: "rightTrigger"]

  /// Nil when no control of report `reportID` maps, or the report is longer than 64 bytes with
  /// its ID byte.
  init?(_ parsed: HIDParsedDescriptor, reportID id: UInt8) {
    reportID = id == 0 ? nil : id
    let base = id == 0 ? 0 : 1
    guard let payload = parsed.payloadSizeBytesByReportID[id], payload + base <= 64,
      payload + base >= (id == 0 ? 1 : 2)
    else { return nil }
    length = payload + base
    var named = Set<Control>()
    var triggerKeys = Set<String>()
    for field in parsed.fields where field.reportID == id && !field.flags.isRelative {
      let bitOffset = base * 8 + field.bitOffset
      let shift = field.bitOffset % 8
      switch (field.usagePage, field.usage) {
      case (0x09, 1...Self.standardButtons.count) where field.bitSize == 1:
        let control = Self.standardButtons[field.usage - 1]
        guard named.insert(control).inserted else { continue }
        buttons.append(["control": control.rawValue, "bitOffset": bitOffset, "bitSize": 1])
      case (0x01, let usage) where Self.stickAxes[usage] != nil:
        guard axes.count < 4, let control = Self.stickAxes[usage], !named.contains(control),
          let axis = Self.axis(field, control: control, bitOffset: bitOffset)
        else { continue }
        named.insert(control)
        axes.append(axis)
      case (0x01, let usage) where Self.triggerAxes[usage] != nil:
        guard let key = Self.triggerAxes[usage], field.bitSize == 8, shift == 0,
          field.logicalMin == 0, triggerKeys.insert(key).inserted
        else { continue }
        triggers[key] = ["bitOffset": bitOffset, "bitSize": 8]
      case (0x01, 0x39):
        guard hat == nil, (3...8).contains(field.bitSize), shift + field.bitSize <= 8,
          field.logicalMin == 0
        else { continue }
        hat = ["encoding": "EightWay", "bitOffset": bitOffset, "bitSize": field.bitSize]
      default: continue
      }
    }
    guard controlCount > 0 else { return nil }
  }

  /// A byte-aligned 8- or 16-bit axis, with its logical range when it is not the full range.
  private static func axis(_ field: HIDField, control: Control, bitOffset: Int) -> [String: Any]? {
    guard field.bitOffset.isMultiple(of: 8), field.bitSize == 8 || field.bitSize == 16 else {
      return nil
    }
    let isSigned = field.logicalMin < 0
    let full = ReportValueField.fullRange(bitSize: field.bitSize, isSigned: isSigned)
    guard full.contains(field.logicalMin), full.contains(field.logicalMax),
      field.logicalMin < field.logicalMax
    else { return nil }
    var axis: [String: Any] = [
      "control": control.rawValue, "bitOffset": bitOffset, "bitSize": field.bitSize,
    ]
    if isSigned { axis["signed"] = true }
    if field.logicalMin != full.lowerBound || field.logicalMax != full.upperBound {
      axis["min"] = field.logicalMin
      axis["max"] = field.logicalMax
    }
    return axis
  }
}
