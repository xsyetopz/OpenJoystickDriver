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
  /// The provider of the raw USB route, backed by IOUSBHost.
  private let ioUSBHostProvider: any USBTransportProvider
  /// The provider of the extension route, backed by the USBDriverKit extension.
  private let usbDriverKitProvider: any USBTransportProvider
  /// Reads the catalog's raw-USB models; the service changes them when user records change.
  private let rawUSBModels: @Sendable () -> Set<ControllerModelID>
  /// The catalog's raw-USB models, read afresh on each use.
  private var supportedRawUSBModels: Set<ControllerModelID> { rawUSBModels() }
  /// The models that only the extension route may serve.
  private let requiredDriverKitModels: Set<ControllerModelID>
  /// Reads the passive USB observation of a raw USB device.
  private let ioUSBHostObservation: @Sendable (USBTransportDevice) throws -> PhysicalDevice?
  /// The signature decision per registry service ID, kept while the service stays enumerated.
  private var signatureAdmissions: [UInt64: Bool] = [:]
  /// Reads the passive USB observation of a raw USB device for one configuration value.
  private let ioUSBHostConfigurationObservation:
    @Sendable (USBTransportDevice, UInt8) throws -> PhysicalDevice?

  /// The models OJD's restricted entitlement covers, which only the DEXT route may serve.
  static let driverKitRequiredModels = Set(
    USBDriverKitExtensionConfiguration.microsoftProductIDs.map {
      ControllerModelID(
        vendorID: USBDriverKitExtensionConfiguration.microsoftVendorID,
        productID: $0
      )
    }
  )

  /// Creates the facade over the IOUSBHost and USBDriverKit providers and the protocol driver
  /// registry's raw USB models.
  public init() {
    ioUSBHostProvider = IOUSBHostTransportProvider()
    usbDriverKitProvider = USBDriverKitTransportProvider()
    let registry = ProtocolDriverRegistry()
    rawUSBModels = { Set(registry.rawUSBModels) }
    requiredDriverKitModels = Self.driverKitRequiredModels
    ioUSBHostObservation = { try PassiveUSBDescriptorProbe.physicalDeviceObservation(for: $0) }
    ioUSBHostConfigurationObservation = Self.readConfigurationObservation
  }

  /// Creates the facade over the given providers, models and observation readers.
  init(
    ioUSBHostProvider: any USBTransportProvider,
    usbDriverKitProvider: any USBTransportProvider,
    supportedRawUSBModels: Set<ControllerModelID>,
    requiredDriverKitModels: Set<ControllerModelID>,
    ioUSBHostObservation: @escaping @Sendable (USBTransportDevice) throws -> PhysicalDevice? = {
      try PassiveUSBDescriptorProbe.physicalDeviceObservation(for: $0)
    },
    ioUSBHostConfigurationObservation:
      @escaping @Sendable (USBTransportDevice, UInt8) throws -> PhysicalDevice? =
      readConfigurationObservation
  ) {
    self.ioUSBHostProvider = ioUSBHostProvider
    self.usbDriverKitProvider = usbDriverKitProvider
    rawUSBModels = { supportedRawUSBModels }
    self.requiredDriverKitModels = requiredDriverKitModels
    self.ioUSBHostObservation = ioUSBHostObservation
    self.ioUSBHostConfigurationObservation = ioUSBHostConfigurationObservation
  }

  /// Reads the cached configuration descriptor `configurationValue` of `device` into an
  /// observation.
  ///
  /// Returns nil when the device has no such cached descriptor.
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

  /// Lists the devices that OJD serves, from both providers, in vendor, product, location, route
  /// and service order.
  ///
  /// A provider that fails is skipped when the other one answers.
  ///
  /// - Throws: The error of the IOUSBHost provider when both providers fail.
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

  /// Uncatalogued direct devices whose passive facts carry a known Xbox USB signature.
  ///
  /// The DEXT matches only catalogued models, so these are reached through IOUSBHost.
  ///
  /// The decision is cached per registry service while it stays enumerated, so each poll does not
  /// re-read every device and a transient read failure cannot drop an admitted device. A negative
  /// decision is cached only once interface facts were observed; a device still being configured
  /// is looked at again.
  private func signatureServiceIDs(in direct: [USBTransportDevice]) -> Set<UInt64> {
    let enumerated = Set(direct.map(\.serviceID))
    signatureAdmissions = signatureAdmissions.filter { enumerated.contains($0.key) }
    var admitted: Set<UInt64> = []
    let supportedRawUSBModels = supportedRawUSBModels
    for device in direct {
      let model = ControllerModelID(device)
      guard !supportedRawUSBModels.contains(model), !requiredDriverKitModels.contains(model) else {
        continue
      }
      if let cached = signatureAdmissions[device.serviceID] {
        if cached { admitted.insert(device.serviceID) }
        continue
      }
      guard let observation = try? ioUSBHostObservation(device),
        observation.serviceAddress == device.serviceAddress
      else { continue }
      let carriesSignature = ProtocolDriverRegistry.carriesProtocolSignature(observation)
      if carriesSignature || !(observation.interfaces ?? []).isEmpty {
        signatureAdmissions[device.serviceID] = carriesSignature
      }
      if carriesSignature { admitted.insert(device.serviceID) }
    }
    return admitted
  }

  /// Returns the passive observation of `device` from the provider of its route, or nil when none
  /// matches the device's service address.
  public func physicalDeviceObservation(for device: USBTransportDevice) async -> PhysicalDevice? {
    switch device.route {
    case .rawUSB:
      guard let observation = try? ioUSBHostObservation(device),
        observation.serviceAddress == device.serviceAddress
      else { return nil }
      return observation
    case .usbExtension: return await usbDriverKitObservation(for: device)
    }
  }

  /// Only IOUSBHost can read the device's configuration; the DEXT route reports no interfaces.
  public func configurationObservation(
    for device: USBTransportDevice,
    configurationValue: UInt8
  ) throws -> PhysicalDevice? {
    guard device.route == .rawUSB else { throw USBTransportError.notSupported }
    let observation = try ioUSBHostConfigurationObservation(device, configurationValue)
    return observation?.serviceAddress == device.serviceAddress ? observation : nil
  }

  /// Opens `device` through the provider of its route.
  ///
  /// - Throws: The error of that provider. A failed open is not retried on the other route.
  public func open(
    _ device: USBTransportDevice,
    options: USBTransportOpenOptions
  ) async throws -> any USBTransportSession {
    switch device.route {
    case .rawUSB: return try await ioUSBHostProvider.open(device, options: options)
    case .usbExtension: return try await usbDriverKitProvider.open(device, options: options)
    }
  }

  /// Only IOUSBHost devices report an exclusive owner; the DEXT route has none.
  public func exclusiveOwner(of device: USBTransportDevice) async throws -> String? {
    guard device.route == .rawUSB else { throw USBTransportError.notSupported }
    return try await ioUSBHostProvider.exclusiveOwner(of: device)
  }

  /// Resets `device` through the provider of its route.
  ///
  /// - Throws: The error of that provider.
  public func resetDevice(_ device: USBTransportDevice) async throws {
    switch device.route {
    case .rawUSB: try await ioUSBHostProvider.resetDevice(device)
    case .usbExtension: try await usbDriverKitProvider.resetDevice(device)
    }
  }

  /// Both routes watch the interface's `IOUSBHostInterface` service: a DEXT route's failed open
  /// leaves the same registry entry held by the other client.
  public func waitForRelease(of device: USBTransportDevice, interfaceNumber: UInt8) async throws {
    try await IOUSBHostTransportProvider.waitForRelease(
      of: device,
      interfaceNumber: interfaceNumber
    )
  }

  /// Returns the transport profile to use for `device`, with the observation it is based on.
  ///
  /// A raw USB device takes the profile that its observed descriptors resolve to. An extension
  /// device keeps `configured`. A failed or mismatched observation also keeps `configured`.
  public func resolveTransport(
    for device: USBTransportDevice,
    configured: DeviceTransportProfile
  ) async -> USBTransportResolution {
    await Task.yield()
    switch device.route {
    case .rawUSB:
      do {
        guard let observation = try ioUSBHostObservation(device),
          observation.serviceAddress == device.serviceAddress
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
    case .usbExtension:
      // DriverKit's service properties provide limited identity/route facts.
      // Do not probe the same service through direct IOUSBHost or infer an
      // interface from the extension's fixed personality.
      guard let observation = await usbDriverKitObservation(for: device) else {
        return USBTransportResolution(profile: configured)
      }
      return USBTransportResolution(profile: configured, physicalDevice: observation)
    }
  }
  /// Returns `configured` unless `route` is raw USB and `observation` is present, in which case the
  /// descriptors resolve the profile.
  static func resolveTransportProfile(
    route: USBTransportRoute,
    configured: DeviceTransportProfile,
    observation: PhysicalDevice?
  ) -> DeviceTransportProfile {
    guard route == .rawUSB, let observation else { return configured }
    return USBDescriptorTransportResolver.resolve(configured: configured, observed: observation)
  }

  /// Returns the observations of the listed devices.
  ///
  /// A device whose observation cannot be read is left out, without failing the others.
  ///
  /// - Throws: The error of ``devices()``.
  public func physicalDeviceObservations() async throws -> [PhysicalDevice] {
    // Observation is deliberately best-effort. A descriptor read failure must
    // not change the exact supported-device selection or prevent diagnostics
    // from reporting devices discovered by either backend.
    let devices = try await devices()
    let hasDriverKitDevices = devices.contains { $0.route == .usbExtension }
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
      case .rawUSB:
        guard let observation = try? ioUSBHostObservation(device),
          observation.serviceAddress == device.serviceAddress
        else { return nil }
        return observation
      case .usbExtension:
        return driverKitObservations.first { Self.driverKitObservation($0, matches: device) }
      }
    }
  }

  /// Returns the extension provider's observation that matches `device`, or nil when none does.
  private func usbDriverKitObservation(for device: USBTransportDevice) async -> PhysicalDevice? {
    guard let provider = usbDriverKitProvider as? any USBPhysicalDeviceObservationProvider,
      let observations = try? await provider.physicalDeviceObservations()
    else { return nil }
    return observations.first { Self.driverKitObservation($0, matches: device) }
  }

  /// Tells whether `observation` is the same device as `device`: the same service address, IDs,
  /// names, serial number and location.
  private static func driverKitObservation(
    _ observation: PhysicalDevice,
    matches device: USBTransportDevice
  ) -> Bool {
    observation.serviceAddress == device.serviceAddress && observation.vendorID == device.vendorID
      && observation.productID == device.productID && observation.productName == device.productName
      && observation.serialNumber == device.serialNumber
      && observation.physicalLocationIdentifier == device.observedPhysicalLocationIdentifier
  }

  /// Selects the devices that OJD serves from the two routes' lists.
  ///
  /// A raw USB device is selected when its model is in the catalog or its service ID is in
  /// `signatureServiceIDs`, its model is not extension-only, and the extension does not list its
  /// location. An extension device is selected when its model is in the catalog.
  static func selectDevices(
    direct: [USBTransportDevice],
    driverKit: [USBTransportDevice],
    supportedRawUSBModels: Set<ControllerModelID>,
    requiredDriverKitModels: Set<ControllerModelID>,
    signatureServiceIDs: Set<UInt64> = []
  ) -> [USBTransportDevice] {
    let observedDriverKitLocations = Set(driverKit.map(USBTransportLocation.init))
    let selectedDirect = direct.filter { device in
      (supportedRawUSBModels.contains(ControllerModelID(device))
        || signatureServiceIDs.contains(device.serviceID))
        && !requiredDriverKitModels.contains(ControllerModelID(device))
        && !observedDriverKitLocations.contains(USBTransportLocation(device))
    }
    let selectedDriverKit = driverKit.filter {
      supportedRawUSBModels.contains(ControllerModelID($0))
    }
    return (selectedDriverKit + selectedDirect).sorted(by: deviceOrder)
  }

  /// Orders devices by vendor, product, location, route and service ID.
  private static func deviceOrder(_ lhs: USBTransportDevice, _ rhs: USBTransportDevice) -> Bool {
    (lhs.vendorID, lhs.productID, lhs.locationID, lhs.route.rawValue, lhs.serviceID) < (
      rhs.vendorID, rhs.productID, rhs.locationID, rhs.route.rawValue, rhs.serviceID
    )
  }
}

extension ControllerModelID {
  /// The model of a USB device.
  init(_ device: USBTransportDevice) {
    self.init(vendorID: device.vendorID, productID: device.productID)
  }
}

/// The vendor, product and location that identify where a device sits.
private struct USBTransportLocation: Hashable, Sendable {
  /// The USB vendor ID.
  let vendorID: UInt16
  /// The USB product ID.
  let productID: UInt16
  /// The USB location ID.
  let locationID: UInt32

  /// Creates the location of `device`.
  init(_ device: USBTransportDevice) {
    vendorID = device.vendorID
    productID = device.productID
    locationID = device.locationID
  }
}
