public struct USBControllerDescription: Equatable, Sendable {
  public let vendorID: UInt16
  public let productID: UInt16
  public let bus: String
  public let address: String
  public let parser: String
  public let protocolVariant: String
  public let inputEndpoint: String
  public let outputEndpoint: String
  public let quirks: [String]
  public let transportObservation: ControllerTransportObservation?
  public let classification: ProtocolClassification?
  public let reconciliation: ProtocolReconciliation?

  public init(
    vendorID: UInt16,
    productID: UInt16,
    bus: String,
    address: String,
    parser: String,
    protocolVariant: String,
    inputEndpoint: String,
    outputEndpoint: String,
    quirks: [String],
    transportObservation: ControllerTransportObservation? = nil,
    classification: ProtocolClassification? = nil,
    reconciliation: ProtocolReconciliation? = nil
  ) {
    self.vendorID = vendorID
    self.productID = productID
    self.bus = bus
    self.address = address
    self.parser = parser
    self.protocolVariant = protocolVariant
    self.inputEndpoint = inputEndpoint
    self.outputEndpoint = outputEndpoint
    self.quirks = quirks
    self.transportObservation = transportObservation
    self.classification = classification
    self.reconciliation = reconciliation
  }
}

public protocol USBTransportObservationProvider: USBTransportProvider {
  func transportObservations() async throws -> [ControllerTransportObservation]
}

public enum USBControllerScanner {
  public static func scanVendorSpecific(using provider: any USBTransportProvider) async throws
    -> [USBControllerDescription]
  {
    let devices = try await provider.devices()
    let observations: [ControllerTransportObservation]
    if let observingProvider = provider as? any USBTransportObservationProvider {
      observations = try await observingProvider.transportObservations()
    } else {
      observations = []
    }
    return devices.map { device in
      let observation = observations.first {
        $0.vendorID == device.vendorID && $0.productID == device.productID
      }
      return description(for: device, observation: observation)
    }
  }

  private static func description(
    for device: USBTransportDevice,
    observation: ControllerTransportObservation? = nil
  ) -> USBControllerDescription {
    let identifier = DeviceIdentifier(vendorID: device.vendorID, productID: device.productID)
    let profile = ParserRegistry().runtimeProfile(for: identifier)
    let classification = observation.map(USBProtocolClassifier.classify)
    let reconciliation = observation.map {
      KnownRecordProtocolReconciler.reconcile(observation: $0, profile: profile)
    }
    return USBControllerDescription(
      vendorID: device.vendorID,
      productID: device.productID,
      bus: device.route.rawValue,
      address: String(device.serviceID),
      parser: profile.parserName,
      protocolVariant: profile.protocolVariant.rawValue,
      inputEndpoint: String(profile.transportProfile.inputEndpoint, radix: 16),
      outputEndpoint: String(profile.transportProfile.outputEndpoint, radix: 16),
      quirks: profile.quirks,
      transportObservation: observation,
      classification: classification,
      reconciliation: reconciliation
    )
  }
}
