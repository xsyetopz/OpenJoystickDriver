import Foundation

extension ControllerRecordDocument {
  /// A record's or description's `input` section, which is either report layouts or, for
  /// `HIDDescriptor`, a HID usage map.
  ///
  /// The keys decide which: `hidUsageMap` and `descriptorShapes` are usage-map keys, any other key
  /// belongs to the report layouts.
  struct Input: Decodable {
    /// The report layouts of the section; nil when it holds usage-map keys.
    let layouts: ControllerInputLayouts?
    /// The HID usage map; nil when the section has none.
    let usageMap: HIDUsageMap?
    /// The descriptor shapes that select the usage map; empty when the section has none.
    let shapes: [HIDUsageShape]

    /// Decodes either report layouts or the keys `hidUsageMap` and `descriptorShapes`; unknown
    /// usage-map keys, an empty section and an empty `descriptorShapes` are rejected.
    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: DocumentKey.self)
      let usageKeys: Set<String> = ["hidUsageMap", "descriptorShapes"]
      if Set(container.allKeys.map(\.stringValue)).isDisjoint(with: usageKeys) {
        layouts = try InputLayouts(from: decoder).layouts
        usageMap = nil
        shapes = []
        return
      }
      try container.rejectUnknown(allowed: usageKeys)
      guard !container.allKeys.isEmpty else {
        throw DecodingError.dataCorrupted(
          .init(codingPath: decoder.codingPath, debugDescription: "input must not be empty")
        )
      }
      layouts = nil
      usageMap = try container.decodeOptional(UsageMap.self, for: "hidUsageMap")?.map
      shapes =
        try container.decodeOptional([UsageShape].self, for: "descriptorShapes")?
        .map(\.shape) ?? []
      guard container.contains(DocumentKey("descriptorShapes")) == !shapes.isEmpty else {
        throw DecodingError.dataCorrupted(
          .init(
            codingPath: decoder.codingPath + [DocumentKey("descriptorShapes")],
            debugDescription: "descriptorShapes must not be empty"
          )
        )
      }
    }
  }

  /// A HID usage map with an optional report ID and its usage entries.
  struct UsageMap: Decodable {
    /// The decoded usage map.
    let map: HIDUsageMap

    /// Decodes `reportID` (1...255) and `usages`; an unknown key or a map that `HIDUsageMap`
    /// rejects is rejected.
    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: DocumentKey.self)
      try container.rejectUnknown(allowed: ["reportID", "usages"])
      let reportID = try container.decodeOptional(Int.self, for: "reportID")
      guard reportID.map({ (1...255).contains($0) }) ?? true else {
        throw DecodingError.dataCorrupted(
          .init(
            codingPath: decoder.codingPath + [DocumentKey("reportID")],
            debugDescription: "reportID must be 1...255"
          )
        )
      }
      let usages = try container.decode([UsageEntry].self, for: "usages")
      do {
        map = try HIDUsageMap(reportID: reportID.map(UInt32.init), entries: usages.map(\.entry))
      } catch let problem as ControllerRecordProblem {
        throw DecodingError.dataCorrupted(
          .init(codingPath: decoder.codingPath, debugDescription: problem.description)
        )
      }
    }
  }

  /// A HID usage named by its page and usage number.
  struct UsageRef: Decodable {
    /// The decoded usage.
    let usage: HIDUsage

    /// Decodes `page` and `usage`; any other key is rejected.
    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: DocumentKey.self)
      try container.rejectUnknown(allowed: ["page", "usage"])
      usage = try UsageEntry.usage(in: container, codingPath: decoder.codingPath)
    }
  }

  /// One entry of a usage map: a usage and the control binding it drives.
  struct UsageEntry: Decodable {
    /// The decoded entry.
    let entry: HIDUsageMap.Entry

    /// Decodes a `Button`, `Axis`, `Hat`, `HalfAxis`, `AxisDpad`, `AxisButton` or `ButtonTrigger`
    /// entry with the keys that kind allows; any other kind or
    /// key is rejected.
    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: DocumentKey.self)
      let kind = try container.decode(String.self, for: "kind")
      let usage = try Self.usage(in: container, codingPath: decoder.codingPath)
      let binding: HIDUsageMap.Binding
      switch kind {
      case "Button":
        try container.rejectUnknown(allowed: ["kind", "page", "usage", "control"])
        binding = .button(try container.decode(Control.self, for: "control"))
      case "Axis":
        let control = try container.decode(Control.self, for: "control")
        try container.rejectUnknown(allowed: [
          "kind", "page", "usage", "control", "inverted", "range", "deadZone",
        ])
        let deadZone = try container.decodeOptional(Double.self, for: "deadZone")
        binding = .axis(
          HIDUsageMap.Axis(
            control: control,
            isInverted: try container.decodeOptional(Bool.self, for: "inverted") ?? false,
            range: try container.decodeOptional(UsageRange.self, for: "range")?.range,
            deadZone: deadZone.map(Float.init)
          )
        )
      case "Hat":
        try container.rejectUnknown(allowed: ["kind", "page", "usage", "range"])
        binding = .hat(
          HIDUsageMap.Hat(range: try container.decodeOptional(UsageRange.self, for: "range")?.range)
        )
      case "HalfAxis":
        try container.rejectUnknown(allowed: [
          "kind", "page", "usage", "half", "control", "inverted",
        ])
        binding = .halfAxis(
          HIDUsageMap.HalfAxis(
            half: try Self.half(in: container),
            control: try container.decode(Control.self, for: "control"),
            isInverted: try container.decodeOptional(Bool.self, for: "inverted") ?? false
          )
        )
      case "AxisDpad", "AxisButton":
        try container.rejectUnknown(allowed: [
          "kind", "page", "usage", "half", "control", "threshold",
        ])
        let half = HIDUsageMap.HalfThreshold(
          half: try Self.half(in: container),
          control: try container.decode(Control.self, for: "control"),
          threshold: Float(try container.decode(Double.self, for: "threshold"))
        )
        binding = kind == "AxisDpad" ? .axisDpad(half) : .axisButton(half)
      case "ButtonTrigger":
        try container.rejectUnknown(allowed: ["kind", "page", "usage", "control"])
        binding = .buttonTrigger(try container.decode(Control.self, for: "control"))
      default:
        throw DecodingError.dataCorrupted(
          .init(
            codingPath: decoder.codingPath + [DocumentKey("kind")],
            debugDescription:
              "kind is Button, Axis, Hat, HalfAxis, AxisDpad, AxisButton or ButtonTrigger"
          )
        )
      }
      entry = HIDUsageMap.Entry(usage: usage, binding: binding)
    }

    /// Reads `half`, which is `Positive` or `Negative`.
    private static func half(
      in container: KeyedDecodingContainer<DocumentKey>
    ) throws -> HIDUsageMap.Half {
      let name = try container.decode(String.self, for: "half")
      guard let half = HIDUsageMap.Half(rawValue: name) else {
        throw DecodingError.dataCorrupted(
          .init(
            codingPath: container.codingPath + [DocumentKey("half")],
            debugDescription: "half is Positive or Negative"
          )
        )
      }
      return half
    }

    /// Reads `page` (1...65535) and `usage` (0...65535) from a container that may hold other keys.
    static func usage(
      in container: KeyedDecodingContainer<DocumentKey>,
      codingPath: [any CodingKey]
    ) throws -> HIDUsage {
      let page = try container.decode(Int.self, for: "page")
      let usage = try container.decode(Int.self, for: "usage")
      guard (1...65_535).contains(page), (0...65_535).contains(usage) else {
        throw DecodingError.dataCorrupted(
          .init(codingPath: codingPath, debugDescription: "page is 1...65535 and usage 0...65535")
        )
      }
      return HIDUsage(usagePage: page, usage: usage)
    }
  }

  /// An inclusive range of raw usage values.
  struct UsageRange: Decodable {
    /// The decoded range.
    let range: ClosedRange<Int>

    /// Decodes `min` and `max`, which must be 32-bit integers with `min` at most `max`.
    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: DocumentKey.self)
      try container.rejectUnknown(allowed: ["min", "max"])
      let low = try container.decode(Int.self, for: "min")
      let high = try container.decode(Int.self, for: "max")
      guard Int(Int32.min)...Int(Int32.max) ~= low, Int(Int32.min)...Int(Int32.max) ~= high,
        low <= high
      else {
        throw DecodingError.dataCorrupted(
          .init(
            codingPath: decoder.codingPath,
            debugDescription: "min and max are 32-bit integers with min at most max"
          )
        )
      }
      range = low...high
    }
  }

  /// A descriptor shape: the usages that select a usage map, and the map.
  struct UsageShape: Decodable {
    /// The decoded shape.
    let shape: HIDUsageShape

    /// Decodes `present` (required), `absent`, `anyOf` and `hidUsageMap`; a usage list must be
    /// nonempty and unique.
    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: DocumentKey.self)
      try container.rejectUnknown(allowed: ["present", "absent", "anyOf", "hidUsageMap"])
      func usages(_ key: String) throws -> Set<HIDUsage> {
        guard let refs = try container.decodeOptional([UsageRef].self, for: key) else { return [] }
        let set = Set(refs.map(\.usage))
        guard !refs.isEmpty, set.count == refs.count else {
          throw DecodingError.dataCorrupted(
            .init(
              codingPath: decoder.codingPath + [DocumentKey(key)],
              debugDescription: "\(key) must be nonempty and unique"
            )
          )
        }
        return set
      }
      shape = HIDUsageShape(
        present: try usages("present"),
        absent: try usages("absent"),
        anyOf: try usages("anyOf"),
        map: try container.decode(UsageMap.self, for: "hidUsageMap").map
      )
      guard !shape.present.isEmpty else {
        throw DecodingError.dataCorrupted(
          .init(codingPath: decoder.codingPath, debugDescription: "present is required")
        )
      }
    }
  }
}
