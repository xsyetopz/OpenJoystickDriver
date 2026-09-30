import OpenJoystickDriverKit

/// Generic raw USB facade that selects an Apple transport from ownership evidence.
///
/// Accessible vendor-specific interfaces use app-side IOUSBHost. Devices covered
/// by OJD's restricted entitlement, or currently observed behind the DEXT, use
/// USBDriverKit. An open failure never falls through to a
/// different backend.
public actor OpenJoystickDriverUSBTransportProvider: USBTransportProvider,
  USBPhysicalDeviceObservationProvider
{
  private let ioUSBHostProvider: any USBTransportProvider
  private let usbDriverKitProvider: any USBTransportProvider
  private let supportedRawUSBModels: Set<USBTransportModel>
  private let requiredDriverKitModels: Set<USBTransportModel>
  private let ioUSBHostObservation: @Sendable (USBTransportDevice) throws -> PhysicalDevice?
  private var signatureAdmissions: [UInt64: Bool] = [:]
  private let ioUSBHostConfigurationObservation:
    @Sendable (USBTransportDevice, UInt8) throws -> PhysicalDevice?

  public init() {
    ioUSBHostProvider = IOUSBHostTransportProvider()
    usbDriverKitProvider = USBDriverKitTransportProvider()
    supportedRawUSBModels = Set(
      ProtocolDriverRegistry().rawUSBIdentifiers.map(USBTransportModel.init)
    )
    requiredDriverKitModels = Set(
      USBDriverKitExtensionConfiguration.microsoftProductIDs.map {
        USBTransportModel(
          vendorID: USBDriverKitExtensionConfiguration.microsoftVendorID,
          productID: $0
        )
      }
    )
    ioUSBHostObservation = { try PassiveUSBDescriptorProbe.physicalDeviceObservation(for: $0) }
    ioUSBHostConfigurationObservation = Self.readConfigurationObservation
  }

  init(
    ioUSBHostProvider: any USBTransportProvider,
    usbDriverKitProvider: any USBTransportProvider,
    supportedRawUSBModels: Set<USBTransportModel>,
    requiredDriverKitModels: Set<USBTransportModel>,
    ioUSBHostObservation: @escaping @Sendable (USBTransportDevice) throws -> PhysicalDevice? = {
      try PassiveUSBDescriptorProbe.physicalDeviceObservation(for: $0)
    },
    ioUSBHostConfigurationObservation:
      @escaping @Sendable (USBTransportDevice, UInt8) throws -> PhysicalDevice? =
      readConfigurationObservation
  ) {
    self.ioUSBHostProvider = ioUSBHostProvider
    self.usbDriverKitProvider = usbDriverKitProvider
    self.supportedRawUSBModels = supportedRawUSBModels
    self.requiredDriverKitModels = requiredDriverKitModels
    self.ioUSBHostObservation = ioUSBHostObservation
    self.ioUSBHostConfigurationObservation = ioUSBHostConfigurationObservation
  }

  private static func readConfigurationObservation(
    _ device: USBTransportDevice,
    configurationValue: UInt8
  ) throws -> PhysicalDevice? {
    guard
      let descriptor = try IOUSBHostTransportProvider.cachedConfigurationDescriptor(
        of: device,
        configurationValue: configurationValue
      )
    else { return nil }
    return try PassiveUSBDescriptorProbe.physicalDeviceObservation(
      for: device,
      configurationDescriptor: descriptor
    )
  }

  public func devices() async throws -> [USBTransportDevice] {
    let direct: Result<[USBTransportDevice], Error>
    do { direct = .success(try await ioUSBHostProvider.devices()) } catch {
      direct = .failure(error)
    }
    let driverKit: Result<[USBTransportDevice], Error>
    do { driverKit = .success(try await usbDriverKitProvider.devices()) } catch {
      driverKit = .failure(error)
    }

    switch (direct, driverKit) {
    case (.failure(let directError), .failure): throw directError
    case (.success(let directDevices), .success(let driverKitDevices)):
      return Self.selectDevices(
        direct: directDevices,
        driverKit: driverKitDevices,
        supportedRawUSBModels: supportedRawUSBModels,
        requiredDriverKitModels: requiredDriverKitModels,
        signatureServiceIDs: signatureServiceIDs(in: directDevices)
      )
    case (.success(let directDevices), .failure):
      return Self.selectDevices(
        direct: directDevices,
        driverKit: [],
        supportedRawUSBModels: supportedRawUSBModels,
        requiredDriverKitModels: requiredDriverKitModels,
        signatureServiceIDs: signatureServiceIDs(in: directDevices)
      )
    case (.failure, .success(let driverKitDevices)):
      return Self.selectDevices(
        direct: [],
        driverKit: driverKitDevices,
        supportedRawUSBModels: supportedRawUSBModels,
        requiredDriverKitModels: requiredDriverKitModels
      )
    }
  }

  /// Uncatalogued direct devices whose passive facts carry a known Xbox USB signature. The DEXT
  /// matches only catalogued models, so these are reached through IOUSBHost.
  ///
  /// The decision is cached per registry service while it stays enumerated, so each poll does not
  /// re-read every device and a transient read failure cannot drop an admitted device. A negative
  /// decision is cached only once interface facts were observed; a device still being configured
  /// is looked at again.
  private func signatureServiceIDs(in direct: [USBTransportDevice]) -> Set<UInt64> {
    let enumerated = Set(direct.map(\.serviceID))
    signatureAdmissions = signatureAdmissions.filter { enumerated.contains($0.key) }
    var admitted: Set<UInt64> = []
    for device in direct {
      let model = USBTransportModel(device)
      guard !supportedRawUSBModels.contains(model), !requiredDriverKitModels.contains(model) else {
        continue
      }
      if let cached = signatureAdmissions[device.serviceID] {
        if cached { admitted.insert(device.serviceID) }
        continue
      }
      guard let observation = try? ioUSBHostObservation(device),
        observation.serviceIdentity == device.serviceIdentity
      else { continue }
      let carriesSignature = ProtocolDriverRegistry.carriesProtocolSignature(observation)
      if carriesSignature || !(observation.interfaces ?? []).isEmpty {
        signatureAdmissions[device.serviceID] = carriesSignature
      }
      if carriesSignature { admitted.insert(device.serviceID) }
    }
    return admitted
  }

  public func physicalDeviceObservation(for device: USBTransportDevice) async -> PhysicalDevice? {
    switch device.route {
    case .ioUSBHost:
      guard let observation = try? ioUSBHostObservation(device),
        observation.serviceIdentity == device.serviceIdentity
      else { return nil }
      return observation
    case .usbDriverKit: return await usbDriverKitObservation(for: device)
    }
  }

  /// Only IOUSBHost can read the device's configuration; the DEXT route reports no interfaces.
  public func configurationObservation(
    for device: USBTransportDevice,
    configurationValue: UInt8
  ) throws -> PhysicalDevice? {
    guard device.route == .ioUSBHost else { throw USBTransportError.notSupported }
    let observation = try ioUSBHostConfigurationObservation(device, configurationValue)
    return observation?.serviceIdentity == device.serviceIdentity ? observation : nil
  }

  public func open(
    _ device: USBTransportDevice,
    options: USBTransportOpenOptions
  ) async throws -> any USBTransportSession {
    switch device.route {
    case .ioUSBHost: return try await ioUSBHostProvider.open(device, options: options)
    case .usbDriverKit: return try await usbDriverKitProvider.open(device, options: options)
    }
  }

  public func resetDevice(_ device: USBTransportDevice) async throws {
    switch device.route {
    case .ioUSBHost: try await ioUSBHostProvider.resetDevice(device)
    case .usbDriverKit: try await usbDriverKitProvider.resetDevice(device)
    }
  }

  public func resolveTransport(
    for device: USBTransportDevice,
    configured: DeviceTransportProfile
  ) async -> USBTransportResolution {
    await Task.yield()
    switch device.route {
    case .ioUSBHost:
      do {
        guard let observation = try ioUSBHostObservation(device),
          observation.serviceIdentity == device.serviceIdentity
        else { return USBTransportResolution(profile: configured) }
        let profile = Self.resolveTransportProfile(
          route: device.route,
          configured: configured,
          observation: observation
        )
        return USBTransportResolution(profile: profile, physicalDevice: observation)
      } catch {
        // Descriptor access is passive and best-effort. Opening continues with
        // the configured catalog profile when observation fails.
        return USBTransportResolution(profile: configured)
      }
    case .usbDriverKit:
      // DriverKit's service properties provide limited identity/route facts.
      // Do not probe the same service through direct IOUSBHost or infer an
      // interface from the extension's fixed personality.
      guard let observation = await usbDriverKitObservation(for: device) else {
        return USBTransportResolution(profile: configured)
      }
      return USBTransportResolution(profile: configured, physicalDevice: observation)
    }
  }
  static func resolveTransportProfile(
    route: USBTransportRoute,
    configured: DeviceTransportProfile,
    observation: PhysicalDevice?
  ) -> DeviceTransportProfile {
    guard route == .ioUSBHost, let observation else { return configured }
    return USBDescriptorTransportResolver.resolve(configured: configured, observed: observation)
  }

  public func physicalDeviceObservations() async throws -> [PhysicalDevice] {
    // Observation is deliberately best-effort. A descriptor read failure must
    // not change the exact supported-device selection or prevent diagnostics
    // from reporting devices discovered by either backend.
    let devices = try await devices()
    let hasDriverKitDevices = devices.contains { $0.route == .usbDriverKit }
    let driverKitObservations: [PhysicalDevice]
    if hasDriverKitDevices,
      let provider = usbDriverKitProvider as? any USBPhysicalDeviceObservationProvider
    {
      driverKitObservations = (try? await provider.physicalDeviceObservations()) ?? []
    } else {
      driverKitObservations = []
    }

    return devices.compactMap { device in
      switch device.route {
      case .ioUSBHost:
        guard let observation = try? ioUSBHostObservation(device),
          observation.serviceIdentity == device.serviceIdentity
        else { return nil }
        return observation
      case .usbDriverKit:
        return driverKitObservations.first { Self.driverKitObservation($0, matches: device) }
      }
    }
  }

  private func usbDriverKitObservation(for device: USBTransportDevice) async -> PhysicalDevice? {
    guard let provider = usbDriverKitProvider as? any USBPhysicalDeviceObservationProvider,
      let observations = try? await provider.physicalDeviceObservations()
    else { return nil }
    return observations.first { Self.driverKitObservation($0, matches: device) }
  }

  private static func driverKitObservation(
    _ observation: PhysicalDevice,
    matches device: USBTransportDevice
  ) -> Bool {
    observation.serviceIdentity == device.serviceIdentity && observation.vendorID == device.vendorID
      && observation.productID == device.productID && observation.productName == device.productName
      && observation.serialNumber == device.serialNumber
      && observation.physicalLocationIdentifier == device.observedPhysicalLocationIdentifier
  }

  static func selectDevices(
    direct: [USBTransportDevice],
    driverKit: [USBTransportDevice],
    supportedRawUSBModels: Set<USBTransportModel>,
    requiredDriverKitModels: Set<USBTransportModel>,
    signatureServiceIDs: Set<UInt64> = []
  ) -> [USBTransportDevice] {
    let observedDriverKitLocations = Set(driverKit.map(USBTransportLocation.init))
    let selectedDirect = direct.filter { device in
      (supportedRawUSBModels.contains(USBTransportModel(device))
        || signatureServiceIDs.contains(device.serviceID))
        && !requiredDriverKitModels.contains(USBTransportModel(device))
        && !observedDriverKitLocations.contains(USBTransportLocation(device))
    }
    let selectedDriverKit = driverKit.filter {
      supportedRawUSBModels.contains(USBTransportModel($0))
    }
    return (selectedDriverKit + selectedDirect).sorted(by: deviceOrder)
  }

  private static func deviceOrder(_ lhs: USBTransportDevice, _ rhs: USBTransportDevice) -> Bool {
    (lhs.vendorID, lhs.productID, lhs.locationID, lhs.route.rawValue, lhs.serviceID) < (
      rhs.vendorID, rhs.productID, rhs.locationID, rhs.route.rawValue, rhs.serviceID
    )
  }
}

struct USBTransportModel: Hashable, Sendable {
  let vendorID: UInt16
  let productID: UInt16

  init(vendorID: UInt16, productID: UInt16) {
    self.vendorID = vendorID
    self.productID = productID
  }

  init(_ device: USBTransportDevice) {
    self.init(vendorID: device.vendorID, productID: device.productID)
  }

  init(_ identifier: DeviceIdentifier) {
    self.init(
      vendorID: identifier.controllerIdentity.vendorID,
      productID: identifier.controllerIdentity.productID
    )
  }
}

private struct USBTransportLocation: Hashable, Sendable {
  let vendorID: UInt16
  let productID: UInt16
  let locationID: UInt32

  init(_ device: USBTransportDevice) {
    vendorID = device.vendorID
    productID = device.productID
    locationID = device.locationID
  }
}
