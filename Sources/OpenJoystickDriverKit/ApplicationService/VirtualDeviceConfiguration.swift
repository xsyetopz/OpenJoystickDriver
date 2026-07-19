import Foundation

/// Which identity/protocol the user-space Compatibility virtual device should publish.
///
/// IMPORTANT:
/// - `sdl2-3` is the mature SDL path: OJD-owned identity plus
///   an explicit SDL mapping.
/// - `generic-hid` is a plain OJD HID GamePad for consumers that inspect descriptors directly.
/// - `apple-gamecontroller` publishes the HID surface accepted by Apple's GameController.framework.
/// - `xone-hid` and `x360-hid` are hardware-spoof profiles. They are only correct for
///   consumers whose expected descriptor/report layout exactly matches the selected profile.
public enum CompatibilityIdentity: Codable, CaseIterable, Sendable, Equatable {
  case genericHID
  case sdl2_3
  case appleGameController
  case x360HID
  case xoneHID

  public static let allCases: [Self] = [
    .genericHID, .sdl2_3, .appleGameController, .x360HID, .xoneHID,
  ]

  public init?(rawValue: String) {
    switch rawValue {
    case "generic-hid": self = .genericHID
    case "sdl2-3": self = .sdl2_3
    case "apple-gamecontroller": self = .appleGameController
    case "x360-hid": self = .x360HID
    case "xone-hid": self = .xoneHID
    default: return nil
    }
  }

  public var rawValue: String {
    switch self {
    case .genericHID: "generic-hid"
    case .sdl2_3: "sdl2-3"
    case .appleGameController: "apple-gamecontroller"
    case .x360HID: "x360-hid"
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
