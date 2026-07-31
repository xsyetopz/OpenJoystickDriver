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
    var seenKeys: Set<String> = []

    for await device in context.findDevices(
      deviceClass: USBConstants.DeviceClass.vendorSpecific.rawValue, findAll: true
    ) {
      let key = "\(device.bus):\(device.address)"
      seenKeys.insert(key)
      devices.append(description(for: device))
    }

    // #22: some controllers declare vendor-specific class only on interfaces,
    // so the device-class filter misses them entirely.
    for await device in context.findDevices(deviceClass: 0, findAll: true) {
      let key = "\(device.bus):\(device.address)"
      if seenKeys.contains(key) { continue }
      guard hasVendorSpecificInterface(device) else { continue }
      seenKeys.insert(key)
      devices.append(description(for: device))
    }

    return devices
  }

  private static func description(for device: USBDevice) -> USBControllerDescription {
    let identifier = DeviceIdentifier(vendorID: device.idVendor, productID: device.idProduct)
    let profile = ParserRegistry().runtimeProfile(for: identifier)
    return USBControllerDescription(
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
  }

  private static func hasVendorSpecificInterface(_ device: USBDevice) -> Bool {
    let config: USBConfigurationDescriptor
    do { config = try device.getActiveConfigurationDescriptor() } catch {
      do { config = try device.getConfigurationDescriptor(index: 0) } catch { return false }
    }
    return config.interfaces.contains {
      $0.bInterfaceClass == USBConstants.DeviceClass.vendorSpecific.rawValue
    }
  }
}
