/// A family's named packets (`defaults.session.namedPackets` in its protocol description): the
/// fixed packets a record selects by id in `protocol.initialization`.
///
/// Only `XboxGIP` has them.
struct NamedPacketPlan: Equatable, Sendable {
  /// The accepted number of named packets.
  static let countRange = 1...16
  /// The index of the byte the driver stamps with the GIP sequence number.
  static let sequenceByteIndex = 2

  /// The packets, in the order the description lists them.
  let packets: [NamedPacket]

  /// Creates a plan; throws when the packet count is outside `countRange` or two packets share an
  /// id.
  init(packets: [NamedPacket]) throws(ControllerRecordProblem) {
    guard Self.countRange.contains(packets.count) else {
      throw ControllerRecordProblem(
        code: .invalidControllerRecord,
        key: "error.E5007.namedPacketPlan.count",
        "namedPackets name 1...16 packets"
      )
    }
    guard Set(packets.map(\.id)).count == packets.count else {
      throw ControllerRecordProblem(
        code: .invalidControllerRecord,
        key: "error.E5007.namedPacketPlan.uniqueId",
        "each named packet id appears at most once"
      )
    }
    self.packets = packets
  }

  /// The packet that `identifier` names, if any.
  func packet(named identifier: String) -> NamedPacket? {
    packets.first { $0.id == identifier }
  }

  /// Whether every id starts with `prefix`, the family name and a slash.
  func allIDs(startWith prefix: String) -> Bool {
    packets.allSatisfy { $0.id.hasPrefix(prefix) }
  }
}

/// One named packet: its id and the raw-USB write that sends it, with the sequence number byte
/// left for the driver to stamp.
struct NamedPacket: Equatable, Sendable {
  /// The id that records select the packet by.
  let id: String
  /// The raw-USB write that sends the packet.
  let write: USBStartupWrite

  /// Creates a named packet; throws when the id is malformed, the packet has fewer than 3 bytes, or
  /// the session byte is not `NamedPacketPlan.sequenceByteIndex`.
  init(id: String, bytes: [UInt8], sessionByte: Int) throws(ControllerRecordProblem) {
    guard Self.isWellFormed(id) else {
      throw ControllerRecordProblem(
        code: .invalidControllerRecord,
        key: "error.E5007.namedPacketPlan.idForm",
        "a named packet id is a family, a slash and lowercase words joined by hyphens"
      )
    }
    guard bytes.count >= 3, sessionByte == NamedPacketPlan.sequenceByteIndex else {
      throw ControllerRecordProblem(
        code: .invalidControllerRecord,
        key: "error.E5007.namedPacketPlan.shape",
        "a named packet has at least 3 bytes and its session byte is 2"
      )
    }
    self.id = id
    write = try USBStartupWrite(bytes: bytes, sessionByte: sessionByte)
  }

  /// `<family>/<word>(-<word>)*`, where a word is lowercase letters and digits.
  static func isWellFormed(_ id: String) -> Bool {
    let parts = id.split(separator: "/", omittingEmptySubsequences: false)
    guard parts.count == 2, !parts[0].isEmpty else { return false }
    let words = parts[1].split(separator: "-", omittingEmptySubsequences: false)
    return words.allSatisfy { word in
      !word.isEmpty && word.allSatisfy { ("a"..."z").contains($0) || ("0"..."9").contains($0) }
    }
  }
}
