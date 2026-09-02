import Foundation

/// Which identity/protocol the user-space Compatibility virtual device should publish.
///
/// IMPORTANT:
/// - `sdl2-3` targets SDL 2/3 applications with an SDL HIDAPI-compatible identity and reports.
/// - `generic-hid` is the fallback for consumers that inspect standard HID descriptors directly.
/// - `apple-gamecontroller` publishes the HID surface accepted by Apple's GameController.framework.
/// - `xone-hid` is a legacy Xbox One Bluetooth-shaped generic-HID profile. It is not
///   XInputHID, XUSB, or GIP emulation.
/// - `xbox360-hid` is a family-adjacent Xbox 360 HID profile. It is not Windows XUSB.
public enum CompatibilityIdentity: Codable, CaseIterable, Sendable, Equatable {
  case automatic
  case genericHID
  case sdl2_3
  case appleGameController
  /// Legacy persisted identity; use `xbox360-hid` or `apple-gamecontroller` for new selections.
  case xoneHID
  case xbox360HID

  public static let allCases: [Self] = [
    .automatic, .genericHID, .sdl2_3, .appleGameController, .xbox360HID
  ]

  /// The result of validating a persisted/raw identity for a new mutation.
  ///
  /// Legacy values remain decodable so existing persisted settings can still
  /// route through their compatibility backend, but they are not accepted as
  /// new user selections.
  public enum MutationDecision: Equatable, Sendable {
    case accepted(CompatibilityIdentity)
    case rejected(CompatibilityIdentityMutationRejection)
  }

  public func mutationDecision() -> MutationDecision {
    if Self.allCases.contains(self) { return .accepted(self) }
    return .rejected(.legacyIdentityNotSelectable)
  }

  public static func mutationDecision(for rawValue: String) -> MutationDecision {
    guard let identity = Self(rawValue: rawValue) else {
      return .rejected(.unknownIdentity)
    }
    return identity.mutationDecision()
  }

  public init?(rawValue: String) {
    switch rawValue {
    case "automatic": self = .automatic
    case "generic-hid": self = .genericHID
    case "sdl2-3": self = .sdl2_3
    case "apple-gamecontroller": self = .appleGameController
    case "xone-hid": self = .xoneHID
    case "xbox360-hid": self = .xbox360HID
    default: return nil
    }
  }

  public var rawValue: String {
    switch self {
    case .automatic: "automatic"
    case .genericHID: "generic-hid"
    case .sdl2_3: "sdl2-3"
    case .appleGameController: "apple-gamecontroller"
    case .xoneHID: "xone-hid"
    case .xbox360HID: "xbox360-hid"
    }
  }

  public init(from decoder: Decoder) throws {
    let raw = try decoder.singleValueContainer().decode(String.self)
    guard let value = Self(rawValue: raw) else {
      throw DecodingError.dataCorrupted(
        .init(
          codingPath: decoder.codingPath,
          debugDescription: "Unknown compatibility identity: \(raw)"
        )
      )
    }
    self = value
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

public enum CompatibilityIdentityMutationRejection: String, Equatable, Sendable {
  case unknownIdentity
  case legacyIdentityNotSelectable
}
