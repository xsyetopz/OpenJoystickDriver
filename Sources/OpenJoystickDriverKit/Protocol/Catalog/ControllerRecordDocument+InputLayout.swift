import Foundation

extension ControllerRecordDocument {
  /// The record's `input` section: the fixed report layouts for the `HIDReportLayout` family.
  struct InputLayouts: Decodable {
    /// The decoded layouts.
    let layouts: ControllerInputLayouts

    /// Decodes `layouts`, a nonempty list of layouts with distinct report selectors; an unknown
    /// key, an empty list, or overlapping selectors are rejected.
    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: DocumentKey.self)
      try container.rejectUnknown(allowed: ["layouts"])
      do {
        layouts = try ControllerInputLayouts(
          layouts: try container.decode([InputLayout].self, for: "layouts").map(\.layout)
        )
      } catch let problem as ControllerRecordProblem {
        throw DecodingError.dataCorrupted(problem.context(at: decoder.codingPath))
      }
    }
  }

  /// One layout of the `input` section and the reports it selects.
  struct InputLayout: Decodable {
    /// The decoded layout.
    let layout: ControllerInputLayout

    /// Decodes `report` and the optional `buttons`, `axes`, `hat`, `leftTrigger` and
    /// `rightTrigger`; an unknown key, an empty list, or a layout that `ControllerInputLayout`
    /// rejects is rejected.
    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: DocumentKey.self)
      try container.rejectUnknown(allowed: [
        "report", "buttons", "axes", "hat", "leftTrigger", "rightTrigger",
      ])
      let report = try container.decode(InputReport.self, for: "report")
      let buttons = try container.decodeOptional([InputButton].self, for: "buttons")
      let axes = try container.decodeOptional([InputAxis].self, for: "axes")
      let hat = try container.decodeOptional([InputHatSource].self, for: "hat")
      guard buttons?.isEmpty != true, axes?.isEmpty != true, hat?.isEmpty != true else {
        throw DecodingError.dataCorrupted(
          .init(codingPath: decoder.codingPath, debugDescription: "input lists must be nonempty")
        )
      }
      do {
        layout = try ControllerInputLayout(
          reportID: report.reportID,
          minimumLength: report.length,
          requiresExactLength: report.requiresExactLength,
          buttons: buttons?.map { ($0.control, $0.field) } ?? [],
          axes: axes?.map(\.axis) ?? [],
          hat: hat?.map(\.source) ?? [],
          leftTrigger: try container.decodeOptional(InputTrigger.self, for: "leftTrigger")?.trigger,
          rightTrigger: try container.decodeOptional(InputTrigger.self, for: "rightTrigger")?
            .trigger
        )
      } catch let problem as ControllerRecordProblem {
        throw DecodingError.dataCorrupted(problem.context(at: decoder.codingPath))
      }
    }
  }

  /// An input report's `length`: exactly one of `atLeast` and `exactly`.
  struct LengthRule: Decodable {
    /// The report length in bytes.
    let length: Int
    /// Whether the report must have exactly `length` bytes.
    let isExact: Bool

    /// Decodes exactly one of `atLeast` and `exactly`; any other key, or both or neither, is
    /// rejected.
    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: DocumentKey.self)
      try container.rejectUnknown(allowed: ["atLeast", "exactly"])
      let atLeast = try container.decodeOptional(Int.self, for: "atLeast")
      let exactly = try container.decodeOptional(Int.self, for: "exactly")
      switch (atLeast, exactly) {
      case (let value?, nil):
        length = value
        isExact = false
      case (nil, let value?):
        length = value
        isExact = true
      default:
        throw DecodingError.dataCorrupted(
          .init(
            codingPath: decoder.codingPath,
            debugDescription: "length names exactly one of atLeast and exactly"
          )
        )
      }
    }
  }

  /// An input report's `id` and `length`.
  struct InputReport: Decodable {
    /// The report ID; nil for a report without one.
    let reportID: UInt8?
    /// The report length in bytes.
    let length: Int
    /// Whether the report must have exactly `length` bytes.
    let requiresExactLength: Bool

    /// Decodes `length` and an optional `id` of 1...255; any other key or an ID of 0 is rejected.
    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: DocumentKey.self)
      try container.rejectUnknown(allowed: ["id", "length"])
      let rule = try container.decode(LengthRule.self, for: "length")
      length = rule.length
      requiresExactLength = rule.isExact
      guard let id = try container.decodeOptional(Int.self, for: "id") else {
        reportID = nil
        return
      }
      guard let validID = UInt8(exactly: id), validID != 0 else {
        throw DecodingError.dataCorrupted(
          .init(codingPath: decoder.codingPath, debugDescription: "id must be 1...255")
        )
      }
      self.reportID = validID
    }
  }

  /// A bit field named by its `bitOffset` and `bitSize`.
  struct InputField: Decodable {
    /// The decoded bit field.
    let field: ReportBitField

    /// Decodes `bitOffset` and `bitSize`; any other key is rejected.
    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: DocumentKey.self)
      try container.rejectUnknown(allowed: ["bitOffset", "bitSize"])
      field = try Self.field(in: container, codingPath: decoder.codingPath)
    }

    /// Reads `bitOffset` and `bitSize` from a container that may hold other keys.
    static func field(
      in container: KeyedDecodingContainer<DocumentKey>,
      codingPath: [any CodingKey]
    ) throws -> ReportBitField {
      let bitOffset = try container.decode(Int.self, for: "bitOffset")
      let bitSize = try container.decode(Int.self, for: "bitSize")
      guard bitOffset >= 0, (1...ReportBitField.maximumBitSize).contains(bitSize) else {
        throw DecodingError.dataCorrupted(
          .init(
            codingPath: codingPath,
            debugDescription:
              "bitOffset is 0 or more and bitSize is 1...\(ReportBitField.maximumBitSize)"
          )
        )
      }
      return ReportBitField(bitOffset: bitOffset, bitSize: bitSize)
    }

    /// Reads a numeric field from a container that may hold other keys: `bitOffset` and
    /// `bitSize`, with optional `byteOrder`, `signed`, `min` and `max`; `min` and `max` default to
    /// the full range of the size.
    static func valueField(
      in container: KeyedDecodingContainer<DocumentKey>,
      codingPath: [any CodingKey]
    ) throws -> ReportValueField {
      let bits = try field(in: container, codingPath: codingPath)
      let byteOrder: ReportByteOrder
      if let name = try container.decodeOptional(String.self, for: "byteOrder") {
        guard let order = ReportByteOrder(rawValue: name) else {
          throw DecodingError.dataCorrupted(
            .init(
              codingPath: codingPath,
              debugDescription: "byteOrder is LittleEndian or BigEndian"
            )
          )
        }
        byteOrder = order
      } else {
        byteOrder = .littleEndian
      }
      let isSigned = try container.decodeOptional(Bool.self, for: "signed") ?? false
      let range = ReportValueField.fullRange(bitSize: bits.bitSize, isSigned: isSigned)
      return ReportValueField(
        bitOffset: bits.bitOffset,
        bitSize: bits.bitSize,
        byteOrder: byteOrder,
        isSigned: isSigned,
        minimum: try container.decodeOptional(Int.self, for: "min") ?? range.lowerBound,
        maximum: try container.decodeOptional(Int.self, for: "max") ?? range.upperBound
      )
    }
  }

  /// A digital control and the bit field that presses it.
  struct InputButton: Decodable {
    /// The control the field presses.
    let control: Control
    /// The bit field that presses the control.
    let field: ReportBitField

    /// Decodes `control`, `bitOffset` and `bitSize`; any other key is rejected.
    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: DocumentKey.self)
      try container.rejectUnknown(allowed: ["control", "bitOffset", "bitSize"])
      control = try container.decode(Control.self, for: "control")
      field = try InputField.field(in: container, codingPath: decoder.codingPath)
    }
  }

  /// A stick axis entry.
  struct InputAxis: Decodable {
    /// The decoded axis.
    let axis: ControllerInputLayout.Axis

    /// Decodes `control`, `bitOffset` and `bitSize`, with optional `byteOrder`, `signed`, `min`,
    /// `max`, `inverted` and `symmetric`; `min` and `max` default to the full range of the size.
    ///
    /// An unknown key is rejected.
    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: DocumentKey.self)
      try container.rejectUnknown(allowed: [
        "control", "bitOffset", "bitSize", "byteOrder", "signed", "min", "max", "inverted",
        "symmetric",
      ])
      axis = ControllerInputLayout.Axis(
        control: try container.decode(Control.self, for: "control"),
        field: try InputField.valueField(in: container, codingPath: decoder.codingPath),
        isInverted: try container.decodeOptional(Bool.self, for: "inverted") ?? false,
        isSymmetric: try container.decodeOptional(Bool.self, for: "symmetric") ?? false
      )
    }
  }

  /// One source of the hat.
  struct InputHatSource: Decodable {
    /// The decoded source.
    let source: ControllerInputLayout.HatSource

    /// Decodes an `EightWay`, `Directions` or `Table` hat source with the keys that encoding
    /// allows; any other encoding or key is rejected.
    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: DocumentKey.self)
      let encoding = try container.decode(String.self, for: "encoding")
      switch encoding {
      case "EightWay":
        try container.rejectUnknown(allowed: [
          "encoding", "bitOffset", "bitSize", "neutralUntilNonzero",
        ])
        source = .eightWay(
          try InputField.field(in: container, codingPath: decoder.codingPath),
          neutralUntilNonzero: try container.decodeOptional(Bool.self, for: "neutralUntilNonzero")
            ?? false
        )
      case "Directions":
        try container.rejectUnknown(allowed: ["encoding", "up", "right", "down", "left"])
        source = .directions(
          up: try container.decode(InputField.self, for: "up").field,
          right: try container.decode(InputField.self, for: "right").field,
          down: try container.decode(InputField.self, for: "down").field,
          left: try container.decode(InputField.self, for: "left").field
        )
      case "Table":
        try container.rejectUnknown(allowed: ["encoding", "bitOffset", "bitSize", "values"])
        source = .table(
          try InputField.field(in: container, codingPath: decoder.codingPath),
          try Self.directions(in: container, codingPath: decoder.codingPath)
        )
      default:
        throw DecodingError.dataCorrupted(
          .init(
            codingPath: decoder.codingPath,
            debugDescription: "hat encoding must be EightWay, Directions or Table"
          )
        )
      }
    }

    /// Reads `values`, a map from a canonical decimal value to a direction name.
    private static func directions(
      in container: KeyedDecodingContainer<DocumentKey>,
      codingPath: [any CodingKey]
    ) throws -> [Int: HatDirection] {
      var directions: [Int: HatDirection] = [:]
      for (key, name) in try container.decode([String: String].self, for: "values") {
        guard let value = Int(key), String(value) == key, value >= 0,
          let direction = HatDirection(rawValue: name), direction != .neutral
        else {
          throw DecodingError.dataCorrupted(
            .init(
              codingPath: codingPath,
              debugDescription: "values map decimal numbers to non-neutral direction names"
            )
          )
        }
        directions[value] = direction
      }
      return directions
    }
  }

  /// A trigger entry.
  struct InputTrigger: Decodable {
    /// The decoded trigger.
    let trigger: ControllerInputLayout.Trigger

    /// Decodes an analog value (`bitOffset` and `bitSize`, with optional `byteOrder`, `signed`,
    /// `min` and `max`), a `button` field, or both; any other key, or a value key without
    /// `bitOffset` and `bitSize`, is rejected.
    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: DocumentKey.self)
      let valueKeys: Set = ["bitOffset", "bitSize", "byteOrder", "signed", "min", "max"]
      try container.rejectUnknown(allowed: valueKeys.union(["button"]))
      let hasAnalog =
        container.contains(DocumentKey("bitOffset")) || container.contains(DocumentKey("bitSize"))
      guard hasAnalog || valueKeys.allSatisfy({ !container.contains(DocumentKey($0)) }) else {
        throw DecodingError.dataCorrupted(
          .init(
            codingPath: decoder.codingPath,
            debugDescription: "a trigger value needs bitOffset and bitSize"
          )
        )
      }
      trigger = ControllerInputLayout.Trigger(
        analog: hasAnalog
          ? try InputField.valueField(in: container, codingPath: decoder.codingPath) : nil,
        button: try container.decodeOptional(InputField.self, for: "button")?.field
      )
    }
  }
}
