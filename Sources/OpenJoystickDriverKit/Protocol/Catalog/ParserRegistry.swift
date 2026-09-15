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

  /// Returns the parser name only when the observed transport matches its record.
  public func parserName(
    for identifier: DeviceIdentifier,
    transport: ControllerCatalogTransport
  ) -> String {
    let profile = catalog.runtimeProfile(for: identifier)
    return profile.catalogTransport == transport ? profile.parserName : "GenericHID"
  }

  /// Exact profile-backed HID devices that may not advertise GamePad usage.
  public func hidProfileIdentifiers() -> [DeviceIdentifier] { catalog.hidProfileIdentifiers }

  /// Exact catalog models admitted to the raw USB pipeline.
  public func rawUSBProfileIdentifiers() -> [DeviceIdentifier] { catalog.rawUSBProfileIdentifiers }

  /// Returns parser for given device identifier.
  public func parser(for identifier: DeviceIdentifier) -> any InputParser {
    let profile = catalog.runtimeProfile(for: identifier)
    return parser(
      for: identifier,
      transport: profile.catalogTransport,
      transportProfile: profile.transportProfile
    )
  }

  /// Returns the parser using transport facts resolved from the connected USB device.
  public func parser(
    for identifier: DeviceIdentifier,
    transportProfile: DeviceTransportProfile
  ) -> any InputParser {
    return parser(for: identifier, transport: .usb, transportProfile: transportProfile)
  }

  /// Returns only the parser declared for this exact catalog identity and transport.
  public func parser(
    for identifier: DeviceIdentifier,
    transport: ControllerCatalogTransport,
    transportProfile: DeviceTransportProfile? = nil
  ) -> any InputParser {
    let runtimeProfile = catalog.runtimeProfile(for: identifier)
    guard runtimeProfile.catalogTransport == transport else {
      return GenericHIDParser(identifier: identifier)
    }
    let transportProfile = transportProfile ?? runtimeProfile.transportProfile
    switch catalog.parserName(for: identifier) {
    case "GIP":
      return GIPParser(
        transportProfile: transportProfile,
        startupPackets: runtimeProfile.gipStartupPackets,
        keepAlivePolicy: runtimeProfile.gipKeepAlivePolicy,
        mappingOptions: runtimeProfile.mappingOptions,
        allowsPhysicalOutput: !runtimeProfile.quirks.contains("inputOnly")
      )
    case "GameSir":
      let protocolVariant: GameSirProtocol =
        runtimeProfile.protocolVariant == .gameSirG7ProUSB ? .g7ProUSB : .enhancedHID
      let model: GameSirModel =
        [0x10C5, 0x10C6, 0x10C7, 0x10C8].contains(identifier.productID)
        ? .g7Pro8K : protocolVariant == .g7ProUSB ? .g7Pro : .cyclone2
      return GameSirParser(protocol: protocolVariant, model: model)
    case "DS3": return DS3Parser()
    case "DS4": return DS4Parser()
    case "DualSense":
      return DualSenseParser(hasEdgeButtons: runtimeProfile.quirks.contains("edgeButtons"))
    case "SteamController":
      return SteamControllerParser(
        isWirelessReceiver: runtimeProfile.quirks.contains("wirelessReceiver")
      )
    case "SwitchPro":
      let layout: NintendoControllerLayout
      if runtimeProfile.quirks.contains("joyConLeft") {
        layout = .leftJoyCon
      } else if runtimeProfile.quirks.contains("joyConRight") {
        layout = .rightJoyCon
      } else {
        layout = .pro
      }
      return SwitchProParser(layout: layout)
    case "XboxBluetoothHID": return XboxBluetoothHIDParser()
    case "Flydigi": return FlydigiParser()
    case "FlydigiVendor": return FlydigiVendorParser()
    case "XUSB":
      return Xbox360Parser(
        outEndpoint: transportProfile.outputEndpoint,
        isWirelessReceiver: runtimeProfile.protocolVariant == .xbox360Wireless
      )
    case "XID": return XIDParser(outEndpoint: transportProfile.outputEndpoint)
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

  /// Returns profile-editor capabilities only for an exact catalog identity.
  public func profileCapabilities(
    for identifier: DeviceIdentifier
  ) -> ControllerProfileCapabilities? {
    guard let profile = catalog.exactRuntimeProfile(for: identifier) else { return nil }
    let parser = parser(
      for: identifier,
      transport: profile.catalogTransport,
      transportProfile: profile.transportProfile
    )
    return ControllerProfileCapabilities(parser: parser, mappingOptions: profile.mappingOptions)
  }

  /// Whether an exact catalog record maps this model to a supported raw-USB parser.
  func supportsRawUSBPipeline(for identifier: DeviceIdentifier) -> Bool {
    catalog.supportsRawUSBPipeline(for: identifier)
  }

  /// Returns the suggested virtual device identity for compatibility mode.
  ///
  /// Used only when the user explicitly opts into spoofing IDs for picky consumers.
  public func virtualProfile(for identifier: DeviceIdentifier) -> VirtualDeviceProfile {
    catalog.virtualProfile(for: identifier)
  }
}
