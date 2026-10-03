import Foundation

/// One input frame for a virtual feed: the pressed buttons and d-pad directions and the axis
/// values. Missing controls are neutral.
///
/// JSON: `{"buttons":["south"],"dpad":["up"],"axes":{"left_stick_x":0.5,"right_trigger":1}}`,
/// with the names of ``RemappingButton``, ``RemappingDpadDirection``, and ``RemappingAxis``.
/// Stick axes run from `-1` to `1` with positive Y up; triggers run from `0` to `1`. Values out
/// of range are clamped. Buttons without virtual output, such as paddles, are ignored.
public struct VirtualFeedFrame: Codable, Equatable, Sendable {
  public let buttons: Set<RemappingButton>
  public let dpad: Set<RemappingDpadDirection>
  public let axes: [RemappingAxis: Double]

  public init(
    buttons: Set<RemappingButton> = [],
    dpad: Set<RemappingDpadDirection> = [],
    axes: [RemappingAxis: Double] = [:]
  ) {
    self.buttons = buttons
    self.dpad = dpad
    self.axes = axes
  }

  private enum CodingKeys: String, CodingKey {
    case buttons
    case dpad
    case axes
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
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(buttons.map(\.rawValue).sorted(), forKey: .buttons)
    try container.encode(dpad.map(\.rawValue).sorted(), forKey: .dpad)
    try container.encode(
      Dictionary(uniqueKeysWithValues: axes.map { ($0.key.rawValue, $0.value) }),
      forKey: .axes
    )
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

/// Arguments of `exchangeVirtualFeed`: the feed's token and the latest frame. An absent frame
/// keeps the feed open without changing its output.
public struct LocalServiceRPCVirtualFeedExchangeArguments: Codable, Sendable {
  public let token: UUID
  public let frame: VirtualFeedFrame?

  public init(token: UUID, frame: VirtualFeedFrame? = nil) {
    self.token = token
    self.frame = frame
  }
}

/// Result of `exchangeVirtualFeed`: the output commands the host sent to the virtual device since
/// the previous exchange, oldest first, and whether the feed is closed.
///
/// The service closes a feed that receives no exchange for ``idleTimeoutSeconds``.
public struct VirtualFeedExchangeResult: Codable, Equatable, Sendable {
  public static let idleTimeoutSeconds: Double = 2

  public let feedback: [ControllerOutputCommand]
  public let closed: Bool

  public init(feedback: [ControllerOutputCommand], closed: Bool) {
    self.feedback = feedback
    self.closed = closed
  }
}

/// Arguments of `closeVirtualFeed`.
public struct LocalServiceRPCVirtualFeedCloseArguments: Codable, Sendable {
  public let token: UUID

  public init(token: UUID) { self.token = token }
}
