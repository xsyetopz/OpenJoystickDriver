import Foundation

/// Tracks host sequence numbers for the GIP (Xbox One) protocol.
///
/// System messages (option 0x20) share one counter, except security, extended and audio
/// messages, which each have their own; each vendor message type has its own counter
/// ([MS-GIPUSB] 2.2.10.3). No counter yields 0:
/// it starts at 1 and wraps from 255 to 1, as in the Linux GIP driver.
public struct GIPSequencer: Sendable {
  /// The command ID of extended messages, which have their own counter.
  private static let extendedCommand: UInt8 = 0x1E
  /// The command ID of audio messages, which have their own counter.
  private static let audioCommand: UInt8 = 0x60
  /// The counter key bit that marks a vendor message type.
  private static let vendorChannel = 0x100

  /// The latest sequence number for each counter.
  private var counters: [Int: UInt8] = [:]

  /// Creates a sequencer whose every counter starts before 1.
  public init() {}

  /// Returns the next sequence number for a message with the given command ID and options.
  public mutating func next(for commandID: UInt8, options: UInt8) -> UInt8 {
    let channel = Self.channel(commandID: commandID, options: options)
    let next = counters[channel, default: 0] % 255 + 1
    counters[channel] = next
    return next
  }

  /// Returns the counter that a message uses: the vendor channel of its command, or for a system
  /// message the shared one, the authenticate, extended or audio one.
  private static func channel(commandID: UInt8, options: UInt8) -> Int {
    guard options & GIPOption.internal != 0 else { return vendorChannel | Int(commandID) }
    switch commandID {
    case GIPCommand.authenticate, extendedCommand, audioCommand: return Int(commandID)
    default: return 0
    }
  }
}
