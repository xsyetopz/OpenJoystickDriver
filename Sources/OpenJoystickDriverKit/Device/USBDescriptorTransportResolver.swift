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
      if requirePreferredInterface, interfaceNumber != preferredInterface { continue }
      guard let inputAddress = interruptAddress(in: endpoints, direction: .in),
        let outputAddress = interruptAddress(in: endpoints, direction: .out)
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

  /// The address of the first interrupt endpoint of `direction` that has one.
  private static func interruptAddress(
    in endpoints: [PhysicalEndpointSignature],
    direction: USBEndpointDirection
  ) -> UInt8? {
    endpoints.first {
      $0.address != nil && $0.transferType == .interrupt && $0.direction == direction
    }?.address
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
