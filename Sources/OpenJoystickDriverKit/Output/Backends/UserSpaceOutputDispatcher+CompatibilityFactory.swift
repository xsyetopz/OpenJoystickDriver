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
      return (OJDSDLGamepadFormat(), nil)
    case .appleGameController:
      return (
        Xbox360MacHIDReportFormat(topLevelUsage: UInt8(kHIDUsage_GD_GamePad)),
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
            VirtualRumbleOutputReportParser.xboxGIPReportPayloadSizeWithoutReportID
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
      outputReportPayloadSize: VirtualRumbleOutputReportParser.xboxOneReportPayloadSize
    )
  }
}
