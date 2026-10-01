extension ControllerRecordDocument {
  /// The record's output section: a rumble template, startup writes, or both.
  struct Output: Decodable {
    let rumble: RumbleOutputTemplate?
    let startup: [RecordStartupWrite]

    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: DocumentKey.self)
      try container.rejectUnknown(allowed: ["rumble", "startup"])
      rumble = try container.decodeOptional(RumbleTemplate.self, for: "rumble")?.template
      let startup = try container.decodeOptional([StartupWrite].self, for: "startup")
      self.startup = startup?.map(\.write) ?? []
      guard rumble != nil || startup != nil, startup.map({ (1...16).contains($0.count) }) ?? true
      else {
        throw DecodingError.dataCorrupted(
          .init(
            codingPath: decoder.codingPath,
            debugDescription: "output names a rumble template or 1...16 startup writes"
          )
        )
      }
    }
  }

  struct StartupWrite: Decodable {
    let write: RecordStartupWrite

    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: DocumentKey.self)
      try container.rejectUnknown(allowed: ["report", "bytes", "delayMilliseconds", "transport"])
      let report = try container.decode(TemplateReport.self, for: "report").report
      let values = try container.decode([Int].self, for: "bytes")
      let delay = try container.decodeOptional(Int.self, for: "delayMilliseconds") ?? 0
      let transportName = try container.decodeOptional(String.self, for: "transport")
      let bytes = values.compactMap(UInt8.init(exactly:))
      let transport = transportName.flatMap(PhysicalTransport.init(rawValue:))
      do throws(ControllerRecordProblem) {
        guard bytes.count == values.count else {
          throw ControllerRecordProblem("startup bytes are 0...255")
        }
        guard transportName == nil || transport != nil else {
          throw ControllerRecordProblem(
            "a startup transport is usb, bluetooth-classic or bluetooth-le"
          )
        }
        write = try RecordStartupWrite(
          report: report,
          bytes: bytes,
          delayMilliseconds: delay,
          transport: transport
        )
      } catch {
        throw DecodingError.dataCorrupted(
          .init(codingPath: decoder.codingPath, debugDescription: error.description)
        )
      }
    }
  }
}
