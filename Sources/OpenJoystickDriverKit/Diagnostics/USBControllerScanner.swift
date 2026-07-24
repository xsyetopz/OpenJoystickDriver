import SwiftUSB

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
  public static func scanVendorSpecific() async throws -> [USBControllerDescription] {
    let context = try USBContext()
    var devices: [USBControllerDescription] = []
    let stream = context.findDevices(
      deviceClass: USBConstants.DeviceClass.vendorSpecific.rawValue,
      findAll: true
    )
    for await device in stream {
      let identifier = DeviceIdentifier(vendorID: device.idVendor, productID: device.idProduct)
      let profile = ParserRegistry().runtimeProfile(for: identifier)
      devices.append(
        USBControllerDescription(
          vendorID: device.idVendor,
          productID: device.idProduct,
          bus: String(describing: device.bus),
          address: String(describing: device.address),
          parser: profile.parserName,
          protocolVariant: profile.protocolVariant.rawValue,
          inputEndpoint: String(profile.transportProfile.inputEndpoint, radix: 16),
          outputEndpoint: String(profile.transportProfile.outputEndpoint, radix: 16),
          mappings: profile.mappingFlags
        )
      )
    }
    return devices
  }
}
