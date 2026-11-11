/// An open USB session to one controller interface, which a protocol driver reads and writes
/// through.
///
/// Protocol drivers depend on this port instead of a USB library or a DriverKit client. Concrete
/// transports own device discovery, interface claims, pipe lifetimes and platform error
/// translation.
public protocol USBTransportSession: AnyObject, Sendable {
  /// The input ownership that this live session confirmed, not the one discovery inferred.
  var inputOwnership: HIDInputOwnership { get async }

  /// Sends one transfer to a bulk or interrupt OUT endpoint and returns the byte count sent.
  ///
  /// - Parameters:
  ///   - endpoint: The OUT endpoint address.
  ///   - data: The bytes to send.
  ///   - timeout: The time to wait, in milliseconds.
  /// - Returns: The number of bytes sent.
  /// - Throws: ``USBTransportError/notSupported`` when `endpoint` has the IN bit set.
  @discardableResult
  func write(endpoint: UInt8, data: [UInt8], timeout: UInt32) async throws -> Int

  /// Receives one transfer of at most `length` bytes from a bulk or interrupt IN endpoint.
  ///
  /// - Parameters:
  ///   - endpoint: The IN endpoint address.
  ///   - length: The most bytes to receive.
  ///   - timeout: The time to wait, in milliseconds.
  /// - Throws: ``USBTransportError/notSupported`` when `endpoint` lacks the IN bit or `length`
  ///   is not positive.
  /// - Returns: The bytes received, at most `length`.
  func read(endpoint: UInt8, length: Int, timeout: UInt32) async throws -> [UInt8]

  /// Performs one request on the default control endpoint and returns the IN data stage.
  ///
  /// OUT and no-data requests return an empty array.
  ///
  /// - Parameters:
  ///   - request: The setup packet and data stage.
  ///   - timeout: The time to wait, in milliseconds.
  /// - Returns: The IN data stage, or an empty array for an OUT or no-data request.
  /// - Throws: A ``USBTransportError`` when the transfer fails.
  @discardableResult
  func controlTransfer(
    _ request: USBControlTransferRequest,
    timeout: UInt32
  ) async throws -> [UInt8]

  /// Closes this session; closing again has no effect.
  func close() async
}

extension USBTransportSession {
  /// Reports unknown input ownership, for a session that does not observe it.
  public var inputOwnership: HIDInputOwnership { .unknown }
  /// Yields once, for a session that holds no resource to release.
  public func close() async { await Task.yield() }
}

extension USBEndpointDirection {
  /// Decodes the direction bit of a USB endpoint address.
  public init(endpointAddress: UInt8) { self = endpointAddress & 0x80 == 0 ? .out : .in }
}

/// One setup packet and data stage for the default control endpoint.
///
/// The data-stage direction derives from `dataStage`, so a request cannot declare one direction
/// and carry data for the other.
public struct USBControlTransferRequest: Equatable, Sendable {
  /// The request type bits of `bmRequestType`.
  public enum RequestKind: UInt8, Equatable, Sendable {
    /// A request that the USB specification defines.
    case standard = 0x00
    /// A request that a device class defines.
    case `class` = 0x20
    /// A request that the vendor defines.
    case vendor = 0x40
  }

  /// The recipient bits of `bmRequestType`.
  public enum Recipient: UInt8, Equatable, Sendable {
    /// The device.
    case device = 0x00
    /// An interface of the device.
    case interface = 0x01
    /// An endpoint of the device.
    case endpoint = 0x02
    /// Another recipient.
    case other = 0x03
  }

  /// The data stage of a control request.
  public enum DataStage: Equatable, Sendable {
    /// No data stage.
    case none
    /// Host-to-device bytes; the count becomes `wLength`.
    case output([UInt8])
    /// Device-to-host transfer of at most `length` bytes.
    case input(length: UInt16)
  }

  /// The request type bits of `bmRequestType`.
  public let kind: RequestKind
  /// The recipient bits of `bmRequestType`.
  public let recipient: Recipient
  /// The request code (`bRequest`).
  public let request: UInt8
  /// The request value (`wValue`).
  public let value: UInt16
  /// The request index (`wIndex`).
  public let index: UInt16
  /// The data stage of the request.
  public let dataStage: DataStage

  /// Creates a control transfer request.
  ///
  /// - Throws: ``USBTransportError/notSupported`` for OUT data that is empty or longer than
  ///   `UInt16.max`, and for an IN data stage of zero bytes.
  public init(
    kind: RequestKind,
    recipient: Recipient,
    request: UInt8,
    value: UInt16 = 0,
    index: UInt16 = 0,
    dataStage: DataStage = .none
  ) throws {
    switch dataStage {
    case .none: break
    case .output(let data):
      guard !data.isEmpty, data.count <= Int(UInt16.max) else {
        throw USBTransportError.notSupported
      }
    case .input(let length): guard length > 0 else { throw USBTransportError.notSupported }
    }
    self.kind = kind
    self.recipient = recipient
    self.request = request
    self.value = value
    self.index = index
    self.dataStage = dataStage
  }

  /// The direction of the data stage; a request with no data stage counts as OUT.
  public var direction: USBEndpointDirection {
    if case .input = dataStage { return .in }
    return .out
  }

  /// `bmRequestType`: direction, kind and recipient bits.
  public var requestType: UInt8 {
    (direction == .in ? 0x80 : 0x00) | kind.rawValue | recipient.rawValue
  }

  /// The length of the data stage (`wLength`).
  public var length: UInt16 {
    switch dataStage {
    case .none: 0
    case .output(let data): UInt16(data.count)
    case .input(let length): length
    }
  }

  /// Host-to-device data-stage bytes, empty for IN and no-data requests.
  public var outputData: [UInt8] {
    guard case .output(let data) = dataStage else { return [] }
    return data
  }
}

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

/// Discovers and opens physical USB interfaces without exposing a transport framework to Kit.
public protocol USBTransportProvider: Sendable {
  /// Enumerates the raw USB services that this provider can see.
  func devices() async throws -> [USBTransportDevice]
  /// Opens `device` with `options` and returns the session.
  func open(
    _ device: USBTransportDevice,
    options: USBTransportOpenOptions
  ) async throws -> any USBTransportSession

  /// Opens the USB command channel of the controller at `address`, which a HID-bound pipeline uses
  /// to send commands the HID interface cannot carry.
  func openCommandChannel(
    at address: ControllerConnectionAddress,
    model: ControllerModelID,
    options: USBTransportOpenOptions
  ) async throws -> any USBTransportSession

  /// Resolves one admitted device's profile and any available physical facts without claiming the
  /// device.
  func resolveTransport(
    for device: USBTransportDevice,
    configured: DeviceTransportProfile
  ) async -> USBTransportResolution

  /// Passive facts for one enumerated device before any binding exists; nil when unavailable.
  func physicalDeviceObservation(for device: USBTransportDevice) async -> PhysicalDevice?

  /// Passive facts that include the host's cached descriptor of configuration `configurationValue`,
  /// read without claiming an interface or sending SET_CONFIGURATION.
  ///
  /// Returns nil when the device reports no such configuration.
  func configurationObservation(
    for device: USBTransportDevice,
    configurationValue: UInt8
  ) async throws -> PhysicalDevice?

  /// Resets the device's USB port, which makes the host enumerate the device again as a replug
  /// does.
  ///
  /// Every open interface of the device ends, and the device returns as a new attachment.
  func resetDevice(_ device: USBTransportDevice) async throws

  /// The process or driver that holds the device exclusively, as the host reports it, or nil when
  /// the host reports no exclusive owner.
  ///
  /// - Throws: ``USBTransportError/notSupported`` when the provider cannot observe owners.
  func exclusiveOwner(of device: USBTransportDevice) async throws -> String?

  /// Returns once the client that holds interface `interfaceNumber` of `device` exclusively lets go
  /// of it, or the device goes away.
  ///
  /// The platform announces the release; nothing polls.
  func waitForRelease(of device: USBTransportDevice, interfaceNumber: UInt8) async throws
}

extension USBTransportProvider {
  /// Opens the device at an IOKit location through ``open(_:options:)``.
  ///
  /// - Throws: ``USBTransportError/notFound`` for any other address, which has no USB device.
  public func openCommandChannel(
    at address: ControllerConnectionAddress,
    model: ControllerModelID,
    options: USBTransportOpenOptions
  ) async throws -> any USBTransportSession {
    guard case .ioKit(let locationID, _) = address else { throw USBTransportError.notFound }
    let device = USBTransportDevice(
      route: .rawUSB,
      serviceID: 0,
      vendorID: model.vendorID,
      productID: model.productID,
      locationID: locationID
    )
    return try await open(device, options: options)
  }

  /// Keeps the configured transport profile unchanged.
  public func resolveTransport(
    for device: USBTransportDevice,
    configured: DeviceTransportProfile
  ) async -> USBTransportResolution {
    await Task.yield()
    return USBTransportResolution(profile: configured)
  }

  /// Observes no physical device; returns nil.
  public func physicalDeviceObservation(for device: USBTransportDevice) -> PhysicalDevice? { nil }

  /// Reads no configuration descriptor.
  ///
  /// - Throws: ``USBTransportError/notSupported`` always.
  public func configurationObservation(
    for device: USBTransportDevice,
    configurationValue: UInt8
  ) throws -> PhysicalDevice? { throw USBTransportError.notSupported }

  /// Resets no device.
  ///
  /// - Throws: ``USBTransportError/notSupported`` always.
  public func resetDevice(_: USBTransportDevice) throws { throw USBTransportError.notSupported }

  /// Names no exclusive owner.
  ///
  /// - Throws: ``USBTransportError/notSupported`` always.
  public func exclusiveOwner(of device: USBTransportDevice) throws -> String? {
    throw USBTransportError.notSupported
  }

  /// Waits for no release.
  ///
  /// - Throws: ``USBTransportError/notSupported`` always.
  public func waitForRelease(of _: USBTransportDevice, interfaceNumber _: UInt8) throws {
    throw USBTransportError.notSupported
  }
}

/// The stable failure categories that USB transport implementations share.
public enum USBTransportError: Error, Equatable, Sendable {
  /// The transfer timed out.
  case timeout
  /// The device went away.
  case disconnected
  /// The transfer failed with an input/output error.
  case inputOutput
  /// The platform denied access to the device.
  case accessDenied
  /// Another client holds the interface open exclusively.
  ///
  /// `owner` is the interface's `UsbExclusiveOwner` text, or nil when the interface names none.
  case ownedByAnotherClient(owner: String?)
  /// The device, interface or endpoint was not found.
  case notFound
  /// The provider or session does not support the operation.
  case notSupported
  /// A platform error, by its code and message.
  case platform(code: Int32, message: String)

  /// Whether the error is ``timeout``.
  public var isTimeout: Bool { self == .timeout }
  /// Whether the error is ``disconnected``.
  public var isDisconnected: Bool { self == .disconnected }
  /// Whether the error is ``inputOutput``.
  public var isInputOutput: Bool { self == .inputOutput }
}

/// The interface and interrupt endpoint pair that descriptor discovery found.
public struct DiscoveredUSBTransport: Equatable, Sendable {
  /// The interface number.
  public let interfaceNumber: UInt8
  /// The alternate setting.
  public let alternateSetting: UInt8
  /// The address of the interrupt IN endpoint.
  public let inputEndpoint: UInt8
  /// The address of the interrupt OUT endpoint.
  public let outputEndpoint: UInt8

  /// Creates a discovered transport from an interface, an alternate setting and its two endpoints.
  public init(
    interfaceNumber: UInt8,
    alternateSetting: UInt8,
    inputEndpoint: UInt8,
    outputEndpoint: UInt8
  ) {
    self.interfaceNumber = interfaceNumber
    self.alternateSetting = alternateSetting
    self.inputEndpoint = inputEndpoint
    self.outputEndpoint = outputEndpoint
  }
}

/// Completes a transport profile from the interfaces that a device reports.
public enum USBDescriptorTransportResolver {
  /// The first vendor-class or XID-class interface with an interrupt IN and OUT endpoint pair.
  ///
  /// - Parameters:
  ///   - interfaces: The interfaces the device reports.
  ///   - preferredInterface: The interface number a pinned profile names.
  ///   - requirePreferredInterface: Whether only `preferredInterface` qualifies.
  /// - Returns: The interface and endpoints, or nil when no interface qualifies.
  public static func discover(
    interfaces: [PhysicalInterfaceSignature]?,
    preferredInterface: UInt8,
    requirePreferredInterface: Bool
  ) -> DiscoveredUSBTransport? {
    for interface in interfaces ?? [] {
      guard let interfaceNumber = interface.interfaceNumber,
        // Vendor class (XUSB, GIP, vendor protocols) or the original Xbox XID class.
        let alternateSetting = interface.alternateSetting,
        interface.interfaceClass == 0xFF || interface.interfaceClass == 0x58,
        let endpoints = interface.endpoints
      else { continue }
      if requirePreferredInterface && interfaceNumber != preferredInterface { continue }
      guard
        let input = endpoints.first(where: {
          $0.address != nil && $0.transferType == .interrupt && $0.direction == .in
        }),
        let output = endpoints.first(where: {
          $0.address != nil && $0.transferType == .interrupt && $0.direction == .out
        }), let inputAddress = input.address, let outputAddress = output.address
      else { continue }
      return DiscoveredUSBTransport(
        interfaceNumber: interfaceNumber,
        alternateSetting: alternateSetting,
        inputEndpoint: inputAddress,
        outputEndpoint: outputAddress
      )
    }
    return nil
  }

  /// The configured profile completed from the observed interfaces; explicit catalog pins win.
  public static func resolve(
    configured: DeviceTransportProfile,
    observed: PhysicalDevice?
  ) -> DeviceTransportProfile {
    resolve(
      configured: configured,
      discovered: discover(configured: configured, observed: observed)
    )
  }

  /// The first vendor or XID interface with an interrupt IN and OUT pair, honoring a pinned
  /// interface.
  public static func discover(
    configured: DeviceTransportProfile,
    observed: PhysicalDevice?
  ) -> DiscoveredUSBTransport? {
    discover(
      interfaces: observed?.interfaces,
      preferredInterface: configured.interfaceNumber,
      requirePreferredInterface: configured.hasInterfaceOverride
    )
  }

  /// The configured profile completed from `discovered`.
  ///
  /// A pinned endpoint or interface keeps its configured value, and the alternate setting always
  /// comes from `discovered`. Without a discovery the configured profile returns unchanged.
  public static func resolve(
    configured: DeviceTransportProfile,
    discovered: DiscoveredUSBTransport?
  ) -> DeviceTransportProfile {
    guard let discovered else { return configured }
    return DeviceTransportProfile(
      inputEndpoint: configured.hasEndpointOverride
        ? configured.inputEndpoint : discovered.inputEndpoint,
      outputEndpoint: configured.hasEndpointOverride
        ? configured.outputEndpoint : discovered.outputEndpoint,
      interfaceNumber: configured.hasInterfaceOverride
        ? configured.interfaceNumber : discovered.interfaceNumber,
      alternateSetting: discovered.alternateSetting,
      hasInterfaceOverride: configured.hasInterfaceOverride,
      hasEndpointOverride: configured.hasEndpointOverride,
      needsSetConfiguration: configured.needsSetConfiguration,
      postHandshakeSettleNanoseconds: configured.postHandshakeSettleNanoseconds
    )
  }
}
