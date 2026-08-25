import Foundation

/// Which identity/protocol the user-space Compatibility virtual device should publish.
///
/// IMPORTANT:
/// - `sdl2-3` targets SDL 2/3 applications with an SDL HIDAPI-compatible identity and reports.
/// - `generic-hid` is the fallback for consumers that inspect standard HID descriptors directly.
/// - `apple-gamecontroller` publishes the HID surface accepted by Apple's GameController.framework.
/// - `xone-hid` is an XInput/XUSB-style hardware-spoof profile. It is only correct for
///   consumers whose expected descriptor/report layout exactly matches that profile.
public enum CompatibilityIdentity: Codable, CaseIterable, Sendable, Equatable {
  case genericHID
  case sdl2_3
  case appleGameController
  case xoneHID

  public static let allCases: [Self] = [.genericHID, .sdl2_3, .appleGameController, .xoneHID]

  public init?(rawValue: String) {
    switch rawValue {
    case "generic-hid": self = .genericHID
    case "sdl2-3": self = .sdl2_3
    case "apple-gamecontroller": self = .appleGameController
    case "xone-hid": self = .xoneHID
    default: return nil
    }
  }

  public var rawValue: String {
    switch self {
    case .genericHID: "generic-hid"
    case .sdl2_3: "sdl2-3"
    case .appleGameController: "apple-gamecontroller"
    case .xoneHID: "xone-hid"
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
