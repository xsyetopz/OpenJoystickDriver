import Foundation

/// Dispatches controllers to appropriate parser
/// by VID/PID lookup.
public final class ParserRegistry: Sendable {
  private let catalog = DeviceCatalog()

  /// Creates a new ParserRegistry.
  public init() {}

  /// Returns parser name for given device identifier.
  public func parserName(for identifier: DeviceIdentifier) -> String {
    catalog.parserName(for: identifier)
  }

  /// Exact profile-backed HID devices that may not advertise GamePad usage.
  public func hidProfileIdentifiers() -> [DeviceIdentifier] { catalog.hidProfileIdentifiers }

  /// Returns parser for given device identifier.
  public func parser(for identifier: DeviceIdentifier) -> any InputParser {
    parser(for: identifier, transportProfile: catalog.transportProfile(for: identifier))
  }

  /// Returns the parser using transport facts resolved from the connected USB device.
  public func parser(for identifier: DeviceIdentifier, transportProfile: DeviceTransportProfile)
    -> any InputParser
  {
    let runtimeProfile = catalog.runtimeProfile(for: identifier)
    switch catalog.parserName(for: identifier) {
    case "GIP":
      return GIPParser(
        transportProfile: transportProfile,
        startupPackets: runtimeProfile.gipStartupPackets
      )
    case "DS3": return DS3Parser()
    case "DS4": return DS4Parser()
    case "DualSense": return DualSenseParser()
    case "SteamController":
      return SteamControllerParser(
        isWirelessReceiver: runtimeProfile.mappingFlags.contains("wirelessReceiver")
      )
    case "SwitchPro": return SwitchProParser()
    case "Xbox360":
      return Xbox360Parser(
        outEndpoint: transportProfile.outputEndpoint,
        isWirelessReceiver: runtimeProfile.protocolVariant == .xbox360Wireless
      )
    default: return GenericHIDParser(identifier: identifier)
    }
  }

  /// Returns the physical transport profile for given device identifier.
  public func transportProfile(for identifier: DeviceIdentifier) -> DeviceTransportProfile {
    catalog.transportProfile(for: identifier)
  }

  /// Returns the complete runtime profile for a physical controller model.
  public func runtimeProfile(for identifier: DeviceIdentifier) -> DeviceRuntimeProfile {
    catalog.runtimeProfile(for: identifier)
  }

  /// Returns the suggested virtual device identity for compatibility mode.
  ///
  /// Used only when the user explicitly opts into spoofing IDs for picky consumers.
  public func virtualProfile(for identifier: DeviceIdentifier) -> VirtualDeviceProfile {
    catalog.virtualProfile(for: identifier)
  }
}
