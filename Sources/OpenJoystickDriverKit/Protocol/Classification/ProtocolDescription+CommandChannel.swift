import Foundation

extension ProtocolDescription {
  /// `defaults.session.commandChannel`: the USB interface that carries a family's commands and
  /// their replies.
  ///
  /// Only `NintendoSwitch2` has it.
  struct CommandChannel: Decodable, Equatable, Sendable {
    /// The USB interface number of the channel.
    let interface: UInt8
    /// The IN endpoint address that carries replies.
    let inEndpoint: UInt8
    /// Largest reply read after each command.
    let replyLength: Int
    /// Timeout of each reply read over USB.
    let usbReplyTimeoutMilliseconds: UInt32
    /// Timeout of each reply read over Bluetooth LE.
    let bluetoothLEReplyTimeoutMilliseconds: UInt32

    /// Decodes `interface`, `inEndpoint`, `replyLength` and the two reply timeouts; an unknown key
    /// or a value outside its range is rejected.
    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: DocumentKey.self)
      try container.rejectUnknown(allowed: [
        "interface", "inEndpoint", "replyLength", "usbReplyTimeoutMilliseconds",
        "bluetoothLEReplyTimeoutMilliseconds",
      ])
      func value(
        _ container: KeyedDecodingContainer<DocumentKey>,
        _ key: String,
        _ range: ClosedRange<Int>
      ) throws -> Int {
        let value = try container.decode(Int.self, for: key)
        guard range.contains(value) else {
          throw DecodingError.dataCorrupted(
            .init(
              codingPath: container.codingPath + [DocumentKey(key)],
              debugDescription: "\(key) must be in \(range.lowerBound)...\(range.upperBound)"
            )
          )
        }
        return value
      }
      interface = UInt8(try value(container, "interface", 0...255))
      inEndpoint = UInt8(try value(container, "inEndpoint", 128...255))
      replyLength = try value(container, "replyLength", 1...4096)
      usbReplyTimeoutMilliseconds = UInt32(
        try value(container, "usbReplyTimeoutMilliseconds", 1...60_000)
      )
      bluetoothLEReplyTimeoutMilliseconds = UInt32(
        try value(container, "bluetoothLEReplyTimeoutMilliseconds", 1...60_000)
      )
    }
  }
}
