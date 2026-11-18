import Testing

@testable import OpenJoystickDriverKit

struct USBDescriptorTransportResolverTests {
  @Test
  func unavailableInterfaceAndEndpointFactsStayAbsent() {
    let interface = PhysicalInterfaceSignature(
      interfaceClass: 0xFF,
      endpoints: [
        PhysicalEndpointSignature(direction: .in, transferType: .interrupt),
        PhysicalEndpointSignature(direction: .out, transferType: .interrupt),
      ]
    )

    #expect(interface.interfaceNumber == nil)
    #expect(interface.alternateSetting == nil)
    #expect(interface.interfaceSubclass == nil)
    #expect(interface.interfaceProtocol == nil)
    #expect(interface.configurationValue == nil)
    #expect(interface.hostTransport == nil)
    #expect(interface.physicalTransport == nil)
    #expect(interface.accessBackend == nil)
    #expect(interface.usbRoute == nil)
    #expect(interface.endpoints?.allSatisfy { $0.address == nil } == true)
    #expect(
      USBDescriptorTransportResolver.discover(
        interfaces: [interface],
        preferredInterface: 0,
        requirePreferredInterface: false
      ) == nil
    )
    #expect(
      USBDescriptorTransportResolver.discover(
        interfaces: nil,
        preferredInterface: 0,
        requirePreferredInterface: false
      ) == nil
    )
  }

  @Test
  func liveDescriptorFactsReplaceProtocolDefaults() {
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

  @Test
  func explicitRecordOverridesWinOverDescriptorFacts() {
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

  @Test
  func discoveryFailureRetainsProtocolDefaultsAndOverrides() {
    let configured = DeviceTransportProfile.gipDefault
    #expect(
      USBDescriptorTransportResolver.resolve(configured: configured, discovered: nil) == configured
    )
  }

  @Test
  func descriptorSelectionUsesCompleteInterruptPairFromAlternateSetting() throws {
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

  @Test
  func descriptorSelectionAcceptsXIDClassAndSkipsHIDInterfaces() throws {
    let selected = USBDescriptorTransportResolver.discover(
      interfaces: [
        interface(
          number: 0,
          interfaceClass: 0x03,
          endpoints: [endpoint(0x81, input: true), endpoint(0x01, input: false)]
        ),
        interface(
          number: 1,
          interfaceClass: 0x58,
          endpoints: [endpoint(0x82, input: true), endpoint(0x02, input: false)]
        ),
      ],
      preferredInterface: 0,
      requirePreferredInterface: false
    )

    let discovered = try #require(selected)
    #expect(discovered.interfaceNumber == 1)
    #expect(discovered.inputEndpoint == 0x82)
    #expect(discovered.outputEndpoint == 0x02)
  }

  @Test
  func missingEndpointAddressDoesNotMaskLaterCompletePair() throws {
    let selected = USBDescriptorTransportResolver.discover(
      interfaces: [
        interface(
          number: 2,
          endpoints: [
            PhysicalEndpointSignature(direction: .in, transferType: .interrupt),
            endpoint(0x82, input: true), endpoint(0x02, input: false),
          ]
        )
      ],
      preferredInterface: 0,
      requirePreferredInterface: false
    )

    let discovered = try #require(selected)
    #expect(discovered.inputEndpoint == 0x82)
    #expect(discovered.outputEndpoint == 0x02)
  }

  @Test
  func descriptorSelectionRequiresInterruptInputAndOutput() {
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

  @Test
  func descriptorSelectionHonorsExplicitInterfaceAndVendorClass() throws {
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

  @Test
  func descriptorSelectionReturnsNilWhenExplicitInterfaceHasNoPair() {
    let selected = USBDescriptorTransportResolver.discover(
      interfaces: [
        interface(
          number: 2,
          endpoints: [endpoint(0x82, input: true), endpoint(0x02, input: false)]
        )
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
  ) -> PhysicalEndpointSignature {
    PhysicalEndpointSignature(
      address: address,
      direction: input ? .in : .out,
      transferType: interrupt ? .interrupt : .bulk
    )
  }

  private func interface(
    number: UInt8,
    alternate: UInt8 = 0,
    interfaceClass: UInt8 = 0xFF,
    endpoints: [PhysicalEndpointSignature]
  ) -> PhysicalInterfaceSignature {
    PhysicalInterfaceSignature(
      interfaceNumber: number,
      alternateSetting: alternate,
      interfaceClass: interfaceClass,
      endpoints: endpoints
    )
  }

}

struct USBControlTransferRequestTests {
  @Test
  func inputRequestComposesSetupPacketFromTypedFields() throws {
    let request = try USBControlTransferRequest(
      kind: .vendor,
      recipient: .interface,
      request: 0x01,
      value: 0x0100,
      index: 2,
      dataStage: .input(length: 20)
    )

    #expect(request.direction == .in)
    #expect(request.requestType == 0xC1)
    #expect(request.length == 20)
    #expect(request.outputData.isEmpty)
  }

  @Test
  func outputRequestTakesLengthFromItsData() throws {
    let request = try USBControlTransferRequest(
      kind: .class,
      recipient: .endpoint,
      request: 0x09,
      value: 0x0200,
      index: 0x81,
      dataStage: .output([1, 2, 3])
    )

    #expect(request.direction == .out)
    #expect(request.requestType == 0x22)
    #expect(request.length == 3)
    #expect(request.outputData == [1, 2, 3])
  }

  @Test
  func noDataRequestIsHostToDeviceWithZeroLength() throws {
    let request = try USBControlTransferRequest(
      kind: .standard,
      recipient: .device,
      request: 0x09,
      value: 1
    )

    #expect(request.direction == .out)
    #expect(request.requestType == 0x00)
    #expect(request.length == 0)
  }

  @Test
  func dataStageLengthsOutsideSetupPacketAreRejected() {
    #expect(throws: USBTransportError.notSupported) {
      try USBControlTransferRequest(
        kind: .vendor,
        recipient: .device,
        request: 1,
        dataStage: .output([UInt8](repeating: 0, count: Int(UInt16.max) + 1))
      )
    }
    #expect(throws: USBTransportError.notSupported) {
      try USBControlTransferRequest(
        kind: .vendor,
        recipient: .device,
        request: 1,
        dataStage: .output([])
      )
    }
    #expect(throws: USBTransportError.notSupported) {
      try USBControlTransferRequest(
        kind: .vendor,
        recipient: .device,
        request: 1,
        dataStage: .input(length: 0)
      )
    }
  }

  @Test
  func endpointAddressDirectionBitSelectsTransferDirection() {
    #expect(USBEndpointDirection(endpointAddress: 0x81) == .in)
    #expect(USBEndpointDirection(endpointAddress: 0x02) == .out)
  }
}
