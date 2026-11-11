import Foundation

// MARK: - HID report descriptor parsing (subset)

/// The type of a short HID item.
enum HIDItemType: UInt8 {
  /// A Main item.
  case main = 0
  /// A Global item.
  case global = 1
  /// A Local item.
  case local = 2
  /// The reserved type.
  case reserved = 3
}

/// The tags of the Global items that the parser reads.
enum HIDGlobalTag: UInt8 {
  /// Usage Page.
  case usagePage = 0x0
  /// Logical Minimum.
  case logicalMinimum = 0x1
  /// Logical Maximum.
  case logicalMaximum = 0x2
  /// Report Size.
  case reportSize = 0x7
  /// Report ID.
  case reportID = 0x8
  /// Report Count.
  case reportCount = 0x9
  /// Push.
  case push = 0xA
  /// Pop.
  case pop = 0xB
}

/// The tags of the Local items that the parser reads.
enum HIDLocalTag: UInt8 {
  /// Usage.
  case usage = 0x0
  /// Usage Minimum.
  case usageMinimum = 0x1
  /// Usage Maximum.
  case usageMaximum = 0x2
}

/// The tags of the Main items that the parser reads.
enum HIDMainTag: UInt8 {
  /// Input.
  case input = 0x8
  /// Output.
  case output = 0x9
  /// Collection.
  case collection = 0xA
  /// Feature.
  case feature = 0xB
  /// End Collection.
  case endCollection = 0xC
}

/// The flags of an Input item.
struct HIDInputFlags: Sendable {
  /// Whether the item is constant padding.
  let isConstant: Bool
  /// Variable (bit 1 set) or Array (bit 1 clear).
  let isVariable: Bool
  /// Whether the item is relative.
  let isRelative: Bool
  /// Whether the item has a null state.
  let hasNullState: Bool

  /// Creates the flags from the data bits of the item.
  init(_ raw: Int) {
    self.isConstant = (raw & 0x01) != 0
    self.isVariable = (raw & 0x02) != 0
    self.isRelative = (raw & 0x04) != 0
    self.hasNullState = (raw & 0x40) != 0
  }
}

/// One Variable input control with an explicitly declared usage.
struct HIDField: Sendable {
  /// The report ID of the field; 0 for an unnumbered report.
  let reportID: UInt8
  /// The offset of the field's first bit in the report payload.
  let bitOffset: Int
  /// The size of the field in bits.
  let bitSize: Int
  /// The usage page of the field.
  let usagePage: Int
  /// The usage of the field.
  let usage: Int
  /// The lowest value the field reports.
  let logicalMin: Int
  /// The highest value the field reports.
  let logicalMax: Int
  /// The flags of the Input item.
  let flags: HIDInputFlags
  /// Index into `HIDParsedDescriptor.applicationCollections` of the enclosing
  /// top-level Application collection; nil outside one.
  let applicationCollection: Int?
}

/// One Array input item: `count` selectors, each reporting one of `usages` or none.
struct HIDArrayField: Sendable {
  /// The report ID of the item; 0 for an unnumbered report.
  let reportID: UInt8
  /// The number of selectors.
  let count: Int
  /// The usages that a selector can report.
  let usages: [HIDUsage]
  /// The flags of the Input item.
  let flags: HIDInputFlags
  /// The index of the enclosing top-level Application collection; nil outside one.
  let applicationCollection: Int?
}

/// A usage with its page.
struct HIDUsage: Hashable, Sendable {
  /// The usage page.
  let usagePage: Int
  /// The usage within the page.
  let usage: Int
}

/// The input controls and report sizes that a descriptor declares.
struct HIDParsedDescriptor: Sendable {
  /// Non-constant Variable input controls across all report IDs.
  ///
  /// Controls beyond an item's explicit usage list are unused padding and have no field.
  let fields: [HIDField]
  /// Non-constant Array input items across all report IDs.
  let arrays: [HIDArrayField]
  /// Input payload size (excluding the report ID byte) for each report ID.
  let payloadSizeBytesByReportID: [UInt8: Int]
  /// Usages of top-level Application collections, in descriptor order.
  ///
  /// A collection without a usage records usage 0.
  let applicationCollections: [HIDUsage]
  /// Report IDs of every Input item, constant or not; `0` means unnumbered.
  let inputReportIDs: Set<UInt8>
  /// Whether a long, Push, Pop, Delimiter, or reserved item, or a usage range that spans pages or
  /// runs backwards, appeared.
  ///
  /// This subset parser does not model those, so its fields are incomplete when this is true.
  let containsUnsupportedItem: Bool
  /// Whether an Input item had a zero Report Size or Count, or a Report Size above 32 bits.
  let containsInvalidInputSize: Bool
  /// Whether any Feature main item appeared, so the device has at least one feature report.
  let containsFeatureItem: Bool
}

/// Parses the input items of a HID report descriptor, a subset of the format.
enum HIDReportDescriptorParser {
  /// Parses `descriptor` into its input fields and report sizes.
  ///
  /// Returns nil for a truncated item or unbalanced collections.
  static func parse(descriptor: [UInt8]) -> HIDParsedDescriptor? {
    var i = 0

    var usagePage: Int = 0
    var logicalMin: Int = 0
    var logicalMax: Int = 0
    var reportSize: Int = 0
    var reportCount: Int = 0
    var reportID: UInt8 = 0

    // A 4-byte usage carries its own page in the high 16 bits (extended usage);
    // otherwise the Usage Page current at the Main item applies.
    var localUsages: [(page: Int?, usage: Int)] = []
    var usageMin: (page: Int?, usage: Int)?
    var usageMax: (page: Int?, usage: Int)?

    var bitOffsetByReportID: [UInt8: Int] = [:]
    var fields: [HIDField] = []
    var arrays: [HIDArrayField] = []
    var applicationCollections: [HIDUsage] = []
    var inputReportIDs: Set<UInt8> = []
    var containsUnsupportedItem = false
    var containsInvalidInputSize = false
    var containsFeatureItem = false
    var collectionDepth = 0
    var application: Int?

    func readSigned(_ bytes: [UInt8]) -> Int {
      switch bytes.count {
      case 0: return 0
      case 1: return Int(Int8(bitPattern: bytes[0]))
      case 2:
        let v = UInt16(bytes[0]) | (UInt16(bytes[1]) << 8)
        return Int(Int16(bitPattern: v))
      case 4:
        let v =
          UInt32(bytes[0]) | (UInt32(bytes[1]) << 8) | (UInt32(bytes[2]) << 16)
          | (UInt32(bytes[3]) << 24)
        return Int(Int32(bitPattern: v))
      default: return 0
      }
    }

    func readUnsigned(_ bytes: [UInt8]) -> Int {
      var v = 0
      for (idx, b) in bytes.enumerated() { v |= Int(b) << (8 * idx) }
      return v
    }

    func readUsage(_ bytes: [UInt8]) -> (page: Int?, usage: Int) {
      let value = readUnsigned(bytes)
      return bytes.count == 4 ? (value >> 16, value & 0xFFFF) : (nil, value)
    }

    func resolve(_ local: (page: Int?, usage: Int)) -> HIDUsage {
      HIDUsage(usagePage: local.page ?? usagePage, usage: local.usage)
    }

    // The explicit usage list, or the usage range when no list was declared.
    func declaredUsages() -> [HIDUsage]? {
      guard localUsages.isEmpty, let usageMin, let usageMax else { return localUsages.map(resolve) }
      let first = resolve(usageMin)
      let last = resolve(usageMax)
      guard first.usagePage == last.usagePage, first.usage <= last.usage else { return nil }
      return (first.usage...last.usage).map { HIDUsage(usagePage: first.usagePage, usage: $0) }
    }

    func currentBitOffset() -> Int { bitOffsetByReportID[reportID] ?? 0 }
    func advanceBits(_ bits: Int) { bitOffsetByReportID[reportID] = currentBitOffset() + bits }

    while i < descriptor.count {
      let prefix = descriptor[i]
      i += 1

      // Xbox One S Bluetooth descriptors end with a zero byte after the last End Collection;
      // Linux ignores it as an unknown main item.
      if prefix == 0, collectionDepth == 0, descriptor[i...].allSatisfy({ $0 == 0 }) { break }

      if prefix == 0xFE {
        // Long item: [0xFE][size][tag][data...]
        guard i + 2 <= descriptor.count else { return nil }
        let size = Int(descriptor[i])
        guard i + 2 + size <= descriptor.count else { return nil }
        i += 2  // skip size + tag
        i += size
        containsUnsupportedItem = true
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
        guard let g = HIDGlobalTag(rawValue: tag) else {
          // Tags 0x3...0x6 (physical extent, unit exponent, unit) are legal but unused.
          if tag > HIDGlobalTag.pop.rawValue { containsUnsupportedItem = true }
          break
        }
        switch g {
        case .usagePage: usagePage = readUnsigned(data)
        case .logicalMinimum: logicalMin = readSigned(data)
        case .logicalMaximum: logicalMax = readSigned(data)
        case .reportSize: reportSize = readUnsigned(data)
        case .reportCount: reportCount = readUnsigned(data)
        case .reportID:
          reportID = UInt8(clamping: readUnsigned(data))
          if bitOffsetByReportID[reportID] == nil { bitOffsetByReportID[reportID] = 0 }
        case .push, .pop: containsUnsupportedItem = true
        }
      case .local:
        guard let l = HIDLocalTag(rawValue: tag) else {
          // Designator and string tags only name physical parts; Delimiter (0xA)
          // defines alternate usages and 0x6 is reserved.
          if !Self.ignoredLocalTags.contains(tag) { containsUnsupportedItem = true }
          break
        }
        switch l {
        case .usage: localUsages.append(readUsage(data))
        case .usageMinimum: usageMin = readUsage(data)
        case .usageMaximum: usageMax = readUsage(data)
        }
      case .main:
        switch HIDMainTag(rawValue: tag) {
        case .input:
          let flags = HIDInputFlags(readUnsigned(data))
          inputReportIDs.insert(reportID)
          if reportSize == 0 || reportCount == 0 || reportSize > Self.maximumFieldBits {
            containsInvalidInputSize = true
          }
          let base = currentBitOffset()
          advanceBits(reportSize * reportCount)
          guard !flags.isConstant, reportSize > 0, reportCount > 0 else { break }
          guard let usages = declaredUsages() else {
            containsUnsupportedItem = true
            break
          }
          guard flags.isVariable else {
            arrays.append(
              HIDArrayField(
                reportID: reportID,
                count: reportCount,
                usages: usages,
                flags: flags,
                applicationCollection: application
              )
            )
            break
          }
          for (idx, usage) in usages.prefix(reportCount).enumerated() {
            fields.append(
              HIDField(
                reportID: reportID,
                bitOffset: base + (idx * reportSize),
                bitSize: reportSize,
                usagePage: usage.usagePage,
                usage: usage.usage,
                logicalMin: logicalMin,
                logicalMax: logicalMax,
                flags: flags,
                applicationCollection: application
              )
            )
          }
        case .collection:
          if collectionDepth == 0 {
            application = nil
            if readUnsigned(data) == Self.applicationCollection {
              applicationCollections.append(
                localUsages.first.map(resolve) ?? HIDUsage(usagePage: usagePage, usage: 0)
              )
              application = applicationCollections.count - 1
            }
          }
          collectionDepth += 1
        case .endCollection:
          guard collectionDepth > 0 else { return nil }
          collectionDepth -= 1
          if collectionDepth == 0 { application = nil }
        case .output: break
        case .feature: containsFeatureItem = true
        case nil: containsUnsupportedItem = true
        }
        // Every main item consumes local usage state. If those usages leak into
        // the next Input item, Xbox One descriptors parse stick axes as stale
        // collection usages instead of X/Y/Rx/Ry.
        localUsages.removeAll(keepingCapacity: true)
        usageMin = nil
        usageMax = nil
      case .reserved: containsUnsupportedItem = true
      }
    }
    guard collectionDepth == 0 else { return nil }

    // Compute payload size per report ID.
    var payloadSize: [UInt8: Int] = [:]
    for (rid, bits) in bitOffsetByReportID { payloadSize[rid] = (bits + 7) / 8 }
    return HIDParsedDescriptor(
      fields: fields,
      arrays: arrays,
      payloadSizeBytesByReportID: payloadSize,
      applicationCollections: applicationCollections,
      inputReportIDs: inputReportIDs,
      containsUnsupportedItem: containsUnsupportedItem,
      containsInvalidInputSize: containsInvalidInputSize,
      containsFeatureItem: containsFeatureItem
    )
  }

  /// Designator Index/Minimum/Maximum and String Index/Minimum/Maximum.
  private static let ignoredLocalTags: Set<UInt8> = [0x3, 0x4, 0x5, 0x7, 0x8, 0x9]
  /// The data value of an Application collection.
  private static let applicationCollection = 0x01
  /// The widest input field that the parser accepts, in bits.
  private static let maximumFieldBits = 32
}
