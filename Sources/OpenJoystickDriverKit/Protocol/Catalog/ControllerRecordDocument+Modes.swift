import Foundation

extension ControllerRecordDocument {
  /// A probe: a read of one feature report, with no way to write.
  struct ModeProbeDocument: Decodable {
    /// The decoded probe.
    let probe: ControllerModeProbe

    /// Decodes `report`, `length`, `expect` and the `offset` and `bytes` of a byte expectation; an
    /// unknown key, an unknown expectation, or `offset` and `bytes` on any expectation but `Bytes`
    /// is rejected.
    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: DocumentKey.self)
      try container.rejectUnknown(allowed: ["report", "length", "expect", "offset", "bytes"])
      let report = try container.decode(Int.self, for: "report")
      let length = try container.decode(Int.self, for: "length")
      let expect = try container.decode(String.self, for: "expect")
      let offset = try container.decodeOptional(Int.self, for: "offset")
      let hex = try container.decodeOptional(String.self, for: "bytes")
      guard let reportID = UInt8(exactly: report), (1...65_535).contains(length) else {
        throw Self.invalid("a probe reads report 0...255 with a length of 1...65535", decoder)
      }
      let expectation: ControllerModeProbe.Expectation
      switch (expect, offset, hex) {
      case ("Answers", nil, nil): expectation = .answers
      case ("Stalls", nil, nil): expectation = .stalls
      case ("Bytes", let offset?, let hex?):
        guard let expected = HexBytes.parse(hex), offset >= 0, offset + expected.count <= length
        else {
          throw Self.invalid(
            "probe bytes are uppercase hex pairs that fit the read length",
            decoder
          )
        }
        expectation = .bytes(offset: offset, expected: expected)
      default:
        throw Self.invalid(
          "a probe expects Answers, Stalls, or Bytes; only Bytes carries offset and bytes",
          decoder
        )
      }
      probe = ControllerModeProbe(reportID: reportID, length: length, expectation: expectation)
    }

    /// Creates the decoding error for a probe with `message`.
    private static func invalid(_ message: String, _ decoder: any Decoder) -> DecodingError {
      .dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: message))
    }
  }

  /// The record's modes: unique IDs and at most one `default`; every mode's protocol obeys the same
  /// record-level rules the default protocol does, whether the record has one mode or many.
  ///
  /// A mode's session runs only what its own protocol can (see `sessionViolation`), and `interface`
  /// selects among HID interfaces, so a raw-USB mode has none. A HID route reports no endpoint set,
  /// so only a raw-USB mode's interface signature may carry `endpoints`.
  func validateModes(codingPath: [any CodingKey]) throws {
    let path = codingPath + [DocumentKey("modes")]
    func fail(_ rule: String, _ message: String) -> DecodingError {
      fail(.rule(rule, message))
    }
    func fail(_ problem: ControllerRecordProblem) -> DecodingError {
      .dataCorrupted(problem.context(at: path))
    }
    guard !modes.isEmpty else { throw fail("error.E5007.modes.empty", "modes must not be empty") }
    guard modes.filter(\.isDefault).count <= 1 else {
      throw fail(
        "error.E5007.modes.defaultCount",
        "modes need at most one mode with the id default"
      )
    }
    guard Set(modes.map(\.id)).count == modes.count else {
      throw fail("error.E5007.modes.uniqueIDs", "mode IDs must be unique")
    }
    for mode in modes {
      let info = mode.protocolInfo
      let rawUSB = info.protocolID.usesRawUSB(storedVariant: info.protocolVariant)
      if let problem = mode.sessionViolation() { throw fail(problem) }
      if rawUSB {
        if mode.interfaceRange != nil {
          throw fail(
            "error.E5007.modes.interfaceRawUSB",
            "interface selects among HID interfaces; a raw-USB mode claims the interface its"
              + " usb transport resolves"
          )
        }
      } else if mode.match?.interfaceSignature?.endpoints != nil {
        throw fail(
          "error.E5007.modes.endpointsHID",
          "a HID mode's interfaceSignature has no endpoints; only the raw USB scanner reads"
            + " an interface's endpoint set"
        )
      }
      if (mode.input?.layouts ?? inputLayouts) == nil, info.protocolID.requiresRecordInputLayout {
        throw fail(
          "error.E5007.modes.inputLayoutNeeded",
          "a HIDReportLayout mode needs the record's input layout"
        )
      }
      if (mode.input?.usageMap ?? hidUsageMap) != nil,
        !info.protocolID.protocolDescription.recordSections.contains(.hidUsageMap)
      {
        throw fail(
          "error.E5007.modes.usageMapDriver",
          "a HID usage map applies only to a driver that reads one, in every mode"
        )
      }
    }
    guard capabilitiesDeclared(byAnyOf: modes.map(\.protocolInfo.protocolID)) else {
      throw fail(
        "error.E5007.modes.capabilities",
        "capabilities must be deltas the driver of some mode declares"
      )
    }
  }
}
