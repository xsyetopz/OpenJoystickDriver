import Foundation

/// Tracks host sequence numbers for the GIP (Xbox One) protocol.
///
/// System messages (option 0x20) share one counter, except security, extended and audio
/// messages, which each have their own. Vendor messages share another. No counter yields 0:
/// it starts at 1 and wraps from 255 to 1, as in the Linux GIP driver.
public struct GIPSequencer: Sendable {
  private static let extendedCommand: UInt8 = 0x1E
  private static let audioCommand: UInt8 = 0x60
  private static let vendorChannel = 0x100

  private var counters: [Int: UInt8] = [:]

  /// Creates a new GIPSequencer with every counter before 1.
  public init() {}

  /// Returns the next sequence number for a message with the given command ID and options.
  public mutating func next(for commandID: UInt8, options: UInt8) -> UInt8 {
    let channel = Self.channel(commandID: commandID, options: options)
    let next = counters[channel, default: 0] % 255 + 1
    counters[channel] = next
    return next
  }

  private static func channel(commandID: UInt8, options: UInt8) -> Int {
    guard options & GIPOption.internal != 0 else { return vendorChannel }
    switch commandID {
    case GIPCommand.authenticate, extendedCommand, audioCommand: return Int(commandID)
    default: return 0
    }
  }
}
