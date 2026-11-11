extension SubcommandPlan: Decodable {
  /// Decodes `reportID`, `counterModulus`, `requests` and `playerIndicator`; an unknown key or a
  /// plan that `SubcommandPlan` rejects is rejected.
  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: DocumentKey.self)
    try container.rejectUnknown(allowed: [
      "reportID", "counterModulus", "requests", "playerIndicator",
    ])
    do {
      try self.init(
        reportID: container.decode(UInt8.self, for: "reportID"),
        counterModulus: container.decode(Int.self, for: "counterModulus"),
        requests: container.decode([SubcommandRequest].self, for: "requests"),
        playerIndicator: container.decode(PlayerIndicatorSubcommand.self, for: "playerIndicator")
      )
    } catch let problem as ControllerRecordProblem {
      throw DecodingError.dataCorrupted(
        .init(codingPath: decoder.codingPath, debugDescription: problem.description)
      )
    }
  }
}

extension PlayerIndicatorSubcommand: Decodable {
  /// The patterns object names `off` and `player1` through `player4`, each a byte.
  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: DocumentKey.self)
    try container.rejectUnknown(allowed: ["subcommand", "patterns"])
    let names: [(String, PhysicalPlayerIndicator)] = [
      ("off", .off), ("player1", .player1), ("player2", .player2), ("player3", .player3),
      ("player4", .player4),
    ]
    let patternsContainer = try container.nestedContainer(
      keyedBy: DocumentKey.self,
      forKey: DocumentKey("patterns")
    )
    try patternsContainer.rejectUnknown(allowed: Set(names.map(\.0)))
    var patterns: [PhysicalPlayerIndicator: UInt8] = [:]
    for (name, indicator) in names {
      patterns[indicator] = try patternsContainer.decode(UInt8.self, for: name)
    }
    do {
      try self.init(
        subcommand: container.decode(UInt8.self, for: "subcommand"),
        patterns: patterns
      )
    } catch let problem as ControllerRecordProblem {
      throw DecodingError.dataCorrupted(
        .init(codingPath: decoder.codingPath, debugDescription: problem.description)
      )
    }
  }
}

extension SubcommandRequest: Decodable {
  /// A request with an `spiRead` is an SPI read; one without carries its `data`.
  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: DocumentKey.self)
    try container.rejectUnknown(allowed: ["subcommand", "data", "spiRead"])
    let subcommand = try container.decode(UInt8.self, for: "subcommand")
    var data: [UInt8]?
    if container.contains(DocumentKey("data")) {
      do {
        data = try HexBytes.decode(container, for: "data", what: "subcommand request data")
      } catch let problem as ControllerRecordProblem {
        throw DecodingError.dataCorrupted(
          .init(
            codingPath: decoder.codingPath + [DocumentKey("data")],
            debugDescription: problem.description
          )
        )
      }
    }
    let read = try container.decodeOptional(SPIRead.self, for: "spiRead")
    do {
      switch (data, read) {
      case (let data?, nil): try self.init(subcommand: subcommand, data: data)
      case (nil, let read?): try self.init(subcommand: subcommand, spiRead: read)
      default:
        throw ControllerRecordProblem(
          code: .invalidControllerRecord,
          "a subcommand request names exactly one of data and spiRead"
        )
      }
    } catch let problem as ControllerRecordProblem {
      throw DecodingError.dataCorrupted(
        .init(codingPath: decoder.codingPath, debugDescription: problem.description)
      )
    }
  }
}

extension SubcommandRequest.SPIRead: Decodable {
  /// Decodes `address`, `length` and `purpose`; an unknown key or an unknown purpose is rejected.
  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: DocumentKey.self)
    try container.rejectUnknown(allowed: ["address", "length", "purpose"])
    let name = try container.decode(String.self, for: "purpose")
    let length = try container.decode(Int.self, for: "length")
    guard let purpose = Purpose(rawValue: name), Self.lengthRange.contains(length) else {
      throw DecodingError.dataCorrupted(
        .init(
          codingPath: decoder.codingPath,
          debugDescription: "an SPI read has a known purpose and a length of 1...29"
        )
      )
    }
    self.init(
      address: try container.decode(UInt32.self, for: "address"),
      length: UInt8(length),
      purpose: purpose
    )
  }
}
