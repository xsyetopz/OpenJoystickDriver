import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverUSB

extension PassiveUSBDescriptorProbeTests {
  @Test
  func registryInterfacesWithoutDescriptorBytesCarryTriplesButNoEndpoints() throws {
    let device = razerDevice()
    let source = SpySource(matches: [
      razerRoot(children: [interface(number: 0, alternate: 0, endpoint: 1)])
    ])

    let observation = try #require(
      try PassiveUSBDescriptorProbe.physicalDeviceObservation(for: device, source: source)
    )
    let interface = try #require(observation.interfaces?.first)
    #expect(observation.interfaces?.count == 1)
    #expect(interface.interfaceNumber == 0 && interface.alternateSetting == 0)
    #expect(
      [interface.interfaceClass, interface.interfaceSubclass, interface.interfaceProtocol] == [
        0xFF, 0x47, 0xD0,
      ]
    )
    #expect(interface.endpoints == nil)
    #expect(ProtocolDriverRegistry.carriesProtocolSignature(observation))
  }

  @Test
  func unconfiguredDeviceHasNoInterfacesAndKeepsItsDeviceTriple() throws {
    let observation = try #require(
      try PassiveUSBDescriptorProbe.physicalDeviceObservation(
        for: razerDevice(),
        source: SpySource(matches: [razerRoot(children: [])])
      )
    )
    #expect(observation.interfaces == nil)
    #expect(observation.configurationValue == nil)
    #expect(
      [observation.deviceClass, observation.deviceSubclass, observation.deviceProtocol] == [
        0xFF, 0x47, 0xD0,
      ]
    )
  }

  @Test
  func transportReadConfigurationDescriptorSuppliesEndpoints() throws {
    let descriptor: [UInt8] = [
      9, 2, 32, 0, 1, 1, 0, 0x80, 0x32, 9, 4, 0, 0, 2, 0xFF, 0x47, 0xD0, 0, 7, 5, 0x81, 3, 64, 0, 4,
      7, 5, 0x01, 3, 64, 0, 4,
    ]
    let observation = try #require(
      try PassiveUSBDescriptorProbe.physicalDeviceObservation(
        for: razerDevice(),
        source: SpySource(matches: [razerRoot(children: [])]),
        configurationDescriptor: descriptor
      )
    )
    let discovered = try #require(
      USBDescriptorTransportResolver.discover(configured: .gipDefault, observed: observation)
    )
    #expect(discovered.interfaceNumber == 0)
    #expect((discovered.inputEndpoint, discovered.outputEndpoint) == (0x81, 0x01))
  }

  @Test
  func threeInterfaceGIPLayoutResolvesInterruptPairOnInterfaceZero() throws {
    // Reconstructed from the Wolverine V2 libusb layout in GitHub issue #19 (interface 0
    // interrupt 0x01/0x81, interface 1 isochronous alt 1, interface 2 bulk alt 1); no raw bytes
    // of a real GIP configuration descriptor are archived.
    let descriptor: [UInt8] = [
      9, 2, 96, 0, 3, 1, 0, 0xA0, 0xFA, 9, 4, 0, 0, 2, 0xFF, 0x47, 0xD0, 0, 7, 5, 0x01, 3, 64, 0, 4,
      7, 5, 0x81, 3, 64, 0, 4, 9, 4, 1, 0, 0, 0xFF, 0x47, 0xD0, 0, 9, 4, 1, 1, 2, 0xFF, 0x47, 0xD0,
      0, 7, 5, 0x03, 1, 228, 0, 1, 7, 5, 0x83, 1, 228, 0, 1, 9, 4, 2, 0, 0, 0xFF, 0x47, 0xD0, 0, 9,
      4, 2, 1, 2, 0xFF, 0x47, 0xD0, 0, 7, 5, 0x02, 2, 64, 0, 0, 7, 5, 0x82, 2, 64, 0, 0,
    ]
    let observation = try #require(
      try PassiveUSBDescriptorProbe.physicalDeviceObservation(
        for: razerDevice(),
        source: SpySource(matches: [razerRoot(children: [])]),
        configurationDescriptor: descriptor
      )
    )
    #expect(observation.interfaces?.count == 5)
    let discovered = try #require(
      USBDescriptorTransportResolver.discover(configured: .gipDefault, observed: observation)
    )
    #expect(discovered.interfaceNumber == 0 && discovered.alternateSetting == 0)
    #expect((discovered.inputEndpoint, discovered.outputEndpoint) == (0x81, 0x01))
  }

  @Test(arguments: [UInt8(1), UInt8(0)])
  func razer0A3FLayoutResolvesItsInterfaceZeroPairEvenWithMalformedAlternate(
    isochronousInterval: UInt8
  ) throws {
    // openrazer#2364 lsusb of 1532:0A3F: interface 0 FF/47/D0 with interrupt OUT 0x05 and IN 0x84
    // (64 bytes, bInterval 4); interface 1 alt 0 without endpoints and alt 1 with two (details not
    // shown, modelled as isochronous). bInterval 0 on those makes the strict parser reject them.
    let descriptor: [UInt8] =
      [9, 2, 55, 0, 2, 1, 0, 0xA0, 0xFA] + [
        9, 4, 0, 0, 2, 0xFF, 0x47, 0xD0, 0, 7, 5, 0x05, 3, 64, 0, 4, 7, 5, 0x84, 3, 64, 0, 4,
      ] + [9, 4, 1, 0, 0, 0xFF, 0x47, 0xD0, 0] + [
        9, 4, 1, 1, 2, 0xFF, 0x47, 0xD0, 0, 7, 5, 0x03, 1, 228, 0, isochronousInterval,
      ] + [7, 5, 0x83, 1, 228, 0, isochronousInterval]
    let observation = try #require(
      try PassiveUSBDescriptorProbe.physicalDeviceObservation(
        for: razerDevice(),
        source: SpySource(matches: [razerRoot(children: [])]),
        configurationDescriptor: descriptor
      )
    )
    #expect(observation.interfaces?.count == 3)
    let discovered = try #require(
      USBDescriptorTransportResolver.discover(configured: .gipDefault, observed: observation)
    )
    #expect(discovered.interfaceNumber == 0)
    #expect((discovered.inputEndpoint, discovered.outputEndpoint) == (0x84, 0x05))
  }

  @Test
  func structuralWalkReportsNoEndpointsForMalformedClaimedInterface() {
    // A reserved address bit on interface 0 keeps its triple but drops its endpoints.
    let descriptor: [UInt8] = [
      9, 2, 32, 0, 1, 1, 0, 0xA0, 0xFA, 9, 4, 0, 0, 2, 0xFF, 0x47, 0xD0, 0, 7, 5, 0x71, 3, 64, 0, 4,
      7, 5, 0x81, 3, 64, 0, 4,
    ]
    let interfaces = PassiveUSBDescriptorProbe.structuralInterfaces(
      descriptor,
      configurationValue: nil,
      route: .rawUSB
    )
    #expect(interfaces?.count == 1)
    #expect(interfaces?.first?.interfaceClass == 0xFF)
    #expect(interfaces?.first?.endpoints == nil)
    #expect(
      PassiveUSBDescriptorProbe.structuralInterfaces(
        [9, 2, 32, 0, 1, 1, 0, 0xA0],
        configurationValue: nil,
        route: .rawUSB
      ) == nil
    )
  }

  private func razerDevice() -> USBTransportDevice {
    USBTransportDevice(
      route: .rawUSB,
      serviceID: 12,
      vendorID: 0x1532,
      productID: 0x0A15,
      locationID: 42
    )
  }

  private func razerRoot(children: [PassiveUSBRegistryNode]) -> PassiveUSBRegistryNode {
    PassiveUSBRegistryNode(
      serviceClass: "IOUSBHostDevice",
      properties: [
        "idVendor": .unsignedInteger(0x1532), "idProduct": .unsignedInteger(0x0A15),
        "locationID": .unsignedInteger(42), "bcdDevice": .unsignedInteger(0x0101),
        "bDeviceClass": .unsignedInteger(0xFF), "bDeviceSubClass": .unsignedInteger(0x47),
        "bDeviceProtocol": .unsignedInteger(0xD0),
      ],
      children: children,
      registryPath: "/fixture/usb/razer",
      registryEntryID: 12
    )
  }
}
