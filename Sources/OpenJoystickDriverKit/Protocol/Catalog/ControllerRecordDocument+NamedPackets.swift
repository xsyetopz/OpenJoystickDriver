extension NamedPacketPlan: Decodable {
  /// Decodes the list of named packets; a list that `NamedPacketPlan` rejects is rejected.
  init(from decoder: any Decoder) throws {
    let packets = try decoder.singleValueContainer().decode([NamedPacket].self)
    do {
      try self.init(packets: packets)
    } catch {
      throw DecodingError.dataCorrupted(error.context(at: decoder.codingPath))
    }
  }
}

extension NamedPacket: Decodable {
  /// Decodes `id`, `bytes` and `sessionByte`; an unknown key or a packet that `NamedPacket` rejects
  /// is rejected.
  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: DocumentKey.self)
    try container.rejectUnknown(allowed: ["id", "bytes", "sessionByte"])
    do {
      try self.init(
        id: container.decode(String.self, for: "id"),
        bytes: HexBytes.decode(container, for: "bytes", what: "named packet"),
        sessionByte: container.decode(Int.self, for: "sessionByte")
      )
    } catch let problem as ControllerRecordProblem {
      throw DecodingError.dataCorrupted(problem.context(at: decoder.codingPath))
    }
  }
}
