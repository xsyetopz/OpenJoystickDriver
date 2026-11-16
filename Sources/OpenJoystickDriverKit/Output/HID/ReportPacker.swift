import Foundation

// MARK: - Packing

/// Identifies one HID input by its usage page and usage.
///
/// Usage numbers are scoped to their page. Keeping both values prevents a
/// controller-specific input from colliding with a standard Button-page input.
public struct HIDInputUsage: Hashable, Sendable {
  /// The usage page.
  public let page: Int
  /// The usage within the page.
  public let usage: Int

  /// Creates an identifier from a usage page and a usage.
  public init(page: Int, usage: Int) {
    self.page = page
    self.usage = usage
  }
}

/// The control value an axis field carries.
public enum HIDAxisRole: CaseIterable, Sendable {
  /// One of the six analog axes of the gamepad state.
  case leftStickX, leftStickY, rightStickX, rightStickY, leftTrigger, rightTrigger

  /// Generic Desktop usages: left stick on X/Y, right stick on Rx/Ry, triggers on Z/Rz.
  public static let standardUsages: [Self: HIDInputUsage] = [
    .leftStickX: HIDInputUsage(page: 0x01, usage: 0x30),
    .leftStickY: HIDInputUsage(page: 0x01, usage: 0x31),
    .leftTrigger: HIDInputUsage(page: 0x01, usage: 0x32),
    .rightStickX: HIDInputUsage(page: 0x01, usage: 0x33),
    .rightStickY: HIDInputUsage(page: 0x01, usage: 0x34),
    .rightTrigger: HIDInputUsage(page: 0x01, usage: 0x35),
  ]
}

/// Packs a gamepad state into the input report that a parsed descriptor declares.
struct HIDReportPacker: Sendable {
  /// The HID Button usage page.
  private static let buttonUsagePage = 0x09
  /// The HID Generic Desktop usage page.
  private static let genericDesktopUsagePage = 0x01
  /// The Button usages that count as gamepad buttons.
  private static let buttonUsageRange = 1...32
  /// The Generic Desktop usages of the axes X to Rz.
  private static let axisUsageRange = 0x30...0x35
  /// The Generic Desktop usage of the hat switch.
  private static let hatSwitchUsage = 0x39

  /// The report ID; 0 for an unnumbered report.
  let reportID: UInt8
  /// The payload size, without the report ID byte.
  let payloadSizeBytes: Int

  /// The input fields of the report by usage.
  let fields: [HIDInputUsage: HIDField]
  /// Maps normalized button bits to descriptor usages for profile-specific layouts.
  let buttonUsageMap: [Int: Int]
  /// Maps normalized button bits to usages outside the Button page; wins over `buttonUsageMap`.
  let digitalUsageMap: [Int: HIDInputUsage]
  /// Maps each axis role to the usage of the field that carries it.
  let axisUsageMap: [HIDAxisRole: HIDInputUsage]
  /// The hat switch field; nil when the report has none.
  let hatField: HIDField?

  /// Chooses the report with the most gamepad-like fields and builds a packer for it.
  ///
  /// The score counts buttons, axes, a hat switch and the payload size. Returns nil when the
  /// descriptor declares no input field.
  static func bestEffortGamepadPacker(
    from parsed: HIDParsedDescriptor,
    buttonUsageMap: [Int: Int] = [:],
    digitalUsageMap: [Int: HIDInputUsage] = [:],
    axisUsageMap: [HIDAxisRole: HIDInputUsage] = HIDAxisRole.standardUsages
  ) -> Self? {
    // Score each report ID by how many "gamepad-ish" fields it contains.
    let grouped = Dictionary(grouping: parsed.fields) { $0.reportID }
    var best: (UInt8, Int)?
    for (rid, reportFields) in grouped {
      let hasButtons = reportFields.contains {
        $0.usagePage == Self.buttonUsagePage && Self.buttonUsageRange.contains($0.usage)
      }
      let axisCount = reportFields.filter {
        $0.usagePage == Self.genericDesktopUsagePage && Self.axisUsageRange.contains($0.usage)
      }.count
      let hasHat = reportFields.contains {
        $0.usagePage == Self.genericDesktopUsagePage && $0.usage == Self.hatSwitchUsage
      }
      var score = 0
      if hasButtons { score += 10 }
      score += min(6, axisCount) * 3
      if hasHat { score += 5 }
      if let size = parsed.payloadSizeBytesByReportID[rid] { score += min(20, size) }
      if let currentBest = best {
        if score > currentBest.1 { best = (rid, score) }
      } else {
        best = (rid, score)
      }
    }
    guard let (rid, _) = best else { return nil }
    let chosenFields = grouped[rid] ?? []
    var fieldsByUsage: [HIDInputUsage: HIDField] = [:]
    var hat: HIDField?
    for f in chosenFields {
      fieldsByUsage[HIDInputUsage(page: f.usagePage, usage: f.usage)] = f
      if f.usagePage == Self.genericDesktopUsagePage, f.usage == Self.hatSwitchUsage {
        hat = f
      }
    }
    return Self(
      reportID: rid,
      payloadSizeBytes: parsed.payloadSizeBytesByReportID[rid] ?? 0,
      fields: fieldsByUsage,
      buttonUsageMap: buttonUsageMap,
      digitalUsageMap: digitalUsageMap,
      axisUsageMap: axisUsageMap,
      hatField: hat
    )
  }

  /// Packs `state` into an input report, with the report ID first when the report is numbered.
  func pack(state: VirtualGamepadState) -> [UInt8] {
    var payload = [UInt8](repeating: 0, count: max(0, payloadSizeBytes))

    func setBits(bitOffset: Int, bitSize: Int, value: UInt32) {
      // Little-endian bit numbering within the report.
      for bit in 0..<bitSize {
        let dstBit = bitOffset + bit
        let byteIndex = dstBit / 8
        let bitIndex = dstBit % 8
        if byteIndex < 0 || byteIndex >= payload.count { continue }
        let mask = UInt8(1 << bitIndex)
        if ((value >> bit) & 1) != 0 {
          payload[byteIndex] |= mask
        } else {
          payload[byteIndex] &= ~mask
        }
      }
    }

    func encodeAxis(_ v: Int16, field: HIDField, signed: Bool) -> UInt32 {
      let minV = field.logicalMin
      let maxV = field.logicalMax
      if signed, minV < 0 {
        let maxAbs = max(abs(minV), abs(maxV))
        let scaled = Int(Double(v) / 32767.0 * Double(maxAbs))
        let clamped = max(minV, min(maxV, scaled))
        return UInt32(bitPattern: Int32(clamped))
      }
      // Unsigned sticks: Int16 0 maps to the unsigned center. Xbox Series BLE
      // axes are 0...65535 with rest 0x8000 (SDL HIDAPI: raw - 0x8000).
      let unsigned = Int(v) - Int(Int16.min)
      let span = maxV - minV
      let scaled = span == 0 ? minV : minV + unsigned * span / 65_535
      let clamped = max(minV, min(maxV, scaled))
      return UInt32(clamped)
    }

    func encodeTrigger(_ v: Int16, field: HIDField) -> UInt32 {
      let minV = field.logicalMin
      let maxV = field.logicalMax
      let scaled = Int(Double(v) / 32767.0 * Double(maxV - minV) + Double(minV))
      let clamped = max(minV, min(maxV, scaled))
      return UInt32(clamped)
    }

    func encodeHat(_ hat: GamepadHIDDescriptor.Hat, field: HIDField) -> UInt32 {
      let minV = field.logicalMin
      let maxV = field.logicalMax
      let hasNull = field.flags.hasNullState
      if hat == .neutral {
        if hasNull {
          // Many hats use "8" as neutral for 0..7.
          if minV == 0, maxV == 7 { return UInt32(maxV + 1) }
          // Or "0" as neutral for 1..8 (below min).
          if minV == 1, maxV == 8 { return 0 }
        }
        return UInt32(minV)
      }
      // Map our 1..8 to either 0..7 or 1..8 depending on logical min.
      let idx = Int(hat.rawValue) - 1
      if minV == 0, maxV == 7 { return UInt32(idx) }
      if minV == 1, maxV == 8 { return UInt32(idx + 1) }
      // Fallback: clamp into range.
      return UInt32(max(minV, min(maxV, idx + minV)))
    }

    // Buttons use stable OJD normalized bits; profiles may map them to different
    // descriptor usages without changing the global normalized ordering.
    for bitIndex in 0..<32 {
      let usage =
        digitalUsageMap[bitIndex]
        ?? HIDInputUsage(
          page: Self.buttonUsagePage,
          usage: buttonUsageMap[bitIndex] ?? (bitIndex + 1)
        )
      guard let field = fields[usage] else { continue }
      let pressed = ((state.buttons >> bitIndex) & 1) != 0
      setBits(bitOffset: field.bitOffset, bitSize: field.bitSize, value: pressed ? 1 : 0)
    }

    for role in HIDAxisRole.allCases {
      guard let usage = axisUsageMap[role], let f = fields[usage] else { continue }
      let value: UInt32
      switch role {
      case .leftStickX: value = encodeAxis(state.leftStickX, field: f, signed: true)
      case .leftStickY: value = encodeAxis(state.leftStickY, field: f, signed: true)
      case .rightStickX: value = encodeAxis(state.rightStickX, field: f, signed: true)
      case .rightStickY: value = encodeAxis(state.rightStickY, field: f, signed: true)
      case .leftTrigger: value = encodeTrigger(state.effectiveLeftTrigger, field: f)
      case .rightTrigger: value = encodeTrigger(state.effectiveRightTrigger, field: f)
      }
      setBits(bitOffset: f.bitOffset, bitSize: f.bitSize, value: value)
    }

    if let f = hatField {
      setBits(bitOffset: f.bitOffset, bitSize: f.bitSize, value: encodeHat(state.hat, field: f))
    }

    if reportID != 0 { return [reportID] + payload }
    return payload
  }
}
