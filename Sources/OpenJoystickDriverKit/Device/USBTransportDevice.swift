/// The Apple transport boundary that owns one raw USB service.
public enum USBTransportRoute: String, Hashable, Sendable {
  /// Direct app-side access through the IOUSBHost framework.
  case rawUSB
  /// Access through an entitled USBDriverKit system extension.
  case usbExtension
}

/// The options that a transport session applies before it is exposed to protocol code.
public struct USBTransportOpenOptions: Equatable, Sendable {
  /// The configuration to select with SET_CONFIGURATION, or nil to leave the configuration alone.
  public let configurationValue: UInt8?
  /// The interface to claim.
  public let interfaceNumber: UInt8
  /// The alternate setting to select on the interface.
  public let alternateSetting: UInt8

  /// Creates open options from the configuration, interface and alternate setting.
  public init(
    configurationValue: UInt8? = nil,
    interfaceNumber: UInt8 = 0,
    alternateSetting: UInt8 = 0
  ) {
    self.configurationValue = configurationValue
    self.interfaceNumber = interfaceNumber
    self.alternateSetting = alternateSetting
  }

  /// Creates the open options that `transportProfile` requires.
  ///
  /// The options select configuration 1 only when the profile needs SET_CONFIGURATION.
  public init(transportProfile: DeviceTransportProfile) {
    self.init(
      configurationValue: transportProfile.needsSetConfiguration ? 1 : nil,
      interfaceNumber: transportProfile.interfaceNumber,
      alternateSetting: transportProfile.alternateSetting
    )
  }

  /// Whether this open must send SET_CONFIGURATION to a device whose current configuration is
  /// `current` (nil or 0 when unconfigured).
  ///
  /// Selecting the configuration the device already runs is skipped: SET_CONFIGURATION terminates
  /// every open interface of the device (`IOUSBHostDevice.h`), so a reopened interface would
  /// otherwise end its siblings' sessions.
  public func setsConfiguration(current: UInt8?) -> Bool {
    guard let configurationValue else { return false }
    return configurationValue != current
  }
}

/// One raw USB service as a transport provider enumerates it.
public struct USBTransportDevice: Hashable, Sendable {
  /// The route that owns the service.
  public let route: USBTransportRoute
  /// The registry ID of the service, unique only within its route.
  public let serviceID: UInt64
  /// The vendor ID.
  public let vendorID: UInt16
  /// The product ID.
  public let productID: UInt16
  /// The backend routing value; it is a fallback when the physical location is unknown.
  public let locationID: UInt32
  /// The USB location property observed from the device service, if available.
  public let observedPhysicalLocationIdentifier: UInt32?
  /// The product name string, if the device reports one.
  public let productName: String?
  /// The serial number string, if the device reports one.
  public let serialNumber: String?
  /// The manufacturer string of the device descriptor, if the device reports one.
  public let manufacturer: String?
  /// The device release number (`bcdDevice`), if the device reports one.
  public let deviceRelease: UInt16?

  /// Creates a description of one raw USB service.
  public init(
    route: USBTransportRoute,
    serviceID: UInt64,
    vendorID: UInt16,
    productID: UInt16,
    locationID: UInt32,
    observedPhysicalLocationIdentifier: UInt32? = nil,
    productName: String? = nil,
    serialNumber: String? = nil,
    manufacturer: String? = nil,
    deviceRelease: UInt16? = nil
  ) {
    self.route = route
    self.serviceID = serviceID
    self.vendorID = vendorID
    self.productID = productID
    self.locationID = locationID
    self.observedPhysicalLocationIdentifier = observedPhysicalLocationIdentifier
    self.productName = productName
    self.serialNumber = serialNumber
    self.manufacturer = manufacturer
    self.deviceRelease = deviceRelease
  }

  /// The address of this service.
  public var serviceAddress: ControllerConnectionAddress {
    .usbService(route: route, serviceID: serviceID)
  }
}

/// The transport profile that applies to one admitted USB service and the physical facts observed
/// for it.
public struct USBTransportResolution: Equatable, Sendable {
  /// The transport profile, completed from the observed interfaces when they identify one.
  public let profile: DeviceTransportProfile
  /// The physical facts observed for the service, if any.
  public let physicalDevice: PhysicalDevice?

  /// Creates a resolution from a profile and the facts observed for the service.
  public init(profile: DeviceTransportProfile, physicalDevice: PhysicalDevice? = nil) {
    self.profile = profile
    self.physicalDevice = physicalDevice
  }
}
