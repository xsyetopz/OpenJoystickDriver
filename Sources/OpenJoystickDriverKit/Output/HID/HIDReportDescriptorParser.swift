import Foundation

// MARK: - HID report descriptor parsing (subset)

enum HIDItemType: UInt8 {
  case main = 0
  case global = 1
  case local = 2
  case reserved = 3
}

enum HIDGlobalTag: UInt8 {
  case usagePage = 0x0
  case logicalMinimum = 0x1
  case logicalMaximum = 0x2
  case reportSize = 0x7
  case reportID = 0x8
  case reportCount = 0x9
}

enum HIDLocalTag: UInt8 {
  case usage = 0x0
  case usageMinimum = 0x1
  case usageMaximum = 0x2
}

enum HIDMainTag: UInt8 {
  case input = 0x8
  case collection = 0xA
  case endCollection = 0xC
}

struct HIDInputFlags: Sendable {
  let isConstant: Bool
  let hasNullState: Bool

  init(_ raw: Int) {
    // HID Input flags are bitfields; we care only about:
    // - Constant (bit 0: 1 = Constant)
    // - Null State (bit 6: 1 = Null state)
    self.isConstant = (raw & 0x01) != 0
    self.hasNullState = (raw & 0x40) != 0
  }
}

struct HIDField: Sendable {
  let reportID: UInt8
  let bitOffset: Int
  let bitSize: Int
  let usagePage: Int
  let usage: Int
  let logicalMin: Int
  let logicalMax: Int
  let flags: HIDInputFlags
}

struct HIDParsedDescriptor: Sendable {
  /// All variable input fields across all report IDs.
  let fields: [HIDField]
  /// Payload size (excluding report ID byte) for each report ID.
  let payloadSizeBytesByReportID: [UInt8: Int]
}

enum HIDReportDescriptorParser {
  static func parse(descriptor: [UInt8]) -> HIDParsedDescriptor? {
    var i = 0

    var usagePage: Int = 0
    var logicalMin: Int = 0
    var logicalMax: Int = 0
    var reportSize: Int = 0
    var reportCount: Int = 0
    var reportID: UInt8 = 0

    var localUsages: [Int] = []
    var usageMin: Int?
    var usageMax: Int?

    var bitOffsetByReportID: [UInt8: Int] = [:]
    var fields: [HIDField] = []

    func readSigned(_ bytes: [UInt8]) -> Int {
      switch bytes.count {
      case 0: return 0
      case 1: return Int(Int8(bitPattern: bytes[0]))
      case 2:
        let v = UInt16(bytes[0]) | (UInt16(bytes[1]) << 8)
        return Int(Int16(bitPattern: v))
      case 4:
        let v = UInt32(bytes[0])
          | (UInt32(bytes[1]) << 8)
          | (UInt32(bytes[2]) << 16)
          | (UInt32(bytes[3]) << 24)
        return Int(Int32(bitPattern: v))
      default:
        return 0
      }
    }

    func readUnsigned(_ bytes: [UInt8]) -> Int {
      var v = 0
      for (idx, b) in bytes.enumerated() { v |= Int(b) << (8 * idx) }
      return v
    }

    func currentBitOffset() -> Int { bitOffsetByReportID[reportID] ?? 0 }
    func advanceBits(_ bits: Int) { bitOffsetByReportID[reportID] = currentBitOffset() + bits }

    while i < descriptor.count {
      let prefix = descriptor[i]
      i += 1

      if prefix == 0xFE {
        // Long item: [0xFE][size][tag][data...]
        guard i + 2 <= descriptor.count else { return nil }
        let size = Int(descriptor[i])
        i += 2  // skip size + tag
        i += size
        continue
      }

      let sizeCode = prefix & 0x03
      let dataSize: Int = (sizeCode == 0x03) ? 4 : Int(sizeCode)
      let type = HIDItemType(rawValue: (prefix >> 2) & 0x03) ?? .reserved
      let tag = (prefix >> 4) & 0x0F

      guard i + dataSize <= descriptor.count else { return nil }
      let data = Array(descriptor[i..<(i + dataSize)])
      i += dataSize

      switch type {
      case .global:
        guard let g = HIDGlobalTag(rawValue: tag) else { break }
        switch g {
        case .usagePage: usagePage = readUnsigned(data)
        case .logicalMinimum: logicalMin = readSigned(data)
        case .logicalMaximum: logicalMax = readSigned(data)
        case .reportSize: reportSize = readUnsigned(data)
        case .reportCount: reportCount = readUnsigned(data)
        case .reportID:
          reportID = UInt8(clamping: readUnsigned(data))
          if bitOffsetByReportID[reportID] == nil { bitOffsetByReportID[reportID] = 0 }
        }
      case .local:
        guard let l = HIDLocalTag(rawValue: tag) else { break }
        switch l {
        case .usage: localUsages.append(readUnsigned(data))
        case .usageMinimum: usageMin = readUnsigned(data)
        case .usageMaximum: usageMax = readUnsigned(data)
        }
      case .main:
        guard let m = HIDMainTag(rawValue: tag) else { break }
        switch m {
        case .input:
          let flags = HIDInputFlags(readUnsigned(data))
          let bitsTotal = reportSize * reportCount
          defer {
            // Main items consume the local state.
            localUsages.removeAll(keepingCapacity: true)
            usageMin = nil
            usageMax = nil
            advanceBits(bitsTotal)
          }
          if flags.isConstant { continue }
          guard reportSize > 0, reportCount > 0 else { continue }

          // Determine usage list for this Input item.
          var usages: [Int] = []
          if !localUsages.isEmpty {
            usages = localUsages
          } else if let min = usageMin, let max = usageMax, max >= min {
            usages = Array(min...max)
          }

          // Expand/trim to reportCount.
          if usages.count < reportCount {
            if let last = usages.last {
              usages += Array(repeating: last, count: reportCount - usages.count)
            } else {
              usages = Array(repeating: 0, count: reportCount)
            }
          } else if usages.count > reportCount {
            usages = Array(usages.prefix(reportCount))
          }

          let base = currentBitOffset()
          for idx in 0..<reportCount {
            fields.append(
              HIDField(
                reportID: reportID,
                bitOffset: base + (idx * reportSize),
                bitSize: reportSize,
                usagePage: usagePage,
                usage: usages[idx],
                logicalMin: logicalMin,
                logicalMax: logicalMax,
                flags: flags
              )
            )
          }
        case .collection, .endCollection:
          // Collection is a main item and consumes local usage state. If those usages
          // leak into the next Input item, Xbox One descriptors parse stick axes as
          // stale collection usages instead of X/Y/Rx/Ry.
          localUsages.removeAll(keepingCapacity: true)
          usageMin = nil
          usageMax = nil
        }
      case .reserved:
        break
      }
    }

    // Compute payload size per report ID.
    var payloadSize: [UInt8: Int] = [:]
    for (rid, bits) in bitOffsetByReportID {
      payloadSize[rid] = (bits + 7) / 8
    }
    return HIDParsedDescriptor(fields: fields, payloadSizeBytesByReportID: payloadSize)
  }
}
