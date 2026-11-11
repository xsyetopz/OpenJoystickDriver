extension KeepAlive: Decodable {
  /// Decodes `intervalMilliseconds` and an optional `writes` list; an unknown key, an explicitly
  /// empty `writes`, or a value that `KeepAlive` rejects is rejected.
  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: DocumentKey.self)
    try container.rejectUnknown(allowed: ["intervalMilliseconds", "writes"])
    do {
      try self.init(
        intervalMilliseconds: container.decode(Int.self, for: "intervalMilliseconds"),
        writes: container.decodeOptional([KeepAliveWrite].self, for: "writes") ?? []
      )
      guard !container.contains(DocumentKey("writes")) || !writes.isEmpty else {
        throw ControllerRecordProblem(
          code: .invalidControllerRecord,
          key: "error.E5007.keepAlive.writesCount",
          "keepAlive names no writes or 1...8 of them"
        )
      }
    } catch let problem as ControllerRecordProblem {
      throw DecodingError.dataCorrupted(
        problem.context(at: decoder.codingPath)
      )
    }
  }
}

extension KeepAliveWrite: Decodable {
  /// A write with a `report` is a HID write; one without is a raw-USB write.
  ///
  /// Its keys are the startup write's, less `phase`, `delayMilliseconds`, `transport`, `crc32Seed`,
  /// `toleratesRejection` and `when`, and plus `resendTuning`.
  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: DocumentKey.self)
    let isHID = container.contains(DocumentKey("report"))
    try container.rejectUnknown(
      allowed: isHID
        ? ["report", "bytes", "variants", "resendTuning"]
        : ["bytes", "endpoint", "timeoutMilliseconds", "sessionByte", "variants", "resendTuning"]
    )
    let condition = try StartupWriteCondition.decode(from: container, decoder: decoder)
    do {
      let name = try container.decodeOptional(String.self, for: "resendTuning")
      let key = name.flatMap(ControllerTuning.Key.init(rawValue:))
      guard name == nil || key.map(Self.resendTuningKeys.contains) == true else {
        throw ControllerRecordProblem(
          code: .invalidControllerRecord,
          key: "error.E5007.keepAlive.resendTuning",
          "a keep-alive resendTuning is lizardResendTicks"
        )
      }
      resendTuning = key
      payload =
        isHID
        ? .hid(try ControllerRecordDocument.StartupWrite.hidWrite(container, condition: condition))
        : .usb(try ControllerRecordDocument.StartupWrite.usbWrite(container, condition: condition))
    } catch let problem as ControllerRecordProblem {
      throw DecodingError.dataCorrupted(
        problem.context(at: decoder.codingPath)
      )
    }
  }
}
