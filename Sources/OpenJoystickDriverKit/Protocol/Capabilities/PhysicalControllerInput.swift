/// Sample formats implemented by the active parser, not a claim of hardware validation.
/// Raw motion means signed, uncalibrated gyroscope and accelerometer vectors.
public struct PhysicalControllerInputCapabilities: Codable, Equatable, Sendable {
  public let rawMotion: Bool
  /// Maximum contacts in one decoded touch frame. Zero means touch decoding is unavailable.
  public let touchContactsPerFrame: UInt8

  /// Additional physical controls exposed by the parser; base gamepad controls remain implicit.
  public let additionalButtons: [Button]
  /// Surface identities emitted by touch samples. An empty list means unspecified or unavailable.
  public let touchSurfaces: [ControllerTouchSurface]

  public init(
    rawMotion: Bool = false,
    touchContactsPerFrame: UInt8 = 0,
    additionalButtons: [Button] = [],
    touchSurfaces: [ControllerTouchSurface] = []
  ) {
    self.rawMotion = rawMotion
    self.touchContactsPerFrame = touchContactsPerFrame
    self.additionalButtons = additionalButtons
    self.touchSurfaces = touchSurfaces
  }

  private enum CodingKeys: String, CodingKey {
    case rawMotion, touchContactsPerFrame, additionalButtons, touchSurfaces
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    rawMotion = try container.decode(Bool.self, forKey: .rawMotion)
    touchContactsPerFrame = try container.decode(UInt8.self, forKey: .touchContactsPerFrame)
    additionalButtons =
      try container.decodeIfPresent([Button].self, forKey: .additionalButtons) ?? []
    touchSurfaces =
      try container.decodeIfPresent([ControllerTouchSurface].self, forKey: .touchSurfaces) ?? []
  }

  public static let none = Self()
}
