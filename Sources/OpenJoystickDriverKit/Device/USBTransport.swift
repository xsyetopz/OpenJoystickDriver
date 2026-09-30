/// An open physical USB controller session used by protocol implementations.
///
/// The semantic controller layer depends on this port rather than a particular
/// USB library or DriverKit client. Concrete transports own device discovery,
/// interface claims, pipe lifetimes, and platform error translation.
public protocol USBTransportSession: AnyObject, Sendable {
  /// Ownership confirmed by this live transport session, rather than by discovery.
  var inputOwnership: HIDInputOwnership { get async }

  /// Sends one transfer to a bulk or interrupt OUT endpoint and returns the byte count sent.
  ///
  /// `timeout` is in milliseconds. An endpoint address with the IN bit set throws
  /// `USBTransportError.notSupported`.
  @discardableResult
  func write(endpoint: UInt8, data: [UInt8], timeout: UInt32) async throws -> Int

  /// Receives one transfer of at most `length` bytes from a bulk or interrupt IN endpoint.
  ///
  /// `timeout` is in milliseconds. An endpoint address without the IN bit, or a
  /// non-positive length, throws `USBTransportError.notSupported`.
  func read(endpoint: UInt8, length: Int, timeout: UInt32) async throws -> [UInt8]

  /// Performs one request on the default control endpoint and returns the IN data stage.
  ///
  /// `timeout` is in milliseconds. OUT and no-data requests return an empty array.
  @discardableResult
  func controlTransfer(
    _ request: USBControlTransferRequest,
    timeout: UInt32
  ) async throws -> [UInt8]

  /// Closes this exact device session idempotently.
  func close() async
}

extension USBTransportSession {
  public var inputOwnership: HIDInputOwnership { .unknown }
  public func close() async { await Task.yield() }
}

extension USBEndpointDirection {
  /// Decodes the direction bit of a USB endpoint address.
  public init(endpointAddress: UInt8) { self = endpointAddress & 0x80 == 0 ? .out : .in }
}

/// One typed setup packet and data stage for the default control endpoint.
///
/// The data-stage direction is derived from `dataStage`, so a request cannot
/// declare one direction and carry data for the other.
public struct USBControlTransferRequest: Equatable, Sendable {
  public enum RequestKind: UInt8, Equatable, Sendable {
    case standard = 0x00
    case `class` = 0x20
    case vendor = 0x40
  }

  public enum Recipient: UInt8, Equatable, Sendable {
    case device = 0x00
    case interface = 0x01
    case endpoint = 0x02
    case other = 0x03
  }

  public enum DataStage: Equatable, Sendable {
    case none
    /// Host-to-device bytes; the count becomes `wLength`.
    case output([UInt8])
    /// Device-to-host transfer of at most `length` bytes.
    case input(length: UInt16)
  }

  public let kind: RequestKind
  public let recipient: Recipient
  public let request: UInt8
  public let value: UInt16
  public let index: UInt16
  public let dataStage: DataStage

  /// Throws `USBTransportError.notSupported` for OUT data longer than `UInt16.max`
  /// or an IN data stage of zero bytes.
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

  public var direction: USBEndpointDirection {
    if case .input = dataStage { return .in }
    return .out
  }

  /// `bmRequestType`: direction, kind and recipient bits.
  public var requestType: UInt8 {
    (direction == .in ? 0x80 : 0x00) | kind.rawValue | recipient.rawValue
  }

  /// `wLength`.
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
  case ioUSBHost
  /// Access through an entitled USBDriverKit system extension.
  case usbDriverKit
}

/// Stable identity for a service whose numeric registry ID may overlap another backend.
public struct USBTransportServiceIdentity: Hashable, Sendable {
  public let route: USBTransportRoute
  public let serviceID: UInt64

  public init(route: USBTransportRoute, serviceID: UInt64) {
    self.route = route
    self.serviceID = serviceID
  }
}

/// Options that must be applied before a transport session is exposed to protocol code.
public struct USBTransportOpenOptions: Equatable, Sendable {
  public let configurationValue: UInt8?
  public let interfaceNumber: UInt8
  public let alternateSetting: UInt8

  public init(
    configurationValue: UInt8? = nil,
    interfaceNumber: UInt8 = 0,
    alternateSetting: UInt8 = 0
  ) {
    self.configurationValue = configurationValue
    self.interfaceNumber = interfaceNumber
    self.alternateSetting = alternateSetting
  }

  public init(transportProfile: DeviceTransportProfile) {
    self.init(
      configurationValue: transportProfile.needsSetConfiguration ? 1 : nil,
      interfaceNumber: transportProfile.interfaceNumber,
      alternateSetting: transportProfile.alternateSetting
    )
  }

  /// Whether this open must send SET_CONFIGURATION to a device whose current configuration is
  /// `current` (nil or 0 when unconfigured). Selecting the configuration the device already runs
  /// is skipped: SET_CONFIGURATION terminates every open interface of the device
  /// (`IOUSBHostDevice.h`), so a reopened interface would otherwise end its siblings' sessions.
  public func setsConfiguration(current: UInt8?) -> Bool {
    guard let configurationValue else { return false }
    return configurationValue != current
  }
}

/// Stable description of one physical raw USB service.
public struct USBTransportDevice: Hashable, Sendable {
  public let route: USBTransportRoute
  public let serviceID: UInt64
  public let vendorID: UInt16
  public let productID: UInt16
  /// Backend routing value. This can be a fallback when the physical location is unknown.
  public let locationID: UInt32
  /// USB location property observed from the device service, if available.
  public let observedPhysicalLocationIdentifier: UInt32?
  public let productName: String?
  public let serialNumber: String?

  public init(
    route: USBTransportRoute,
    serviceID: UInt64,
    vendorID: UInt16,
    productID: UInt16,
    locationID: UInt32,
    observedPhysicalLocationIdentifier: UInt32? = nil,
    productName: String? = nil,
    serialNumber: String? = nil
  ) {
    self.route = route
    self.serviceID = serviceID
    self.vendorID = vendorID
    self.productID = productID
    self.locationID = locationID
    self.observedPhysicalLocationIdentifier = observedPhysicalLocationIdentifier
    self.productName = productName
    self.serialNumber = serialNumber
  }

  public var serviceIdentity: USBTransportServiceIdentity {
    USBTransportServiceIdentity(route: route, serviceID: serviceID)
  }
}

/// Best-effort runtime resolution for one admitted USB service.
public struct USBTransportResolution: Equatable, Sendable {
  public let profile: DeviceTransportProfile
  public let physicalDevice: PhysicalDevice?

  public init(profile: DeviceTransportProfile, physicalDevice: PhysicalDevice? = nil) {
    self.profile = profile
    self.physicalDevice = physicalDevice
  }
}

/// Discovers and opens physical USB interfaces without exposing a transport framework to Kit.
public protocol USBTransportProvider: Sendable {
  func devices() async throws -> [USBTransportDevice]
  func open(
    _ device: USBTransportDevice,
    options: USBTransportOpenOptions
  ) async throws -> any USBTransportSession

  /// Resolves one admitted device's profile and any available physical facts
  /// without claiming the device.
  func resolveTransport(
    for device: USBTransportDevice,
    configured: DeviceTransportProfile
  ) async -> USBTransportResolution

  /// Passive facts for one enumerated device before any binding exists. Nil when unavailable.
  func physicalDeviceObservation(for device: USBTransportDevice) async -> PhysicalDevice?

  /// Passive facts that include the host's cached descriptor of configuration
  /// `configurationValue`, read without claiming an interface or sending SET_CONFIGURATION. Nil
  /// when the device reports no such configuration.
  func configurationObservation(
    for device: USBTransportDevice,
    configurationValue: UInt8
  ) async throws -> PhysicalDevice?

  /// Resets the device's USB port, which makes the host enumerate the device again as a replug
  /// does. Every open interface of the device ends, and the device returns as a new attachment.
  func resetDevice(_ device: USBTransportDevice) async throws
}

extension USBTransportProvider {
  public func resolveTransport(
    for device: USBTransportDevice,
    configured: DeviceTransportProfile
  ) async -> USBTransportResolution {
    await Task.yield()
    return USBTransportResolution(profile: configured)
  }

  public func physicalDeviceObservation(for device: USBTransportDevice) -> PhysicalDevice? { nil }

  public func configurationObservation(
    for device: USBTransportDevice,
    configurationValue: UInt8
  ) throws -> PhysicalDevice? { throw USBTransportError.notSupported }

  public func resetDevice(_: USBTransportDevice) throws { throw USBTransportError.notSupported }
}

/// Stable failure categories shared by USB transport implementations.
public enum USBTransportError: Error, Equatable, Sendable {
  case timeout
  case disconnected
  case inputOutput
  case accessDenied
  case notFound
  case notSupported
  case platform(code: Int32, message: String)

  public var isTimeout: Bool { self == .timeout }
  public var isDisconnected: Bool { self == .disconnected }
  public var isInputOutput: Bool { self == .inputOutput }
}

public struct DiscoveredUSBTransport: Equatable, Sendable {
  public let interfaceNumber: UInt8
  public let alternateSetting: UInt8
  public let inputEndpoint: UInt8
  public let outputEndpoint: UInt8

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

public enum USBDescriptorTransportResolver {
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
