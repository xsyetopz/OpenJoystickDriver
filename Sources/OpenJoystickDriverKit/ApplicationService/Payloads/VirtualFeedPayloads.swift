import Foundation

/// One input frame for a virtual feed: the pressed buttons and d-pad directions, the axis
/// values, and how long the frame lasts at least. Missing controls are neutral.
///
/// JSON: `{"buttons":["south"],"dpad":["up"],"axes":{"left_stick_x":0.5},"holdMilliseconds":50}`,
/// with the names of ``RemappingButton``, ``RemappingDpadDirection``, and ``RemappingAxis``.
/// Stick axes run from `-1` to `1` with positive Y up; triggers run from `0` to `1`. Values out
/// of range are clamped. Buttons without virtual output, such as paddles, are ignored.
public struct VirtualFeedFrame: Codable, Equatable, Sendable {
  /// The longest `holdMilliseconds` a frame can ask for.
  public static let maximumHoldMilliseconds = 60_000

  public let buttons: Set<RemappingButton>
  public let dpad: Set<RemappingDpadDirection>
  public let axes: [RemappingAxis: Double]
  /// How long the feed shows this frame before the next one, at least
  /// ``VirtualFeedExchangeResult/minimumFrameMilliseconds``; nil shows it until the next frame.
  public let holdMilliseconds: Int?

  public init(
    buttons: Set<RemappingButton> = [],
    dpad: Set<RemappingDpadDirection> = [],
    axes: [RemappingAxis: Double] = [:],
    holdMilliseconds: Int? = nil
  ) {
    self.buttons = buttons
    self.dpad = dpad
    self.axes = axes
    self.holdMilliseconds = holdMilliseconds
  }

  private enum CodingKeys: String, CodingKey {
    case buttons
    case dpad
    case axes
    case holdMilliseconds
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    buttons = try container.decodeIfPresent(Set<RemappingButton>.self, forKey: .buttons) ?? []
    dpad = try container.decodeIfPresent(Set<RemappingDpadDirection>.self, forKey: .dpad) ?? []
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

  /// The frame as remapping output, whose stick Y points down.
  public var gamepadState: RemappingGamepadState {
    RemappingGamepadState(
      buttons: buttons,
      dpad: dpad,
      axes: axes.reduce(into: [:]) { result, entry in
        let flipsY = entry.key == .leftStickY || entry.key == .rightStickY
        result[entry.key] = flipsY ? -entry.value : entry.value
      }
    )
  }
}

/// Arguments of `openVirtualFeed`: the raw identifier of the virtual HID profile to publish, such
/// as `hid-generic`.
public struct LocalServiceRPCVirtualFeedOpenArguments: Codable, Sendable {
  public let profile: String

  public init(profile: String) { self.profile = profile }
}

/// Result of `openVirtualFeed`: the token that names the feed in later requests.
public struct VirtualFeedSession: Codable, Equatable, Sendable {
  public let token: UUID

  public init(token: UUID) { self.token = token }
}

/// Arguments of `exchangeVirtualFeed`: the feed's token and the frames to queue, oldest first.
/// No frames keeps the feed open without changing its output.
public struct LocalServiceRPCVirtualFeedExchangeArguments: Codable, Sendable {
  public let token: UUID
  public let frames: [VirtualFeedFrame]

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
  public static let idleTimeoutSeconds: Double = 2
  public static let maximumQueuedFrames = 256
  public static let minimumFrameMilliseconds = 8

  public let feedback: [ControllerOutputCommand]
  public let closed: Bool
  /// How many of the sent frames, counted from the first, the feed queued.
  public let accepted: Int
  /// Queued frames plus the frame the feed still shows for its minimum time.
  public let queued: Int

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
  public let token: UUID

  public init(token: UUID) { self.token = token }
}
