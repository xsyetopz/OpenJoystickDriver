public struct USBControllerDescription: Equatable, Sendable {
  public let vendorID: UInt16
  public let productID: UInt16
  public let bus: String
  public let address: String
  public let parser: String
  public let protocolVariant: String
  public let inputEndpoint: String
  public let outputEndpoint: String
  public let mappings: [String]

  public init(
    vendorID: UInt16,
    productID: UInt16,
    bus: String,
    address: String,
    parser: String,
    protocolVariant: String,
    inputEndpoint: String,
    outputEndpoint: String,
    mappings: [String]
  ) {
    self.vendorID = vendorID
    self.productID = productID
    self.bus = bus
    self.address = address
    self.parser = parser
    self.protocolVariant = protocolVariant
    self.inputEndpoint = inputEndpoint
    self.outputEndpoint = outputEndpoint
    self.mappings = mappings
  }
}

public enum USBControllerScanner {
  public static func scanVendorSpecific(using provider: any USBTransportProvider) async throws
    -> [USBControllerDescription]
  { try await provider.devices().map(description) }

  private static func description(for device: USBTransportDevice) -> USBControllerDescription {
    let identifier = DeviceIdentifier(vendorID: device.vendorID, productID: device.productID)
    let profile = ParserRegistry().runtimeProfile(for: identifier)
    return USBControllerDescription(
      vendorID: device.vendorID,
      productID: device.productID,
      bus: device.route.rawValue,
      address: String(device.serviceID),
      parser: profile.parserName,
      protocolVariant: profile.protocolVariant.rawValue,
      inputEndpoint: String(profile.transportProfile.inputEndpoint, radix: 16),
      outputEndpoint: String(profile.transportProfile.outputEndpoint, radix: 16),
      mappings: profile.mappingFlags
    )
  }
}
