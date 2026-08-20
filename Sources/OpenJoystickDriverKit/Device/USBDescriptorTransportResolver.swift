import SwiftUSB

struct DiscoveredUSBTransport: Equatable, Sendable {
  let interfaceNumber: UInt8
  let alternateSetting: UInt8
  let inputEndpoint: UInt8
  let outputEndpoint: UInt8
}

struct USBEndpointTransportFacts: Equatable, Sendable {
  let address: UInt8
  let isInterrupt: Bool
  let isInput: Bool

  init(endpoint: USBEndpoint) {
    self.address = endpoint.bEndpointAddress
    self.isInterrupt = endpoint.transferType == .interrupt
    self.isInput = endpoint.direction == .in
  }

  init(address: UInt8, isInterrupt: Bool, isInput: Bool) {
    self.address = address
    self.isInterrupt = isInterrupt
    self.isInput = isInput
  }
}

struct USBInterfaceTransportFacts: Equatable, Sendable {
  let interfaceNumber: UInt8
  let alternateSetting: UInt8
  let interfaceClass: UInt8
  let endpoints: [USBEndpointTransportFacts]

  init(interface: USBInterface) {
    self.interfaceNumber = interface.bInterfaceNumber
    self.alternateSetting = interface.bAlternateSetting
    self.interfaceClass = interface.bInterfaceClass
    self.endpoints = interface.endpoints().map(USBEndpointTransportFacts.init)
  }

  init(
    interfaceNumber: UInt8,
    alternateSetting: UInt8,
    interfaceClass: UInt8,
    endpoints: [USBEndpointTransportFacts]
  ) {
    self.interfaceNumber = interfaceNumber
    self.alternateSetting = alternateSetting
    self.interfaceClass = interfaceClass
    self.endpoints = endpoints
  }
}

public enum USBDescriptorTransportResolver {
  public static func resolve(device: USBDevice, configured: DeviceTransportProfile)
    -> DeviceTransportProfile
  {
    let configuration: USBConfigurationDescriptor
    do { configuration = try device.getActiveConfigurationDescriptor() } catch {
      do { configuration = try device.getConfigurationDescriptor(index: 0) } catch {
        print(
          "[USBDescriptors] Discovery failed"
            + " bus=\(device.bus) address=\(device.address): \(error);"
            + " using protocol defaults/record overrides"
        )
        return configured
      }
    }

    guard
      let discovered = discover(
        interfaces: configuration.interfaces.map(USBInterfaceTransportFacts.init),
        preferredInterface: configured.interfaceNumber,
        requirePreferredInterface: configured.hasInterfaceOverride
      )
    else {
      print(
        "[USBDescriptors] No interrupt endpoint pair"
          + " bus=\(device.bus) address=\(device.address);"
          + " using protocol defaults/record overrides"
      )
      return configured
    }
    return resolve(configured: configured, discovered: discovered)
  }

  static func discover(
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

  static func resolve(configured: DeviceTransportProfile, discovered: DiscoveredUSBTransport?)
    -> DeviceTransportProfile
  {
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
