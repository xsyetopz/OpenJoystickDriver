import Foundation

extension ControllerRecordDocument {
  /// The rumble template of a record, as a `report` target with its motor fields.
  struct RumbleTemplate: Decodable {
    /// The decoded template.
    let template: RumbleOutputTemplate

    /// Decodes `report`, `bytes`, `counter`, `resendIntervalMilliseconds`, `followUp`, `stop` and
    /// one field per template motor; an unknown key or a template that `RumbleOutputTemplate`
    /// rejects is rejected.
    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: DocumentKey.self)
      let motors = RumbleOutputTemplate.templateMotors
      try container.rejectUnknown(
        allowed: Set(
          ["report", "bytes", "counter", "resendIntervalMilliseconds", "followUp", "stop"]
            + motors.map(\.recordKey)
        )
      )
      let target = try container.decode(RumbleTarget.self, for: "report").target
      var fields: [PhysicalRumbleMotor: RumbleOutputTemplate.MotorField] = [:]
      for motor in motors {
        fields[motor] = try container.decodeOptional(MotorField.self, for: motor.recordKey)?.field
      }
      do {
        let bytes =
          container.contains(DocumentKey("bytes"))
          ? try HexBytes.decode(container, for: "bytes", what: "rumble template") : nil
        template = try RumbleOutputTemplate(
          target: target,
          bytes: bytes,
          motors: fields,
          counterByte: try container.decodeOptional(TemplateByte.self, for: "counter")?.byte,
          resendIntervalMilliseconds: try container.decodeOptional(
            Int.self,
            for: "resendIntervalMilliseconds"
          ),
          followUp: try container.decodeOptional([String].self, for: "followUp")?.map {
            text throws(ControllerRecordProblem) in
            guard let report = HexBytes.parse(text) else {
              throw .rule(
                "error.E5007.record.hexBytes",
                ["followUp", "rumble follow-up"],
                "rumble follow-up \(HexBytes.message)"
              )
            }
            return report
          },
          stop: container.contains(DocumentKey("stop"))
            ? try HexBytes.decode(container, for: "stop", what: "rumble stop") : nil
        )
      } catch let problem as ControllerRecordProblem {
        throw DecodingError.dataCorrupted(
          problem.context(at: decoder.codingPath)
        )
      }
    }
  }

  /// The player-indicator template of a record: a HID `report`, the `byte` that carries the value
  /// and one value per slot.
  struct PlayerIndicatorTemplate: Decodable {
    /// The decoded template.
    let template: PlayerIndicatorOutputTemplate

    /// Decodes `report`, `byte` and one value per slot; an unknown key, a missing or out-of-range
    /// value, or a template that `PlayerIndicatorOutputTemplate` rejects is rejected.
    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: DocumentKey.self)
      let slots = PhysicalPlayerIndicator.allCases
      try container.rejectUnknown(allowed: Set(["report", "byte"] + slots.map(\.recordKey)))
      var values: [PhysicalPlayerIndicator: UInt8] = [:]
      for slot in slots {
        let value = try container.decode(Int.self, for: slot.recordKey)
        guard let byte = UInt8(exactly: value) else {
          throw DecodingError.dataCorrupted(
            .init(
              codingPath: decoder.codingPath + [DocumentKey(slot.recordKey)],
              debugDescription: "a player-indicator value is 0...255"
            )
          )
        }
        values[slot] = byte
      }
      do {
        template = try PlayerIndicatorOutputTemplate(
          report: try container.decode(TemplateReport.self, for: "report").report,
          byte: try container.decode(Int.self, for: "byte"),
          values: values
        )
      } catch let problem as ControllerRecordProblem {
        throw DecodingError.dataCorrupted(problem.context(at: decoder.codingPath))
      }
    }
  }

  /// A rumble template's report: a HID output or feature report, or a raw-USB packet of
  /// `length` bytes to the family's output endpoint.
  struct RumbleTarget: Decodable {
    /// The decoded target.
    let target: RumbleOutputTemplate.Target

    /// Decodes a `USB` target with `length`, or a HID target with `kind`, `id` and `length`; an
    /// unknown key is rejected.
    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: DocumentKey.self)
      if try container.decode(String.self, for: "kind") == "USB" {
        try container.rejectUnknown(allowed: ["kind", "length"])
        target = .usb(length: try container.decode(Int.self, for: "length"))
      } else {
        target = .hid(try TemplateReport(from: decoder).report)
      }
    }
  }

  /// Where a rumble template writes one motor: its first byte and the value's encoding.
  struct MotorField: Decodable {
    /// The decoded motor field.
    let field: RumbleOutputTemplate.MotorField

    /// Decodes `byte` and an optional `encoding`; an unknown key or an unknown encoding is
    /// rejected.
    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: DocumentKey.self)
      try container.rejectUnknown(allowed: ["byte", "encoding"])
      let encodingName = try container.decodeOptional(String.self, for: "encoding")
      guard let encoding = encodingName.map(RumbleMotorEncoding.init(rawValue:)) ?? .uInt8 else {
        throw DecodingError.dataCorrupted(
          .init(
            codingPath: decoder.codingPath,
            debugDescription: "a rumble motor encoding is "
              + RumbleMotorEncoding.allCases.map(\.rawValue).joined(separator: ", ")
          )
        )
      }
      field = .init(byte: try container.decode(Int.self, for: "byte"), encoding: encoding)
    }
  }

  /// A HID report named by `kind`, `id` and `length`.
  struct TemplateReport: Decodable {
    /// The decoded report.
    let report: ControllerTemplateReport

    /// Decodes `kind`, `id` and `length`; an unknown key or kind is rejected.
    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: DocumentKey.self)
      try container.rejectUnknown(allowed: ["kind", "id", "length"])
      let reportKind = try container.decode(String.self, for: "kind")
      let reportID = try container.decode(Int.self, for: "id")
      let length = try container.decode(Int.self, for: "length")
      guard reportKind == "Output" || reportKind == "Feature",
        let id = UInt8(exactly: reportID)
      else {
        throw DecodingError.dataCorrupted(
          .init(
            codingPath: decoder.codingPath,
            debugDescription: "report must be an output or feature report with ID 0...255"
          )
        )
      }
      report = ControllerTemplateReport(
        kind: reportKind == "Output" ? .output : .feature,
        reportID: id,
        length: length
      )
    }
  }

  /// A byte offset named by `byte`.
  struct TemplateByte: Decodable {
    /// The decoded offset.
    let byte: Int

    /// Decodes `byte`; any other key is rejected.
    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: DocumentKey.self)
      try container.rejectUnknown(allowed: ["byte"])
      byte = try container.decode(Int.self, for: "byte")
    }
  }
}
