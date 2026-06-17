import Foundation

// MARK: - Packing

struct HIDReportPacker: @unchecked Sendable {
  let reportID: UInt8
  let payloadSizeBytes: Int

  let buttonFields: [Int: HIDField]  // usage -> field
  let axisFields: [Int: HIDField]  // usage -> field (Generic Desktop)
  let hatField: HIDField?

  static func bestEffortGamepadPacker(from parsed: HIDParsedDescriptor) -> Self? {
    // Score each report ID by how many "gamepad-ish" fields it contains.
    let grouped = Dictionary(grouping: parsed.fields) { $0.reportID }
    var best: (UInt8, Int)?
    for (rid, fields) in grouped {
      let hasButtons = fields.contains { $0.usagePage == 0x09 && (1...32).contains($0.usage) }
      let axisCount = fields.filter { $0.usagePage == 0x01 && (0x30...0x35).contains($0.usage) }
        .count
      let hasHat = fields.contains { $0.usagePage == 0x01 && $0.usage == 0x39 }
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
    let fields = grouped[rid] ?? []
    var buttons: [Int: HIDField] = [:]
    var axes: [Int: HIDField] = [:]
    var hat: HIDField?
    for f in fields {
      if f.usagePage == 0x09 {
        buttons[f.usage] = f
      } else if f.usagePage == 0x01 && (0x30...0x35).contains(f.usage) {
        axes[f.usage] = f
      } else if f.usagePage == 0x01 && f.usage == 0x39 {
        hat = f
      }
    }
    return Self(
      reportID: rid,
      payloadSizeBytes: parsed.payloadSizeBytesByReportID[rid] ?? 0,
      buttonFields: buttons,
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

    // Buttons: normalized state bit 0 is HID Button usage 1, bit 1 is usage 2, etc.
    for usage in 1...32 {
      guard let field = buttonFields[usage] else { continue }
      let bitIndex = usage - 1
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
