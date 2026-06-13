import Foundation
import IOKit.hid

extension UserSpaceOutputDispatcher {
  public static func makeCompatibilityDispatcher(
    identity: CompatibilityIdentity,
    onRumbleCommand: RumbleCommandHandler? = nil
  ) throws -> ForegroundConsumerCompatibilityDispatcherPool {
    let compatibilityProfile = CompatibilityOutputProfileCatalog.profile(for: identity)
    let profile = compatibilityProfile.deviceProfile
    let (format, primaryUsage) = try compatibilityReportFormat(for: identity, profile: profile)

    return try ForegroundConsumerCompatibilityDispatcherPool { routeToken in
      try UserSpaceOutputDispatcher(
        profile: profile,
        format: format,
        primaryUsage: primaryUsage,
        emitsXboxGuideReport: compatibilityProfile.emitsXboxGuideReport,
        routeToken: routeToken,
        onRumbleCommand: onRumbleCommand
      )
    }
  }

  static func compatibilityReportFormat(
    for identity: CompatibilityIdentity,
    profile: VirtualDeviceProfile
  ) throws -> (any VirtualGamepadReportFormat, Int?) {
    switch identity {
    case .genericHID, .sdl2_3:
      return (
        Xbox360SDLHIDReportFormat(),
        Int(kHIDUsage_GD_GamePad)
      )
    case .appleGameController:
      return (
        Xbox360SDLHIDReportFormat(),
        Int(kHIDUsage_GD_GamePad)
      )
    case .xoneHID:
      return (try xboxOneCompatibilityReportFormat(profile: profile), nil)
    case .x360HID:
      return (Xbox360SDLHIDReportFormat(), nil)
    }
  }

  private static func xboxOneCompatibilityReportFormat(
    profile: VirtualDeviceProfile
  ) throws -> any VirtualGamepadReportFormat {
    if let physical = HIDDescriptorReportFormat.copyPhysicalReportDescriptor(
      vendorID: profile.vendorID,
      productID: profile.productID,
      preferredTransport: "USB"
    ) {
      do {
        return try HIDDescriptorReportFormat(
          descriptor: physical,
          outputReportID: VirtualRumbleOutputReportParser.xboxGIPReportID,
          outputReportPayloadSize:
            VirtualRumbleOutputReportParser.xboxGIPReportPayloadSizeWithoutReportID,
          buttonUsageByBit: xboxOneBrowserButtonUsageByBit
        )
      } catch {
        return try fallbackXboxOneCompatibilityReportFormat()
      }
    }
    return try fallbackXboxOneCompatibilityReportFormat()
  }

  private static func fallbackXboxOneCompatibilityReportFormat()
    throws -> any VirtualGamepadReportFormat {
    try HIDDescriptorReportFormat(
      descriptor: XboxOneBluetoothHIDDescriptor.descriptor,
      outputReportID: VirtualRumbleOutputReportParser.xboxOneReportID,
      outputReportPayloadSize: VirtualRumbleOutputReportParser.xboxOneReportPayloadSize,
      buttonUsageByBit: xboxOneBrowserButtonUsageByBit
    )
  }

  /// Safari's Gamepad API maps this Xbox One identity's center buttons before stick clicks.
  /// Swap only the affected logical bits for the Xbox One compatibility identity.
  static let xboxOneBrowserButtonUsageByBit: [Int: Int] = [
    GamepadHIDDescriptor.ButtonBit.leftStick.rawValue: 9,  // L3 -> usage Safari reads as L3.
    GamepadHIDDescriptor.ButtonBit.rightStick.rawValue: 10,  // R3 -> usage Safari reads as R3.
    GamepadHIDDescriptor.ButtonBit.start.rawValue: 8,  // Menu / right center button.
    GamepadHIDDescriptor.ButtonBit.back.rawValue: 7,  // View / left center button.
  ]
}
