/// An open physical USB controller session used by protocol implementations.
///
/// The semantic controller layer depends on this port rather than a particular
/// USB library or DriverKit client. Concrete transports own device discovery,
/// interface claims, pipe lifetimes, and platform error translation.
public protocol USBTransportSession: AnyObject, Sendable {
  /// Sends one packet to an interrupt OUT endpoint.
  @discardableResult func writeInterruptPacket(endpoint: UInt8, data: [UInt8], timeout: UInt32)
    async throws -> Int

  /// Receives one packet from an interrupt IN endpoint.
  func readInterruptPacket(endpoint: UInt8, length: Int, timeout: UInt32) async throws -> [UInt8]

  /// Closes this exact device session idempotently.
  func close() async
}

extension USBTransportSession { public func close() async { await Task.yield() } }

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
}

/// Stable description of one physical raw USB service.
public struct USBTransportDevice: Hashable, Sendable {
  public let route: USBTransportRoute
  public let serviceID: UInt64
  public let vendorID: UInt16
  public let productID: UInt16
  public let locationID: UInt32
  public let productName: String?
  public let serialNumber: String?

  public init(
    route: USBTransportRoute,
    serviceID: UInt64,
    vendorID: UInt16,
    productID: UInt16,
    locationID: UInt32,
    productName: String? = nil,
    serialNumber: String? = nil
  ) {
    self.route = route
    self.serviceID = serviceID
    self.vendorID = vendorID
    self.productID = productID
    self.locationID = locationID
    self.productName = productName
    self.serialNumber = serialNumber
  }

  public var serviceIdentity: USBTransportServiceIdentity {
    USBTransportServiceIdentity(route: route, serviceID: serviceID)
  }
}

/// Discovers and opens physical USB interfaces without exposing a transport framework to Kit.
public protocol USBTransportProvider: Sendable {
  func devices() async throws -> [USBTransportDevice]
  /// Resolves interface and endpoint facts from the connected device when the
  /// controller record leaves them at protocol defaults.
  func resolveTransportProfile(for device: USBTransportDevice, configured: DeviceTransportProfile)
    async -> DeviceTransportProfile
  func open(_ device: USBTransportDevice, options: USBTransportOpenOptions) async throws
    -> any USBTransportSession
}

extension USBTransportProvider {
  /// Keeps the catalog transport profile unchanged when a backend does not
  /// support live USB descriptor inspection.
  public func resolveTransportProfile(
    for device: USBTransportDevice,
    configured: DeviceTransportProfile
  ) -> DeviceTransportProfile { configured }
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

package struct DiscoveredUSBTransport: Equatable, Sendable {
  package let interfaceNumber: UInt8
  package let alternateSetting: UInt8
  package let inputEndpoint: UInt8
  package let outputEndpoint: UInt8

  package init(
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

public struct USBEndpointTransportFacts: Equatable, Sendable {
  public let address: UInt8
  public let isInterrupt: Bool
  public let isInput: Bool
  public let transferType: USBEndpointTransferType
  public let direction: USBEndpointDirection
  public let maxPacketSize: UInt16?
  public let interval: UInt8?

  public init(
    address: UInt8,
    isInterrupt: Bool,
    isInput: Bool,
    transferType: USBEndpointTransferType? = nil,
    direction: USBEndpointDirection? = nil,
    maxPacketSize: UInt16? = nil,
    interval: UInt8? = nil
  ) {
    self.address = address
    self.isInterrupt = isInterrupt
    self.isInput = isInput
    self.transferType = transferType ?? (isInterrupt ? .interrupt : .unknown)
    self.direction = direction ?? (isInput ? .in : .out)
    self.maxPacketSize = maxPacketSize
    self.interval = interval
  }

  public init(
    address: UInt8,
    transferType: USBEndpointTransferType,
    direction: USBEndpointDirection,
    maxPacketSize: UInt16? = nil,
    interval: UInt8? = nil
  ) {
    self.init(
      address: address,
      isInterrupt: transferType == .interrupt,
      isInput: direction == .in,
      transferType: transferType,
      direction: direction,
      maxPacketSize: maxPacketSize,
      interval: interval
    )
  }
}

public struct USBInterfaceTransportFacts: Equatable, Sendable {
  public let interfaceNumber: UInt8
  public let alternateSetting: UInt8
  public let interfaceClass: UInt8
  public let interfaceSubclass: UInt8?
  public let interfaceProtocol: UInt8?
  public let configurationValue: UInt8?
  public let endpoints: [USBEndpointTransportFacts]

  public init(
    interfaceNumber: UInt8,
    alternateSetting: UInt8 = 0,
    interfaceClass: UInt8,
    interfaceSubclass: UInt8? = nil,
    interfaceProtocol: UInt8? = nil,
    configurationValue: UInt8? = nil,
    endpoints: [USBEndpointTransportFacts]
  ) {
    self.interfaceNumber = interfaceNumber
    self.alternateSetting = alternateSetting
    self.interfaceClass = interfaceClass
    self.interfaceSubclass = interfaceSubclass
    self.interfaceProtocol = interfaceProtocol
    self.configurationValue = configurationValue
    self.endpoints = endpoints
  }
}

public enum USBDescriptorTransportResolver {
  package static func discover(
    interfaces: [USBInterfaceTransportFacts],
    preferredInterface: UInt8,
    requirePreferredInterface: Bool
  ) -> DiscoveredUSBTransport? {
    for interface in interfaces where interface.interfaceClass == 0xFF {
      if requirePreferredInterface && interface.interfaceNumber != preferredInterface { continue }
      let endpoints = interface.endpoints.filter(\.isInterrupt)
      guard let input = endpoints.first(where: \.isInput),
        let output = endpoints.first(where: { !$0.isInput })
      else { continue }
      return DiscoveredUSBTransport(
        interfaceNumber: interface.interfaceNumber,
        alternateSetting: interface.alternateSetting,
        inputEndpoint: input.address,
        outputEndpoint: output.address
      )
    }
    return nil
  }

  package static func resolve(
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
