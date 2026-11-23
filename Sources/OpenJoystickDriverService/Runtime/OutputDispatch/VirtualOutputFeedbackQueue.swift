import Foundation
import OpenJoystickDriverKit

/// The feedback of one controller waiting to be sent, in arrival order.
///
/// A DualShock 4 host sends held rumble and ends it with a separate zero report, so a short cue is
/// a set and a stop a few milliseconds apart. A physical write takes longer than that, and a cue
/// whose set was dropped or overtaken never reaches the motor. The queue therefore keeps the order,
/// and while a write is in flight it collapses only rumble that a later rumble replaces, keeping
/// the last set ahead of a final stop.
struct VirtualOutputFeedbackQueue: Sendable {
  /// One queued command.
  struct Entry: Sendable {
    /// The consumer command.
    var command: ControllerOutputCommand
    /// The admission generation the command arrived under.
    var generation: VirtualOutputFeedbackGeneration
    /// When the command arrived.
    var arrival: ContinuousClock.Instant
  }

  /// The commands in arrival order.
  private(set) var entries: [Entry] = []

  /// Whether no command waits.
  var isEmpty: Bool { entries.isEmpty }

  /// Appends `entry` after the waiting commands.
  mutating func append(_ entry: Entry) { entries.append(entry) }

  /// Removes every waiting command.
  mutating func removeAll() { entries.removeAll() }

  /// Collapses the waiting rumble, then removes and returns the first command.
  mutating func popFirst() -> Entry? {
    entries = Self.collapsed(entries)
    return entries.isEmpty ? nil : entries.removeFirst()
  }

  /// `entries` with each rumble command dropped that a later rumble command replaces, except the
  /// last set-rumble before a final stop, so a short cue still reaches the motor.
  ///
  /// Commands other than rumble keep their place.
  static func collapsed(_ entries: [Entry]) -> [Entry] {
    guard let last = entries.lastIndex(where: { $0.command.isRumble }) else { return entries }
    var kept: Set<Int> = [last]
    if entries[last].command == .stopRumble,
      let set = entries[..<last].lastIndex(where: { $0.command.isSetRumble })
    {
      kept.insert(set)
    }
    return entries.indices.filter { !entries[$0].command.isRumble || kept.contains($0) }
      .map { entries[$0] }
  }
}

/// The gate and controller generations that a feedback was admitted under.
struct VirtualOutputFeedbackGeneration: Equatable, Sendable {
  /// The gate generation.
  var gate: UInt64
  /// The controller generation.
  var controller: UInt64
}

extension ControllerOutputCommand {
  /// Whether the command sets rumble.
  fileprivate var isSetRumble: Bool {
    if case .setRumble = self { return true }
    return false
  }

  /// Whether the command sets or stops rumble.
  fileprivate var isRumble: Bool { isSetRumble || self == .stopRumble }
}
