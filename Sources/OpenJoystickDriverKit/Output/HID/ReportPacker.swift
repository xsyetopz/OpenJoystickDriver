import Foundation

// MARK: - Packing

/// Identifies one HID input by its usage page and usage.
///
/// Usage numbers are scoped to their page. Keeping both values prevents a
/// controller-specific input from colliding with a standard Button-page input.
public struct HIDInputUsage: Hashable, Sendable {
  public let page: Int
  public let usage: Int

  public init(page: Int, usage: Int) {
    self.page = page
    self.usage = usage
  }
}

struct HIDReportPacker: @unchecked Sendable {
  private static let buttonUsagePage = 0x09
  private static let genericDesktopUsagePage = 0x01
  private static let buttonUsageRange = 1...32
  private static let axisUsageRange = 0x30...0x35
  private static let hatSwitchUsage = 0x39

  let reportID: UInt8
  let payloadSizeBytes: Int

  let digitalFields: [HIDInputUsage: HIDField]
  /// Maps normalized button bits to descriptor usages for profile-specific layouts.
  let buttonUsageMap: [Int: Int]
  /// Maps normalized button bits to inputs outside the standard Button page.
  let digitalUsageMap: [Int: HIDInputUsage]
  let axisFields: [Int: HIDField]  // usage -> field (Generic Desktop)
  let hatField: HIDField?

  enum Error: Swift.Error, Equatable, Sendable {
    case duplicateExplicitUsage(HIDInputUsage)
    case missingExplicitUsage(HIDInputUsage)
    case ambiguousExplicitUsage(HIDInputUsage)
    case explicitUsagesSpanReports
  }

  static func bestEffortGamepadPacker(
    from parsed: HIDParsedDescriptor,
    buttonUsageMap: [Int: Int] = [:],
    digitalUsageMap: [Int: HIDInputUsage] = [:]
  ) throws -> Self? {
    let explicitUsages = Array(digitalUsageMap.values)
    for (bitIndex, usage) in digitalUsageMap {
      let duplicatesAnotherButton = (0..<32).contains { otherBitIndex in
        guard otherBitIndex != bitIndex else { return false }
        let otherUsage =
          digitalUsageMap[otherBitIndex]
          ?? HIDInputUsage(
            page: Self.buttonUsagePage,
            usage: buttonUsageMap[otherBitIndex] ?? (otherBitIndex + 1)
          )
        return otherUsage == usage
      }
      if duplicatesAnotherButton { throw Error.duplicateExplicitUsage(usage) }
    }

    for usage in explicitUsages {
      let matches = parsed.fields.filter(usage.matches)
      if matches.isEmpty { throw Error.missingExplicitUsage(usage) }
      let matchesByReport = Dictionary(grouping: matches, by: \.reportID)
      if matchesByReport.count > 1 || matchesByReport.values.contains(where: { $0.count > 1 }) {
        throw Error.ambiguousExplicitUsage(usage)
      }
    }

    // Score each report ID by how many "gamepad-ish" fields it contains.
    let grouped = Dictionary(grouping: parsed.fields) { $0.reportID }
    var best: (UInt8, Int)?
    for (rid, fields) in grouped
    where explicitUsages.allSatisfy({ usage in fields.count(where: usage.matches) == 1 }) {
      let hasButtons = fields.contains {
        $0.usagePage == Self.buttonUsagePage && Self.buttonUsageRange.contains($0.usage)
      }
      let axisCount = fields.filter {
        $0.usagePage == Self.genericDesktopUsagePage && Self.axisUsageRange.contains($0.usage)
      }.count
      let hasHat = fields.contains {
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
    guard let (rid, _) = best else {
      if !explicitUsages.isEmpty { throw Error.explicitUsagesSpanReports }
      return nil
    }
    let fields = grouped[rid] ?? []
    var digitalFields: [HIDInputUsage: HIDField] = [:]
    var axes: [Int: HIDField] = [:]
    var hat: HIDField?
    for f in fields {
      let usage = HIDInputUsage(page: f.usagePage, usage: f.usage)
      digitalFields[usage] = f
      if f.usagePage == Self.genericDesktopUsagePage && Self.axisUsageRange.contains(f.usage) {
        axes[f.usage] = f
      } else if f.usagePage == Self.genericDesktopUsagePage && f.usage == Self.hatSwitchUsage {
        hat = f
      }
    }
    return Self(
      reportID: rid,
      payloadSizeBytes: parsed.payloadSizeBytesByReportID[rid] ?? 0,
      digitalFields: digitalFields,
      buttonUsageMap: buttonUsageMap,
      digitalUsageMap: digitalUsageMap,
      axisFields: axes,
      hatField: hat
    )
  }

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
      if signed && minV < 0 {
        let maxAbs = max(abs(minV), abs(maxV))
        let scaled = Int(Double(v) / 32767.0 * Double(maxAbs))
        let clamped = max(minV, min(maxV, scaled))
        return UInt32(bitPattern: Int32(clamped))
      }
      let scaled = Int((Double(v) + 32767.0) / 65534.0 * Double(maxV - minV) + Double(minV))
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
          if minV == 0 && maxV == 7 { return UInt32(maxV + 1) }
          // Or "0" as neutral for 1..8 (below min).
          if minV == 1 && maxV == 8 { return 0 }
        }
        return UInt32(minV)
      }
      // Map our 1..8 to either 0..7 or 1..8 depending on logical min.
      let idx = Int(hat.rawValue) - 1
      if minV == 0 && maxV == 7 { return UInt32(idx) }
      if minV == 1 && maxV == 8 { return UInt32(idx + 1) }
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
      guard let field = digitalFields[usage] else { continue }
      let pressed = ((state.buttons >> bitIndex) & 1) != 0
      setBits(bitOffset: field.bitOffset, bitSize: field.bitSize, value: pressed ? 1 : 0)
    }

    // Axes (Generic Desktop): X,Y,Z,Rx,Ry,Rz
    if let f = axisFields[0x30] {
      setBits(
        bitOffset: f.bitOffset,
        bitSize: f.bitSize,
        value: encodeAxis(state.leftStickX, field: f, signed: true)
      )
    }
    if let f = axisFields[0x31] {
      setBits(
        bitOffset: f.bitOffset,
        bitSize: f.bitSize,
        value: encodeAxis(state.leftStickY, field: f, signed: true)
      )
    }
    if let f = axisFields[0x32] {
      setBits(
        bitOffset: f.bitOffset,
        bitSize: f.bitSize,
        value: encodeTrigger(state.leftTrigger, field: f)
      )
    }
    if let f = axisFields[0x33] {
      setBits(
        bitOffset: f.bitOffset,
        bitSize: f.bitSize,
        value: encodeAxis(state.rightStickX, field: f, signed: true)
      )
    }
    if let f = axisFields[0x34] {
      setBits(
        bitOffset: f.bitOffset,
        bitSize: f.bitSize,
        value: encodeAxis(state.rightStickY, field: f, signed: true)
      )
    }
    if let f = axisFields[0x35] {
      setBits(
        bitOffset: f.bitOffset,
        bitSize: f.bitSize,
        value: encodeTrigger(state.rightTrigger, field: f)
      )
    }

    if let f = hatField {
      setBits(bitOffset: f.bitOffset, bitSize: f.bitSize, value: encodeHat(state.hat, field: f))
    }

    if reportID != 0 { return [reportID] + payload }
    return payload
  }
}

extension HIDInputUsage {
  func matches(_ field: HIDField) -> Bool { field.usagePage == page && field.usage == usage }
}
