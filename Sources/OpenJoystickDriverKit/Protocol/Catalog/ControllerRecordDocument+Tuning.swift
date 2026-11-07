import Foundation

extension ControllerRecordDocument {
  /// The record's `tuning` section, with each value range-checked as the schema does.
  struct Tuning: Decodable {
    /// The decoded tuning.
    let tuning: ControllerTuning

    /// Decodes the tuning keys of a record; an unknown key or a value outside its range is
    /// rejected.
    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: DocumentKey.self)
      try container.rejectUnknown(allowed: [
        "stickDeadzone", "inputLivenessTimeoutMs", "hidStartupIntervalMs",
        "minimumHIDOutputIntervalMs", "hidStartupRecoveryIntervalMs", "hidStartupRecoveryRounds",
        "lizardResendTicks",
        "usbCommandTimeoutMs",
        "presenceResendReports",
        "adapterDisconnectDelayMs",
        "usbStartupIntervalMs",
        "usbStartupRetryDelayMs",
        "usbTransferTimeoutMs",
        "irWriteIntervalMs",
        "speakerMaxSeconds",
        "replyTimeoutMs",
        "frameQueueCapacity",
      ])
      guard !container.allKeys.isEmpty else {
        throw DecodingError.dataCorrupted(
          .init(codingPath: decoder.codingPath, debugDescription: "tuning must not be empty")
        )
      }
      func integer(_ key: String, _ range: ClosedRange<Int>) throws -> Int? {
        let value = try container.decodeOptional(Int.self, for: key)
        guard value.map(range.contains) ?? true else {
          throw DecodingError.dataCorrupted(
            .init(
              codingPath: decoder.codingPath + [DocumentKey(key)],
              debugDescription: "\(key) must be in \(range.lowerBound)...\(range.upperBound)"
            )
          )
        }
        return value
      }
      let deadzone = try container.decodeOptional(Double.self, for: "stickDeadzone")
      guard deadzone.map({ $0 > 0 && $0 < 1 }) ?? true else {
        throw DecodingError.dataCorrupted(
          .init(
            codingPath: decoder.codingPath + [DocumentKey("stickDeadzone")],
            debugDescription: "stickDeadzone must be greater than 0 and less than 1"
          )
        )
      }
      tuning = ControllerTuning(
        stickDeadzone: deadzone.map(Float.init),
        inputLivenessTimeoutMilliseconds: try integer("inputLivenessTimeoutMs", 1...60_000),
        hidStartupIntervalMilliseconds: try integer("hidStartupIntervalMs", 0...60_000),
        minimumHIDOutputIntervalMilliseconds: try integer("minimumHIDOutputIntervalMs", 0...60_000),
        hidStartupRecoveryIntervalMilliseconds: try integer(
          "hidStartupRecoveryIntervalMs",
          1...60_000
        ),
        hidStartupRecoveryRounds: try integer("hidStartupRecoveryRounds", 1...10),
        lizardResendTicks: try integer("lizardResendTicks", 1...100_000),
        usbCommandTimeoutMilliseconds: try integer("usbCommandTimeoutMs", 1...60_000),
        presenceResendReports: try integer("presenceResendReports", 1...1_000),
        adapterDisconnectDelayMilliseconds: try integer("adapterDisconnectDelayMs", 1...60_000),
        usbStartupIntervalMilliseconds: try integer("usbStartupIntervalMs", 0...60_000),
        usbStartupRetryDelayMilliseconds: try integer("usbStartupRetryDelayMs", 1...60_000),
        usbTransferTimeoutMilliseconds: try integer("usbTransferTimeoutMs", 1...60_000),
        irWriteIntervalMilliseconds: try integer(
          "irWriteIntervalMs",
          ControllerTuning.irWriteIntervalRange
        ),
        speakerMaxSeconds: try integer(
          "speakerMaxSeconds",
          ControllerTuning.speakerMaxSecondsRange
        ),
        replyTimeoutMilliseconds: try integer("replyTimeoutMs", ControllerTuning.replyTimeoutRange),
        frameQueueCapacity: try integer(
          "frameQueueCapacity",
          ControllerTuning.frameQueueCapacityRange
        )
      )
    }
  }

  /// Each timing applies only where a driver reads it; the family's description names the keys
  /// its driver reads.
  func validateTuning(codingPath: [any CodingKey]) throws {
    let path = codingPath + [DocumentKey("tuning")]
    let violation = ControllerTuning.Key.allCases.filter(tuning.setKeys.contains).lazy
      .compactMap(tuningScopeViolation).first
    if let violation {
      throw DecodingError.dataCorrupted(.init(codingPath: path, debugDescription: violation))
    }
  }
}
