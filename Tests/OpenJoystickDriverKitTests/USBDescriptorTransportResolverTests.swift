import Testing

@testable import OpenJoystickDriverKit

struct USBDescriptorTransportResolverTests {
  @Test func liveDescriptorFactsReplaceProtocolDefaults() {
    let configured = DeviceTransportProfile.gipDefault
    let resolved = USBDescriptorTransportResolver.resolve(
      configured: configured,
      discovered: DiscoveredUSBTransport(
        interfaceNumber: 3,
        alternateSetting: 0,
        inputEndpoint: 0x84,
        outputEndpoint: 0x04
      )
    )

    #expect(resolved.interfaceNumber == 3)
    #expect(resolved.alternateSetting == 0)
    #expect(resolved.inputEndpoint == 0x84)
    #expect(resolved.outputEndpoint == 0x04)
  }

  @Test func explicitRecordOverridesWinOverDescriptorFacts() {
    let configured = DeviceTransportProfile(
      inputEndpoint: 0x81,
      outputEndpoint: 0x01,
      interfaceNumber: 2,
      hasInterfaceOverride: true,
      hasEndpointOverride: true,
      needsSetConfiguration: true,
      postHandshakeSettleNanoseconds: 200_000_000
    )
    let resolved = USBDescriptorTransportResolver.resolve(
      configured: configured,
      discovered: DiscoveredUSBTransport(
        interfaceNumber: 2,
        alternateSetting: 1,
        inputEndpoint: 0x84,
        outputEndpoint: 0x04
      )
    )

    #expect(resolved.interfaceNumber == 2)
    #expect(resolved.alternateSetting == 1)
    #expect(resolved.inputEndpoint == 0x81)
    #expect(resolved.outputEndpoint == 0x01)
    #expect(resolved.needsSetConfiguration)
    #expect(resolved.postHandshakeSettleNanoseconds == 200_000_000)
  }

  @Test func discoveryFailureRetainsProtocolDefaultsAndOverrides() {
    let configured = DeviceTransportProfile.gipDefault
    #expect(
      USBDescriptorTransportResolver.resolve(configured: configured, discovered: nil) == configured
    )
  }


  @Test func descriptorSelectionUsesCompleteInterruptPairFromAlternateSetting() throws {
    let selected = USBDescriptorTransportResolver.discover(
      interfaces: [
        interface(number: 2, alternate: 0, endpoints: [endpoint(0x81, input: true)]),
        interface(
          number: 2,
          alternate: 1,
          endpoints: [endpoint(0x84, input: true), endpoint(0x04, input: false)]
        ),
      ],
      preferredInterface: 0,
      requirePreferredInterface: false
    )

    let discovered = try #require(selected)
    #expect(discovered.interfaceNumber == 2)
    #expect(discovered.alternateSetting == 1)
    #expect(discovered.inputEndpoint == 0x84)
    #expect(discovered.outputEndpoint == 0x04)
  }

  @Test func descriptorSelectionRequiresInterruptInputAndOutput() {
    let selected = USBDescriptorTransportResolver.discover(
      interfaces: [
        interface(number: 1, endpoints: [endpoint(0x81, input: true)]),
        interface(
          number: 2,
          endpoints: [endpoint(0x82, input: true), endpoint(0x02, input: false, interrupt: false)]
        ),
      ],
      preferredInterface: 0,
      requirePreferredInterface: false
    )

    #expect(selected == nil)
  }

  @Test func descriptorSelectionHonorsExplicitInterfaceAndVendorClass() throws {
    let selected = USBDescriptorTransportResolver.discover(
      interfaces: [
        interface(
          number: 1,
          interfaceClass: 0x03,
          endpoints: [endpoint(0x81, input: true), endpoint(0x01, input: false)]
        ),
        interface(
          number: 2,
          endpoints: [endpoint(0x82, input: true), endpoint(0x02, input: false)]
        ),
        interface(
          number: 3,
          endpoints: [endpoint(0x83, input: true), endpoint(0x03, input: false)]
        ),
      ],
      preferredInterface: 3,
      requirePreferredInterface: true
    )

    let discovered = try #require(selected)
    #expect(discovered.interfaceNumber == 3)
    #expect(discovered.inputEndpoint == 0x83)
    #expect(discovered.outputEndpoint == 0x03)
  }

  @Test func descriptorSelectionReturnsNilWhenExplicitInterfaceHasNoPair() {
    let selected = USBDescriptorTransportResolver.discover(
      interfaces: [
        interface(
          number: 2,
          endpoints: [endpoint(0x82, input: true), endpoint(0x02, input: false)]
        ),
      ],
      preferredInterface: 3,
      requirePreferredInterface: true
    )

    #expect(selected == nil)
  }

  private func endpoint(
    _ address: UInt8,
    input: Bool,
    interrupt: Bool = true
  ) -> USBEndpointTransportFacts {
    USBEndpointTransportFacts(address: address, isInterrupt: interrupt, isInput: input)
  }

  private func interface(
    number: UInt8,
    alternate: UInt8 = 0,
    interfaceClass: UInt8 = 0xFF,
    endpoints: [USBEndpointTransportFacts]
  ) -> USBInterfaceTransportFacts {
    USBInterfaceTransportFacts(
      interfaceNumber: number,
      alternateSetting: alternate,
      interfaceClass: interfaceClass,
      endpoints: endpoints
    )
  }

}
