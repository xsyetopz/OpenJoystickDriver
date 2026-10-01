import Foundation

extension ControllerRecordDocument {
  /// The record's `input` section: a fixed report layout for the `hid.report-layout` family.
  struct InputLayout: Decodable {
    let layout: ControllerInputLayout

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
          buttons: buttons?.map { ($0.control, $0.field) } ?? [],
          axes: axes?.map(\.axis) ?? [],
          hat: hat?.map(\.source) ?? [],
          leftTrigger: try container.decodeOptional(InputTrigger.self, for: "leftTrigger")?.trigger,
          rightTrigger: try container.decodeOptional(InputTrigger.self, for: "rightTrigger")?
            .trigger
        )
      } catch let problem as ControllerRecordProblem {
        throw DecodingError.dataCorrupted(
          .init(codingPath: decoder.codingPath, debugDescription: problem.description)
        )
      }
    }
  }

  struct InputReport: Decodable {
    let reportID: UInt8?
    let length: Int

    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: DocumentKey.self)
      try container.rejectUnknown(allowed: ["id", "length"])
      length = try container.decode(Int.self, for: "length")
      guard let id = try container.decodeOptional(Int.self, for: "id") else {
        reportID = nil
        return
      }
      guard let reportID = UInt8(exactly: id), reportID != 0 else {
        throw DecodingError.dataCorrupted(
          .init(codingPath: decoder.codingPath, debugDescription: "id must be 1...255")
        )
      }
      self.reportID = reportID
    }
  }

  struct InputField: Decodable {
    let field: ReportBitField

    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: DocumentKey.self)
      try container.rejectUnknown(allowed: ["byte", "mask"])
      field = try Self.field(in: container, codingPath: decoder.codingPath)
    }

    /// Reads `byte` and `mask` from a container that may hold other keys.
    static func field(
      in container: KeyedDecodingContainer<DocumentKey>,
      codingPath: [any CodingKey]
    ) throws -> ReportBitField {
      let byte = try container.decode(Int.self, for: "byte")
      guard let mask = UInt8(exactly: try container.decode(Int.self, for: "mask")) else {
        throw DecodingError.dataCorrupted(
          .init(codingPath: codingPath, debugDescription: "mask must be 1...255")
        )
      }
      return ReportBitField(byte: byte, mask: mask)
    }
  }

  struct InputButton: Decodable {
    let control: ControlID
    let field: ReportBitField

    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: DocumentKey.self)
      try container.rejectUnknown(allowed: ["control", "byte", "mask"])
      control = try container.decode(ControlID.self, for: "control")
      field = try InputField.field(in: container, codingPath: decoder.codingPath)
    }
  }

  struct InputAxis: Decodable {
    let axis: ControllerInputLayout.Axis

    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: DocumentKey.self)
      try container.rejectUnknown(allowed: [
        "control", "byte", "bits", "signed", "min", "max", "inverted",
      ])
      let bits = try container.decodeOptional(Int.self, for: "bits") ?? 8
      let isSigned = try container.decodeOptional(Bool.self, for: "signed") ?? false
      let fullRange = ControllerInputLayout.Axis.fullRange(bits: bits, isSigned: isSigned)
      axis = ControllerInputLayout.Axis(
        control: try container.decode(ControlID.self, for: "control"),
        byte: try container.decode(Int.self, for: "byte"),
        bits: bits,
        isSigned: isSigned,
        minimum: try container.decodeOptional(Int.self, for: "min") ?? fullRange.lowerBound,
        maximum: try container.decodeOptional(Int.self, for: "max") ?? fullRange.upperBound,
        isInverted: try container.decodeOptional(Bool.self, for: "inverted") ?? false
      )
    }
  }

  struct InputHatSource: Decodable {
    let source: ControllerInputLayout.HatSource

    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: DocumentKey.self)
      let encoding = try container.decode(String.self, for: "encoding")
      switch encoding {
      case "8-way":
        try container.rejectUnknown(allowed: ["encoding", "byte", "mask", "neutralUntilNonzero"])
        source = .eightWay(
          try InputField.field(in: container, codingPath: decoder.codingPath),
          neutralUntilNonzero: try container.decodeOptional(Bool.self, for: "neutralUntilNonzero")
            ?? false
        )
      case "directions":
        try container.rejectUnknown(allowed: ["encoding", "up", "right", "down", "left"])
        source = .directions(
          up: try container.decode(InputField.self, for: "up").field,
          right: try container.decode(InputField.self, for: "right").field,
          down: try container.decode(InputField.self, for: "down").field,
          left: try container.decode(InputField.self, for: "left").field
        )
      default:
        throw DecodingError.dataCorrupted(
          .init(
            codingPath: decoder.codingPath,
            debugDescription: "hat encoding must be 8-way or directions"
          )
        )
      }
    }
  }

  struct InputTrigger: Decodable {
    let trigger: ControllerInputLayout.Trigger

    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: DocumentKey.self)
      try container.rejectUnknown(allowed: ["byte", "button"])
      trigger = ControllerInputLayout.Trigger(
        byte: try container.decodeOptional(Int.self, for: "byte"),
        button: try container.decodeOptional(InputField.self, for: "button")?.field
      )
    }
  }
}
