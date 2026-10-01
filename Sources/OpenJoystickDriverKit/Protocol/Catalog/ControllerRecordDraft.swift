import Foundation

/// A starting controller record for one connected controller, from its HID report descriptor
/// and the input reports it sent while you pressed its controls.
///
/// The draft maps what the descriptor states plainly: one-bit buttons 1 to 11 in the order the
/// `hid.descriptor` family reads them, byte-aligned X, Y, Rx, and Ry sticks, byte-aligned Z and
/// Rz triggers, and a hat whose value starts at 0. It does not guess at anything else; the bytes
/// that changed during the capture show where the remaining controls sit.
public struct ControllerRecordDraft: Sendable {
  /// One report byte that took more than one value during the capture.
  public struct ChangedByte: Codable, Equatable, Sendable {
    public let byte: Int
    public let minimum: Int
    public let maximum: Int
  }

  /// `add` for a model without a bundled record, otherwise `patch`.
  public let operation: ControllerRecordOperation
  /// The protocol family the draft names: `hid.report-layout` when a control mapped, otherwise
  /// `hid.descriptor`.
  public let family: PhysicalProtocolID
  /// The input report the draft reads, or nil when nothing chose one.
  public let reportID: UInt8?
  public let reportLength: Int?
  /// The number of reports captured with the chosen ID and at least the chosen length.
  public let capturedReports: Int
  public let changedBytes: [ChangedByte]
  /// The override document, as `ojd record install` reads it.
  public let document: Data

  /// Builds the draft for `identity`. `reports` are the captured input reports as macOS
  /// delivered them, with the report ID in byte 0 of a numbered report.
  ///
  /// Returns nil for a model with a bundled record when no control mapped, because a patch
  /// that only names `hid.descriptor` would replace the bundled family with nothing better.
  public init?(
    identity: ControllerIdentity,
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

    var fields: [String: Any] = ["protocol": ["family": family.rawValue]]
    if let layout { fields["input"] = layout.json }
    let body: [String: Any]
    if bundled {
      body = [
        "$schema": ControllerRecordSet.overrideSchemaID, "operation": "patch",
        "vendorID": Int(identity.vendorID), "productID": Int(identity.productID), "set": fields,
      ]
    } else {
      fields["$schema"] = ControllerRecordDocument.schemaID
      fields["vendorID"] = Int(identity.vendorID)
      fields["productID"] = Int(identity.productID)
      body = [
        "$schema": ControllerRecordSet.overrideSchemaID, "operation": "add", "record": fields,
      ]
    }
    guard
      let document = try? JSONSerialization.data(
        withJSONObject: body,
        options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
      )
    else { return nil }
    self.document = document
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
  let reportID: UInt8?
  let length: Int
  private var buttons: [[String: Any]] = []
  private var axes: [[String: Any]] = []
  private var hat: [String: Any]?
  private var triggers: [String: [String: Any]] = [:]

  var controlCount: Int { buttons.count + axes.count + (hat == nil ? 0 : 1) + triggers.count }

  var json: [String: Any] {
    var report: [String: Any] = ["length": length]
    if let reportID { report["id"] = Int(reportID) }
    var input: [String: Any] = ["report": report]
    if !buttons.isEmpty { input["buttons"] = buttons }
    if !axes.isEmpty { input["axes"] = axes }
    if let hat { input["hat"] = [hat] }
    for (key, trigger) in triggers { input[key] = trigger }
    return input
  }

  /// The button order the `hid.descriptor` family reads in its standard layout.
  private static let standardButtons: [ControlID] = [
    .faceSouth, .faceEast, .faceWest, .faceNorth, .leftShoulder, .rightShoulder, .view, .menu,
    .leftStickClick, .rightStickClick, .guide,
  ]
  private static let stickAxes: [Int: ControlID] = [
    0x30: .leftStickX, 0x31: .leftStickY, 0x33: .rightStickX, 0x34: .rightStickY,
  ]
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
    var named = Set<ControlID>()
    var triggerKeys = Set<String>()
    for field in parsed.fields where field.reportID == id && !field.flags.isRelative {
      let byte = base + field.bitOffset / 8
      let shift = field.bitOffset % 8
      switch (field.usagePage, field.usage) {
      case (0x09, 1...Self.standardButtons.count) where field.bitSize == 1:
        let control = Self.standardButtons[field.usage - 1]
        guard named.insert(control).inserted else { continue }
        buttons.append(["control": control.rawValue, "byte": byte, "mask": 1 << shift])
      case (0x01, let usage) where Self.stickAxes[usage] != nil:
        guard axes.count < 4, let control = Self.stickAxes[usage], !named.contains(control),
          let axis = Self.axis(field, control: control, byte: byte)
        else { continue }
        named.insert(control)
        axes.append(axis)
      case (0x01, let usage) where Self.triggerAxes[usage] != nil:
        guard let key = Self.triggerAxes[usage], field.bitSize == 8, shift == 0,
          field.logicalMin == 0, triggerKeys.insert(key).inserted
        else { continue }
        triggers[key] = ["byte": byte]
      case (0x01, 0x39):
        guard hat == nil, (3...8).contains(field.bitSize), shift + field.bitSize <= 8,
          field.logicalMin == 0
        else { continue }
        hat = ["encoding": "8-way", "byte": byte, "mask": ((1 << field.bitSize) - 1) << shift]
      default: continue
      }
    }
    guard controlCount > 0 else { return nil }
  }

  /// A byte-aligned 8- or 16-bit axis, with its logical range when it is not the full range.
  private static func axis(_ field: HIDField, control: ControlID, byte: Int) -> [String: Any]? {
    guard field.bitOffset.isMultiple(of: 8), field.bitSize == 8 || field.bitSize == 16 else {
      return nil
    }
    let isSigned = field.logicalMin < 0
    let full = ControllerInputLayout.Axis.fullRange(bits: field.bitSize, isSigned: isSigned)
    guard full.contains(field.logicalMin), full.contains(field.logicalMax),
      field.logicalMin < field.logicalMax
    else { return nil }
    var axis: [String: Any] = ["control": control.rawValue, "byte": byte]
    if field.bitSize == 16 { axis["bits"] = 16 }
    if isSigned { axis["signed"] = true }
    if field.logicalMin != full.lowerBound || field.logicalMax != full.upperBound {
      axis["min"] = field.logicalMin
      axis["max"] = field.logicalMax
    }
    return axis
  }
}
