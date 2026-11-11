/// A USB device with the protocol and endpoints OJD would use for it.
public struct USBControllerDescription: Equatable, Sendable {
  /// The USB vendor ID.
  public let vendorID: UInt16
  /// The USB product ID.
  public let productID: UInt16
  /// The name of the route that reaches the device.
  public let bus: String
  /// The service ID of the device, as text.
  public let address: String
  /// The family and variant of the catalog record, or of the binding that the interface signature
  /// gives; nil when the model has neither.
  public let protocolBinding: ProtocolBindingID?
  /// The input endpoint address in hex, resolved from the configuration descriptor; nil when no
  /// profile applies.
  public let inputEndpoint: String?
  /// The output endpoint address in hex, resolved from the configuration descriptor; nil when no
  /// profile applies.
  public let outputEndpoint: String?
  /// The entries of the profile's parameters; empty when no profile applies.
  public let parameters: [String]
  /// The passive observation of the device; nil when the provider reports none.
  public let physicalDevice: PhysicalDevice?
  /// How the observed facts classify the device; nil when they lack what a classification needs.
  public let classification: ProtocolClassification?

  /// Creates a description from its values.
  public init(
    vendorID: UInt16,
    productID: UInt16,
    bus: String,
    address: String,
    protocolBinding: ProtocolBindingID?,
    inputEndpoint: String?,
    outputEndpoint: String?,
    parameters: [String],
    physicalDevice: PhysicalDevice? = nil,
    classification: ProtocolClassification? = nil
  ) {
    self.vendorID = vendorID
    self.productID = productID
    self.bus = bus
    self.address = address
    self.protocolBinding = protocolBinding
    self.inputEndpoint = inputEndpoint
    self.outputEndpoint = outputEndpoint
    self.parameters = parameters
    self.physicalDevice = physicalDevice
    self.classification = classification
  }
}

/// A USB provider that also reports passive observations of the attached devices.
public protocol USBPhysicalDeviceObservationProvider: USBTransportProvider {
  /// The passive observations of the attached devices.
  ///
  /// - Throws: The provider's error when it cannot read the devices.
  func physicalDeviceObservations() async throws -> [PhysicalDevice]
}

/// Lists the USB controllers that a provider sees.
public enum USBControllerScanner {
  /// Describes each device of `provider`, with its observation when the provider reports one.
  ///
  /// - Throws: The provider's error when it cannot list the devices or read their observations.
  public static func scanVendorSpecific(
    using provider: any USBTransportProvider
  ) async throws -> [USBControllerDescription] {
    let devices = try await provider.devices()
    let observations: [PhysicalDevice]
    if let observingProvider = provider as? any USBPhysicalDeviceObservationProvider {
      observations = try await observingProvider.physicalDeviceObservations()
    } else {
      observations = []
    }
    let registry = ProtocolDriverRegistry()
    var descriptions: [USBControllerDescription] = []
    for device in devices {
      let physicalDevice = observations.first { $0.serviceAddress == device.serviceAddress }
      // Endpoints are resolved from the device's configuration descriptor, as runtime binding
      // resolves them; the registry never carries endpoint descriptors.
      let configuration =
        device.route == .rawUSB
        ? try? await provider.configurationObservation(for: device, configurationValue: 1) : nil
      descriptions.append(
        description(
          for: device,
          physicalDevice: physicalDevice,
          configuration: configuration,
          registry: registry
        )
      )
    }
    return descriptions
  }

  /// The description of `device`: its catalog record or signature binding, and the endpoints that
  /// the configuration descriptor gives.
  private static func description(
    for device: USBTransportDevice,
    physicalDevice: PhysicalDevice?,
    configuration: PhysicalDevice?,
    registry: ProtocolDriverRegistry
  ) -> USBControllerDescription {
    let record = registry.record(
      for: ControllerModelID(vendorID: device.vendorID, productID: device.productID)
    )
    // An uncatalogued model is admitted by its passive facts, and runtime binding classifies
    // exactly those facts, so its classification needs no completeness gate.
    let classification: ProtocolClassification? = physicalDevice.flatMap { observation in
      guard record == nil || hasCompleteProtocolFacts(observation) else { return nil }
      return registry.classify(observation, backend: DeviceAccessBackend(route: device.route))
    }
    var signatureBinding: ProtocolBinding?
    if record == nil, case .bound(let binding) = classification { signatureBinding = binding }
    let profile = record ?? signatureBinding.flatMap(registry.runtimeProfile(for:))
    let transport = profile.map {
      USBDescriptorTransportResolver.resolve(
        configured: $0.transportProfile,
        observed: configuration ?? physicalDevice
      )
    }
    return USBControllerDescription(
      vendorID: device.vendorID,
      productID: device.productID,
      bus: device.route.rawValue,
      address: String(device.serviceID),
      protocolBinding: record?.rawUSBBinding ?? signatureBinding?.id,
      inputEndpoint: transport.map { String($0.inputEndpoint, radix: 16) },
      outputEndpoint: transport.map { String($0.outputEndpoint, radix: 16) },
      parameters: profile?.parameters.entries ?? [],
      physicalDevice: physicalDevice,
      classification: classification
    )
  }

  /// Whether `device` lists every field of its interfaces and endpoints; an empty interface list
  /// counts as complete.
  private static func hasCompleteProtocolFacts(_ device: PhysicalDevice) -> Bool {
    guard let interfaces = device.interfaces else { return false }
    // The probe preserves nil (configuration unavailable) separately from an
    // observed empty interface list (parsed configuration with no interfaces).
    if interfaces.isEmpty { return true }
    return interfaces.allSatisfy { interface in
      guard interface.interfaceNumber != nil, interface.alternateSetting != nil,
        interface.interfaceClass != nil, interface.interfaceSubclass != nil,
        interface.interfaceProtocol != nil, let endpoints = interface.endpoints
      else { return false }
      return endpoints.allSatisfy {
        $0.address != nil && $0.direction != nil && $0.transferType != nil
      }
    }
  }
}
