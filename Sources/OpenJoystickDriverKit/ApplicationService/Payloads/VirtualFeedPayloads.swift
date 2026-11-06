import Foundation

/// One input frame for a virtual feed: the pressed buttons and d-pad directions, the axis values,
/// and how long the frame lasts at least.
///
/// Missing controls are neutral.
///
/// JSON: `{"buttons":["South"],"dpad":["DpadUp"],"axes":{"LeftStickX":0.5},"holdMilliseconds":50}`,
/// with the names of ``Control``, ``RemappingDpadDirection``, and ``RemappingAxis``.
/// Stick axes run from `-1` to `1` with positive Y down; triggers run from `0` to `1`. Values out
/// of range are clamped. Buttons without virtual output, such as paddles, are ignored. Decoding
/// throws on an unknown key and on a button or d-pad direction listed twice.
public struct VirtualFeedFrame: Codable, Equatable, Sendable {
  /// The longest `holdMilliseconds` a frame can ask for.
  public static let maximumHoldMilliseconds = 60_000

  /// The pressed buttons.
  public let buttons: Set<Control>
  /// The pressed d-pad directions.
  public let dpad: Set<RemappingDpadDirection>
  /// The axis values by axis.
  public let axes: [RemappingAxis: Double]
  /// How long the feed shows this frame before the next one, at least
  /// ``VirtualFeedExchangeResult/minimumFrameMilliseconds``; nil shows it until the next frame.
  public let holdMilliseconds: Int?

  /// Creates a frame from its values; missing controls are neutral.
  public init(
    buttons: Set<Control> = [],
    dpad: Set<RemappingDpadDirection> = [],
    axes: [RemappingAxis: Double] = [:],
    holdMilliseconds: Int? = nil
  ) {
    self.buttons = buttons
    self.dpad = dpad
    self.axes = axes
    self.holdMilliseconds = holdMilliseconds
  }

  /// The keys of the JSON encoding.
  private enum CodingKeys: String, CodingKey, CaseIterable {
    /// The `buttons` key.
    case buttons
    /// The `dpad` key.
    case dpad
    /// The `axes` key.
    case axes
    /// The `holdMilliseconds` key.
    case holdMilliseconds
    /// The `apiVersion` key.
    case apiVersion
    /// The `kind` key.
    case kind
  }

  /// The `kind` of a frame that carries the envelope, as the endpoint's frames do.
  public static let kind = "Frame"

  /// Decodes the value from `decoder`.
  public init(from decoder: any Decoder) throws {
    try decoder.rejectUnknownKeys(CodingKeys.self)
    let container = try decoder.container(keyedBy: CodingKeys.self)
    if let apiVersion = try container.decodeIfPresent(String.self, forKey: .apiVersion),
      apiVersion != OpenJoystickDriverAPI.version
    {
      throw DecodingError.dataCorruptedError(
        forKey: .apiVersion,
        in: container,
        debugDescription: "Unsupported apiVersion: \(apiVersion)"
      )
    }
    if let kind = try container.decodeIfPresent(String.self, forKey: .kind), kind != Self.kind {
      throw DecodingError.dataCorruptedError(
        forKey: .kind,
        in: container,
        debugDescription: "Unexpected kind: \(kind)"
      )
    }
    buttons = try Self.decodeUnique(Control.self, forKey: .buttons, in: container)
    dpad = try Self.decodeUnique(RemappingDpadDirection.self, forKey: .dpad, in: container)
    let named = try container.decodeIfPresent([String: Double].self, forKey: .axes) ?? [:]
    axes = try named.reduce(into: [:]) { result, entry in
      guard let axis = RemappingAxis(rawValue: entry.key) else {
        throw DecodingError.dataCorruptedError(
          forKey: .axes,
          in: container,
          debugDescription: "Unknown axis: \(entry.key)"
        )
      }
      result[axis] = entry.value
    }
    holdMilliseconds = try container.decodeIfPresent(Int.self, forKey: .holdMilliseconds)
    if let holdMilliseconds, !(0...Self.maximumHoldMilliseconds).contains(holdMilliseconds) {
      throw DecodingError.dataCorruptedError(
        forKey: .holdMilliseconds,
        in: container,
        debugDescription: "holdMilliseconds is out of range: \(holdMilliseconds)"
      )
    }
  }

  /// Decodes the list under `key` as a set.
  ///
  /// - Throws: `DecodingError.dataCorrupted` when the list names a value twice.
  private static func decodeUnique<Value: Decodable & Hashable>(
    _ type: Value.Type,
    forKey key: CodingKeys,
    in container: KeyedDecodingContainer<CodingKeys>
  ) throws -> Set<Value> {
    let list = try container.decodeIfPresent([Value].self, forKey: key) ?? []
    let values = Set(list)
    guard values.count == list.count else {
      throw DecodingError.dataCorruptedError(
        forKey: key,
        in: container,
        debugDescription: "\(key.stringValue) lists a value twice"
      )
    }
    return values
  }

  /// Encodes the value into `encoder`.
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(buttons.map(\.rawValue).sorted(), forKey: .buttons)
    try container.encode(dpad.map(\.rawValue).sorted(), forKey: .dpad)
    try container.encode(
      Dictionary(uniqueKeysWithValues: axes.map { ($0.key.rawValue, $0.value) }),
      forKey: .axes
    )
    try container.encodeIfPresent(holdMilliseconds, forKey: .holdMilliseconds)
  }

  /// The frame as remapping output; its stick Y points down, as the frame's does.
  public var gamepadState: RemappingGamepadState {
    RemappingGamepadState(buttons: buttons, dpad: dpad, axes: axes)
  }
}

/// One rumble command that the host sent to a virtual gamepad, as a line of `ojd virtual feed` and
/// of the endpoint's feed: the `RumbleCommand` object without its `apiVersion` and `kind`.
///
/// JSON: `{"type":"SetRumble","intensities":{...},"durationMilliseconds":450}` or
/// `{"type":"StopRumble"}`. A `SetRumble` that lasts until the next rumble command has no
/// `durationMilliseconds`. Virtual gamepads receive only rumble commands.
public struct RumbleCommandLine: Encodable, Equatable, Sendable {
  /// The `kind` of the rumble command object.
  public static let kind = "RumbleCommand"

  /// The type of rumble command.
  public enum Kind: String, Encodable, Sendable {
    /// Start rumble with the command's intensities.
    case setRumble = "SetRumble"
    /// Stop all rumble.
    case stopRumble = "StopRumble"
  }

  /// Whether the command starts or stops rumble.
  public let type: Kind
  /// The rumble strengths of a `SetRumble`; nil for `StopRumble`.
  public let intensities: RumbleIntensities?
  /// Nil for a `SetRumble` that is held until the next rumble command, and for `StopRumble`.
  public let durationMilliseconds: Int?

  /// Nil for a command that is not a rumble command.
  public init?(_ command: ControllerOutputCommand) {
    switch command {
    case .setRumble(let intensities, let duration):
      type = .setRumble
      self.intensities = intensities
      if case .milliseconds(let milliseconds) = duration {
        durationMilliseconds = milliseconds
      } else {
        durationMilliseconds = nil
      }
    case .stopRumble:
      type = .stopRumble
      intensities = nil
      durationMilliseconds = nil
    default: return nil
    }
  }
}

/// Arguments of `openVirtualFeed`: the raw identifier of the virtual HID profile to publish, such
/// as `Generic`.
public struct LocalServiceRPCVirtualFeedOpenArguments: Codable, Sendable {
  /// The raw identifier of the virtual HID profile to publish.
  public let profile: String

  /// Creates the arguments for the profile identified by `profile`.
  public init(profile: String) { self.profile = profile }
}

/// Result of `openVirtualFeed`: the token that names the feed in later requests.
public struct VirtualFeedSession: Codable, Equatable, Sendable {
  /// The token that names the feed in later requests.
  public let token: UUID

  /// Creates a session for the feed `token` names.
  public init(token: UUID) { self.token = token }
}

/// Arguments of `exchangeVirtualFeed`: the feed's token and the frames to queue, oldest first.
///
/// No frames keeps the feed open without changing its output.
public struct LocalServiceRPCVirtualFeedExchangeArguments: Codable, Sendable {
  /// The token of the feed.
  public let token: UUID
  /// The frames to queue, oldest first.
  public let frames: [VirtualFeedFrame]

  /// Creates the arguments from a token and frames.
  public init(token: UUID, frames: [VirtualFeedFrame] = []) {
    self.token = token
    self.frames = frames
  }
}

/// Result of `exchangeVirtualFeed`: the output commands the host sent to the virtual device since
/// the previous exchange, oldest first, whether the feed is closed, how many of the sent frames
/// the feed accepted, and how many frames it has not finished showing.
///
/// The feed shows frames in order, each for at least ``minimumFrameMilliseconds``. It queues at
/// most ``maximumQueuedFrames``; send the frames it did not accept again in a later exchange.
/// The service closes a feed that receives no exchange for ``idleTimeoutSeconds``.
public struct VirtualFeedExchangeResult: Codable, Equatable, Sendable {
  /// Seconds without an exchange after which the service closes a feed.
  public static let idleTimeoutSeconds: Double = 2
  /// How often an idle client exchanges to keep its feed open, well inside
  /// ``idleTimeoutSeconds``.
  public static let heartbeatSeconds = 0.5
  /// The most frames a feed queues.
  public static let maximumQueuedFrames = 256
  /// The shortest time a feed shows a frame, in milliseconds.
  public static let minimumFrameMilliseconds = 8

  /// The output commands the host sent to the virtual device since the previous exchange.
  public let feedback: [ControllerOutputCommand]
  /// Whether the feed is closed.
  public let closed: Bool
  /// How many of the sent frames, counted from the first, the feed queued.
  public let accepted: Int
  /// Queued frames plus the frame the feed still shows for its minimum time.
  public let queued: Int

  /// Creates a result from its values.
  public init(feedback: [ControllerOutputCommand], closed: Bool, accepted: Int = 0, queued: Int = 0)
  {
    self.feedback = feedback
    self.closed = closed
    self.accepted = accepted
    self.queued = queued
  }
}

/// Arguments of `closeVirtualFeed`.
public struct LocalServiceRPCVirtualFeedCloseArguments: Codable, Sendable {
  /// The token of the feed to close.
  public let token: UUID

  /// Creates the arguments for the feed `token` names.
  public init(token: UUID) { self.token = token }
}
