import Foundation

extension ControllerRecordDocument {
  /// The record's `tuning` section, with each value range-checked as the schema does.
  struct Tuning: Decodable {
    let tuning: ControllerTuning

    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: DocumentKey.self)
      try container.rejectUnknown(allowed: [
        "stickDeadzone", "inputLivenessTimeoutMs", "hidStartupIntervalMs",
        "minimumHIDOutputIntervalMs", "hidStartupRecoveryIntervalMs", "hidStartupRecoveryRounds",
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
        hidStartupRecoveryRounds: try integer("hidStartupRecoveryRounds", 1...10)
      )
    }
  }

  /// Each timing applies only where a driver reads it: DualShock 4 liveness, Switch 1 startup
  /// recovery, and HID startup and output pacing.
  func validateTuning(codingPath: [any CodingKey]) throws {
    let path = codingPath + [DocumentKey("tuning")]
    let quirks = protocolInfo.quirks
    let violation: String? =
      if tuning.inputLivenessTimeoutMilliseconds != nil,
        protocolInfo.protocolID != .sonyDualShock4
      {
        "inputLivenessTimeoutMs requires the sony.dualshock4 family"
      } else if tuning.hidStartupRecoveryIntervalMilliseconds != nil
        || tuning.hidStartupRecoveryRounds != nil,
        protocolInfo.protocolID != .nintendoSwitch1 || quirks.contains(.switch2)
          || quirks.contains(.inputOnly)
      {
        "startup recovery tuning requires a Switch 1 controller with startup recovery"
      } else if tuning.hidStartupIntervalMilliseconds != nil
        || tuning.minimumHIDOutputIntervalMilliseconds != nil,
        protocolInfo.protocolID.usesRawUSB(storedVariant: protocolInfo.protocolVariant)
      {
        "HID startup and output timings apply only to HID controllers"
      } else { nil }
    if let violation {
      throw DecodingError.dataCorrupted(.init(codingPath: path, debugDescription: violation))
    }
  }
}
