/// First-class compatibility profiles exposed by the user-space HID backend.
public struct CompatibilityOutputProfile: Equatable, Sendable {
  public let identity: CompatibilityIdentity
  public let deviceProfile: VirtualDeviceProfile
  public let displayName: String
  public let notes: String
  public let isHardwareSpoof: Bool
  public let emitsXboxGuideReport: Bool

  public init(
    identity: CompatibilityIdentity,
    deviceProfile: VirtualDeviceProfile,
    displayName: String,
    notes: String,
    isHardwareSpoof: Bool,
    emitsXboxGuideReport: Bool
  ) {
    self.identity = identity
    self.deviceProfile = deviceProfile
    self.displayName = displayName
    self.notes = notes
    self.isHardwareSpoof = isHardwareSpoof
    self.emitsXboxGuideReport = emitsXboxGuideReport
  }
}

public enum CompatibilityOutputProfileCatalog {
  public static func profile(for identity: CompatibilityIdentity) -> CompatibilityOutputProfile {
    switch identity {
    case .genericHID:
      CompatibilityOutputProfile(
        identity: identity,
        deviceProfile: .xbox360Wired,
        displayName: "Generic HID",
        notes: "Browser-compatible HID GamePad surface accepted by Apple's GameController stack.",
        isHardwareSpoof: true,
        emitsXboxGuideReport: false
      )
    case .sdl2_3:
      CompatibilityOutputProfile(
        identity: identity,
        deviceProfile: .xbox360Wired,
        displayName: "SDL 2/3",
        notes: "Browser-compatible SDL/Xbox 360 HID surface accepted by Apple's " +
          "GameController stack.",
        isHardwareSpoof: true,
        emitsXboxGuideReport: false
      )
    case .appleGameController:
      CompatibilityOutputProfile(
        identity: identity,
        deviceProfile: .xbox360Wired,
        displayName: "Apple GameController",
        notes: "Xbox-compatible HID surface accepted by Apple's " +
          "GameController.framework as a native GCController.",
        isHardwareSpoof: true,
        emitsXboxGuideReport: false
      )
    case .x360HID:
      CompatibilityOutputProfile(
        identity: identity,
        deviceProfile: .xbox360Wired,
        displayName: "Xbox 360 HID",
        notes: "Xbox 360 HID identity accepted by Apple's Browser/GameController stack.",
        isHardwareSpoof: true,
        emitsXboxGuideReport: false
      )
    case .xoneHID:
      CompatibilityOutputProfile(
        identity: identity,
        deviceProfile: .xboxOneWirelessGameController,
        displayName: "Xbox One HID",
        notes: "Experimental Microsoft hardware-spoof profile for Apple's Xbox One bridge.",
        isHardwareSpoof: true,
        emitsXboxGuideReport: true
      )
    }
  }
}
