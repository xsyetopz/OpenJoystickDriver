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
    .genericHID,
    .sdl2_3,
    .appleGameController,
    .x360HID,
    .xoneHID,
  ]

  public init?(rawValue: String) {
    switch rawValue {
    case "generic-hid":
      self = .genericHID
    case "sdl2-3":
      self = .sdl2_3
    case "apple-gamecontroller":
      self = .appleGameController
    case "x360-hid":
      self = .x360HID
    case "xone-hid":
      self = .xoneHID
    default:
      return nil
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

  public var disablesDriverKitMirror: Bool {
    switch self {
    case .genericHID, .sdl2_3:
      true
    case .appleGameController:
      false
    case .xoneHID, .x360HID:
      false
    }
  }

  public var seizesDriverKitInCompatibilityMode: Bool {
    true
  }
}

/// Which virtual device output path the application service should actively drive.
///
/// - `auto`: prefer DriverKit, fall back to user-space only if DriverKit output is unstable.
/// - `driverKit`: send reports to the DriverKit dext only.
/// - `compatUserSpace`: create an IOHIDUserDevice and send reports to it only.
/// - `both`: send reports to both (developer-only; can cause double input).
public enum VirtualDeviceMode: String, Codable, CaseIterable, Sendable {
  case auto
  case driverKit
  case compatUserSpace
  case both
}
