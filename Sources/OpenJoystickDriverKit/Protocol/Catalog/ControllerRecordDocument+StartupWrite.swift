extension ControllerRecordDocument {
  /// A startup write that names one of the family's packets (`defaults.session.namedPackets`).
  ///
  /// Only a protocol description has them.
  struct StartupPacketReference: Equatable, Sendable {
    /// The ID of the named packet.
    let id: String
    /// The condition under which the packet is sent.
    let condition: StartupWriteCondition
  }

  /// One startup write of either format, or a reference to a named packet.
  struct StartupWrite: Decodable {
    /// The HID report write; nil unless the entry has a `report`.
    let hid: RecordStartupWrite?
    /// The raw-USB write; nil unless the entry is a raw-USB packet.
    let usb: USBStartupWrite?
    /// The named packet reference; nil unless the entry has a `packet`.
    let packet: StartupPacketReference?

    /// Decodes a `packet` reference, a HID write with a `report`, or a raw-USB write, together with
    /// the optional `variants` and `when` conditions; an unknown key for the entry's kind, or a
    /// write its type rejects, is rejected.
    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: DocumentKey.self)
      let condition = try StartupWriteCondition.decode(from: container, decoder: decoder)
      do {
        if container.contains(DocumentKey("packet")) {
          guard decoder.userInfo[.startupConditionsAllowed] as? Bool == true else {
            throw ControllerRecordProblem(
              code: .invalidControllerRecord,
              key: "error.E5007.startupWrite.packetReference",
              "a startup packet reference is for protocol descriptions"
            )
          }
          try container.rejectUnknown(allowed: ["packet", "variants", "when"])
          packet = StartupPacketReference(
            id: try container.decode(String.self, for: "packet"),
            condition: condition
          )
          hid = nil
          usb = nil
        } else if container.contains(DocumentKey("report")) {
          try container.rejectUnknown(allowed: [
            "report", "bytes", "delayMilliseconds", "transport", "phase", "crc32Seed", "variants",
            "when",
          ])
          hid = try Self.hidWrite(container, condition: condition)
          usb = nil
          packet = nil
        } else {
          try container.rejectUnknown(allowed: [
            "bytes", "endpoint", "timeoutMilliseconds", "delayMilliseconds", "sessionByte",
            "toleratesRejection", "variants", "when",
          ])
          usb = try Self.usbWrite(container, condition: condition)
          hid = nil
          packet = nil
        }
      } catch let problem as ControllerRecordProblem {
        throw DecodingError.dataCorrupted(problem.context(at: decoder.codingPath))
      }
    }

    /// Reads the `bytes` hex string of a startup write.
    static func bytes(
      _ container: KeyedDecodingContainer<DocumentKey>
    ) throws -> [UInt8] {
      try HexBytes.decode(container, for: "bytes", what: "startup")
    }

    /// Reads a HID startup write with its `condition`; throws when a field is missing or outside
    /// its range.
    static func hidWrite(
      _ container: KeyedDecodingContainer<DocumentKey>,
      condition: StartupWriteCondition
    ) throws -> RecordStartupWrite {
      let report = try container.decode(TemplateReport.self, for: "report").report
      let transportName = try container.decodeOptional(String.self, for: "transport")
      let transport = transportName.flatMap(PhysicalTransport.init(rawValue:))
        .flatMap { $0 == .proprietaryRadioReceiver ? nil : $0 }
      guard transportName == nil || transport != nil else {
        throw ControllerRecordProblem(
          code: .invalidControllerRecord,
          key: "error.E5007.startupWrite.transport",
          "a startup transport is USB, BluetoothClassic or BluetoothLE"
        )
      }
      let phaseName = try container.decodeOptional(String.self, for: "phase")
      let phase = phaseName.flatMap(StartupPhase.init(rawValue:))
      guard phaseName == nil || phase != nil else {
        throw ControllerRecordProblem(
          code: .invalidControllerRecord,
          key: "error.E5007.startupWrite.phase",
          "a startup phase is Startup or Activation"
        )
      }
      let seed = try container.decodeOptional(Int.self, for: "crc32Seed")
      guard seed.map({ (0...255).contains($0) }) ?? true else {
        throw ControllerRecordProblem(
          code: .invalidControllerRecord,
          key: "error.E5007.startupWrite.crcSeedRange",
          "a startup crc32Seed is 0...255"
        )
      }
      return try RecordStartupWrite(
        report: report,
        bytes: bytes(container),
        delayMilliseconds: container.decodeOptional(Int.self, for: "delayMilliseconds"),
        transport: transport,
        phase: phase ?? .activation,
        crc32Seed: seed.map { UInt8($0) },
        condition: condition
      )
    }

    /// Reads a raw-USB startup write with its `condition`; throws when a field is missing or
    /// outside its range.
    static func usbWrite(
      _ container: KeyedDecodingContainer<DocumentKey>,
      condition: StartupWriteCondition
    ) throws -> USBStartupWrite {
      let endpoint = try container.decodeOptional(Int.self, for: "endpoint")
      guard endpoint.map(USBStartupWrite.endpointRange.contains) ?? true else {
        throw ControllerRecordProblem(
          code: .invalidControllerRecord,
          key: "error.E5007.startupWrite.usbEndpoint",
          "a USB startup endpoint is 1...127"
        )
      }
      return try USBStartupWrite(
        bytes: bytes(container),
        endpoint: endpoint.map { UInt8($0) },
        timeoutMilliseconds: container.decodeOptional(Int.self, for: "timeoutMilliseconds"),
        delayMilliseconds: container.decodeOptional(Int.self, for: "delayMilliseconds"),
        sessionByte: container.decodeOptional(Int.self, for: "sessionByte"),
        toleratesRejection: container.decodeOptional(Bool.self, for: "toleratesRejection")
          ?? false,
        condition: condition
      )
    }
  }
}
