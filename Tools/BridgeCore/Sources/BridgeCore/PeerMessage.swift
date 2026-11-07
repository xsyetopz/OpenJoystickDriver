import Foundation

/// Checks the messages that a peer sends over the data channel.
///
/// The peer is not trusted: a message that is too long, is not JSON, or does not have the shape of
/// its endpoint line is dropped, and a message that passes is rebuilt from the checked fields.
public enum PeerMessage {
  /// The longest message the bridge reads, and the longest signaling blob.
  public static let maximumBytes = 64 * 1024
  /// The longest `holdMilliseconds` of a `Frame`, as in `Resources/Schemas/endpoint.schema.json`.
  public static let maximumHoldMilliseconds = 60_000
  /// The longest `durationMilliseconds` of a `SetRumble`, as in `cli-output.schema.json`.
  public static let maximumRumbleMilliseconds = 5000

  /// The control ids of `Resources/Schemas/vocabulary.schema.json` that a `Frame` lists as buttons.
  ///
  /// These are every control but the D-pad directions and the stick axes, which `dpad` and `axes`
  /// carry. `PeerMessageTests` fails when this list and the schema differ.
  static let buttons: Set<String> = [
    "South", "East", "West", "North", "LeftShoulder", "RightShoulder", "LeftTrigger",
    "RightTrigger", "Back", "Start", "LeftStickClick", "RightStickClick", "Guide", "Capture",
    "Microphone", "TouchpadClick", "LeftPaddle1", "LeftPaddle2", "RightPaddle1", "RightPaddle2",
    "Auxiliary1", "Auxiliary2", "Auxiliary3", "Auxiliary4", "Auxiliary5", "Auxiliary6",
    "Auxiliary7", "Auxiliary8", "LeftStickTouch", "RightStickTouch", "LeftTrackpadClick",
    "RightTrackpadClick", "LeftTrackpadTouch", "RightTrackpadTouch", "PointerX", "PointerY",
    "PointerTracking",
  ]
  /// The D-pad directions that a `Frame` lists in `dpad`.
  static let dpad: Set<String> = ["DpadUp", "DpadDown", "DpadLeft", "DpadRight"]
  /// The stick and trigger axes that a `Frame` lists in `axes`.
  static let axes: Set<String> = [
    "LeftStickX", "LeftStickY", "RightStickX", "RightStickY", "LeftTrigger", "RightTrigger",
  ]
  /// The members that a `Frame` line may have.
  private static let frameKeys: Set<String> = [
    "apiVersion", "kind", "buttons", "dpad", "axes", "holdMilliseconds",
  ]
  /// The six intensities that a `SetRumble` command has all of.
  private static let intensities: Set<String> = [
    "lowFrequency", "highFrequency", "leftTrigger", "rightTrigger", "leftHaptic", "rightHaptic",
  ]
  /// The members that a `RumbleCommand` line may have.
  private static let rumbleKeys: Set<String> = [
    "apiVersion", "kind", "type", "intensities", "durationMilliseconds",
  ]

  /// The `Frame` in the message, or nil when the message is not a valid `Frame`.
  public static func frame(from data: Data) -> [String: Any]? {
    guard let line = object(from: data), keys(of: line, within: frameKeys), header(line, "Frame")
    else { return nil }
    var frame: [String: Any] = ["apiVersion": endpointAPIVersion, "kind": "Frame"]
    if let value = line["buttons"] {
      guard let names = unique(value, within: buttons) else { return nil }
      frame["buttons"] = names
    }
    if let value = line["dpad"] {
      guard let names = unique(value, within: dpad) else { return nil }
      frame["dpad"] = names
    }
    if let value = line["axes"] {
      guard let object = value as? [String: Any], Set(object.keys).isSubset(of: axes) else {
        return nil
      }
      var checked: [String: Double] = [:]
      for (name, number) in object {
        guard let number = real(number) else { return nil }
        checked[name] = number
      }
      frame["axes"] = checked
    }
    if let value = line["holdMilliseconds"] {
      guard let hold = integer(value), (0...maximumHoldMilliseconds).contains(hold) else {
        return nil
      }
      frame["holdMilliseconds"] = hold
    }
    return frame
  }

  /// The `RumbleCommand` in the message, or nil when the message is not a valid one.
  ///
  /// The shape is that of `sharedVirtualFeedLine` in `Resources/Schemas/cli-output.schema.json`:
  /// `SetRumble` has all six intensities and an optional duration of 0 to 5000 ms, and `StopRumble`
  /// has no member besides the header and `type`.
  public static func rumble(from data: Data) -> [String: Any]? {
    guard let line = object(from: data), keys(of: line, within: rumbleKeys),
      header(line, "RumbleCommand"), let type = line["type"] as? String
    else { return nil }
    var command: [String: Any] = [
      "apiVersion": endpointAPIVersion, "kind": "RumbleCommand", "type": type,
    ]
    switch type {
    case "StopRumble":
      return line.count == 3 ? command : nil
    case "SetRumble":
      guard let object = line["intensities"] as? [String: Any], Set(object.keys) == intensities
      else { return nil }
      var checked: [String: Int] = [:]
      for (name, number) in object {
        guard let level = integer(number), (0...65535).contains(level) else { return nil }
        checked[name] = level
      }
      command["intensities"] = checked
      if let value = line["durationMilliseconds"] {
        guard let duration = integer(value), (0...maximumRumbleMilliseconds).contains(duration)
        else { return nil }
        command["durationMilliseconds"] = duration
      }
      return command
    default:
      return nil
    }
  }

  /// The JSON object in `data`, or nil when it is too long or is not a JSON object.
  private static func object(from data: Data) -> [String: Any]? {
    guard data.count <= maximumBytes else { return nil }
    return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
  }

  /// Whether every member name of the line is in `allowed`.
  private static func keys(of line: [String: Any], within allowed: Set<String>) -> Bool {
    Set(line.keys).isSubset(of: allowed)
  }

  /// Whether the line has the endpoint `apiVersion` and the given `kind`.
  private static func header(_ line: [String: Any], _ kind: String) -> Bool {
    line["apiVersion"] as? String == endpointAPIVersion && line["kind"] as? String == kind
  }

  /// The names in the value, or nil unless they are distinct strings that are in `allowed`.
  private static func unique(_ value: Any, within allowed: Set<String>) -> [String]? {
    guard let names = value as? [String], Set(names).count == names.count,
      Set(names).isSubset(of: allowed)
    else { return nil }
    return names
  }

  /// Whether the value is a JSON boolean, which Foundation also bridges to a number.
  private static func isBoolean(_ value: Any) -> Bool {
    CFGetTypeID(value as AnyObject) == CFBooleanGetTypeID()
  }

  /// The finite number in the value, or nil for a boolean, a string or a non-finite number.
  private static func real(_ value: Any) -> Double? {
    guard !isBoolean(value), let double = value as? Double, double.isFinite else { return nil }
    return double
  }

  /// The whole number in the value that is below 1e15 in magnitude, or nil.
  private static func integer(_ value: Any) -> Int? {
    guard let double = real(value), double == double.rounded(), abs(double) < 1e15 else {
      return nil
    }
    return Int(double)
  }
}

/// Holds the newest `Frame` of the peer for the one thread that sends to the endpoint.
///
/// A frame that is replaced before it is taken is dropped, so a peer that sends faster than the
/// endpoint plays cannot fill the endpoint's queue.
public final class FrameMailbox: @unchecked Sendable {
  /// Guards `pending` and wakes a waiting `next(timeout:)` when a frame is posted.
  private let condition = NSCondition()
  /// The newest posted frame that no `next(timeout:)` has taken.
  private var pending: [String: Any]?

  /// Creates a mailbox with no frame.
  public init() {}

  /// Posts a frame in place of the one that waits.
  ///
  /// It holds the lock only to store the frame, so it can run on the WebRTC callback thread.
  public func post(_ frame: [String: Any]) {
    condition.lock()
    pending = frame
    condition.signal()
    condition.unlock()
  }

  /// Takes the newest posted frame, waiting up to `timeout` seconds for one.
  ///
  /// The frame is checked under the lock that `post` takes, so a post that races the timeout is
  /// returned, not lost, and leaves nothing behind that would end a later wait early.
  ///
  /// - Returns: The frame, or nil when none is posted within `timeout`.
  public func next(timeout: TimeInterval) -> [String: Any]? {
    let deadline = Date(timeIntervalSinceNow: timeout)
    condition.lock()
    defer { condition.unlock() }
    while pending == nil {
      if !condition.wait(until: deadline) { break }
    }
    let frame = pending
    pending = nil
    return frame
  }
}
