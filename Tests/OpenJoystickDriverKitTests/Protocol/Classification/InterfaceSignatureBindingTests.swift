import Testing

@testable import OpenJoystickDriverKit

struct InterfaceSignatureBindingTests {
  private let registry = ProtocolDriverRegistry()
  private let uncatalogued = DeviceIdentifier(vendorID: 0x1234, productID: 0x5678)

  @Test(arguments: [
    (UInt8(0x58), UInt8(0x42), UInt8(0x00), "xbox.xid:gamepad"),
    (UInt8(0xFF), UInt8(0x5D), UInt8(0x01), "xbox.xusb:wired"),
    (UInt8(0xFF), UInt8(0x5D), UInt8(0x81), "xbox.xusb:receiver"),
    (UInt8(0xFF), UInt8(0x47), UInt8(0xD0), "xbox.gip:usb"),
  ])
  func eachRegistryInterfaceSignatureBindsItsFamily(
    interfaceClass: UInt8,
    subclass: UInt8,
    interfaceProtocol: UInt8,
    expected: String
  ) throws {
    let device = observed(interfaces: [
      registryInterface(0, interfaceClass, subclass, interfaceProtocol)
    ])
    let binding = try bound(device)
    #expect(binding.id.rawValue == expected)
    #expect(binding.rule == .interfaceSignature)
    #expect(binding.record == nil)
    #expect(binding.interfaceNumber == 0)
    #expect(binding.matchedPredicates == [.interfaceSignature])
    #expect(ProtocolDriverRegistry.carriesProtocolSignature(device))
    // Registry facts carry no endpoints, so they cannot vouch for the claimed interface.
    let registryOnly = try #require(registry.runtimeProfile(for: binding)).transportProfile
    #expect(
      violation(of: binding, USBTransportResolution(profile: registryOnly, physicalDevice: device))
        == .interfaceContractMismatch
    )
    let driver = try registry.makeDriver(
      for: binding,
      identifier: uncatalogued,
      claimed: try descriptorClaim(for: binding, interfaceClass, subclass, interfaceProtocol)
    ).get()
    switch binding.protocolID {
    case .xboxXID: #expect(driver is XIDDriver)
    case .xboxXUSB: #expect(driver is XUSBDriver)
    default: #expect(driver is GIPDriver)
    }
  }

  @Test
  func unconfiguredDeviceWithTheGIPDeviceTripleBindsGIPOnItsDataInterface() throws {
    let device = PhysicalDevice(
      vendorID: 0x1234,
      productID: 0x5678,
      deviceRelease: 0x0101,
      deviceClass: 0xFF,
      deviceSubclass: 0x47,
      deviceProtocol: 0xD0
    )
    let binding = try bound(device)
    #expect(binding.id.rawValue == "xbox.gip:usb")
    #expect(binding.interfaceNumber == 0)
    #expect(binding.matchedPredicates == [.deviceClassSignature])
    #expect(
      try registry.makeDriver(
        for: binding,
        identifier: uncatalogued,
        claimed: try descriptorClaim(for: binding, 0xFF, 0x47, 0xD0)
      ).get() is GIPDriver
    )
  }

  @Test
  func deviceTripleDoesNotBindAConfiguredDeviceOrOverHID() {
    let configured = PhysicalDevice(
      vendorID: 0x1234,
      productID: 0x5678,
      deviceClass: 0xFF,
      deviceSubclass: 0x47,
      deviceProtocol: 0xD0,
      configurationValue: 1,
      interfaces: [registryInterface(0, 0x03, 0x00, 0x00)]
    )
    #expect(registry.classify(configured, backend: .ioUSBHost) == .unsupported(.noProtocolMatch))
    #expect(ProtocolDriverRegistry.carriesProtocolSignature(configured))
    let unconfigured = PhysicalDevice(deviceClass: 0xFF, deviceSubclass: 0x47, deviceProtocol: 0xD0)
    #expect(
      registry.classify(unconfigured, backend: .ioHID)
        == rejection(.unsupportedTransportVariant, .xboxGIP)
    )
  }

  @Test
  func catalogRowBeatsAnInterfaceSignature() throws {
    // 045E:028E is a catalogued XUSB row; while its own XUSB interface is present, an extra GIP
    // triple does not change the binding. A GIP-only device is the firmware-mode case covered in
    // `ProtocolClassifierTests.xboxRecordYieldsToTheOtherXboxFamilysObservedSignature`.
    let device = PhysicalDevice(
      vendorID: 0x045E,
      productID: 0x028E,
      deviceClass: 0xFF,
      deviceSubclass: 0x47,
      deviceProtocol: 0xD0,
      interfaces: [registryInterface(0, 0xFF, 0x5D, 0x01), registryInterface(1, 0xFF, 0x47, 0xD0)]
    )
    let binding = try bound(device)
    #expect(binding.rule == .catalogRecord)
    #expect(binding.protocolID == .xboxXUSB)
  }

  @Test
  func twoFamiliesAtTheInterfaceLevelConflict() {
    let device = observed(interfaces: [
      registryInterface(0, 0xFF, 0x5D, 0x01), registryInterface(1, 0xFF, 0x47, 0xD0),
    ])
    #expect(
      registry.classify(device, backend: .ioUSBHost)
        == .conflict(.ambiguousProtocolMatch, candidates: [.xboxXUSB, .xboxGIP])
    )
  }

  @Test
  func variantsOfOneFamilyResolveToTheLowestInterface() throws {
    let device = observed(interfaces: [
      registryInterface(1, 0xFF, 0x5D, 0x81), registryInterface(0, 0xFF, 0x5D, 0x01),
    ])
    let binding = try bound(device)
    #expect(binding.id.rawValue == "xbox.xusb:wired")
    #expect(binding.interfaceNumber == 0)
  }

  @Test
  func uncataloguedDeviceWithoutASignatureHasNoProtocolMatch() {
    let device = observed(interfaces: [registryInterface(0, 0xFF, 0x00, 0x00)])
    #expect(!ProtocolDriverRegistry.carriesProtocolSignature(device))
    #expect(registry.classify(device, backend: .ioUSBHost) == .unsupported(.noProtocolMatch))
  }

  @Test
  func gipSignatureRunsWithTheProfileOfAFamilyOnlyGIPRow() throws {
    let binding = try bound(observed(interfaces: [registryInterface(0, 0xFF, 0x47, 0xD0)]))
    // 3537:1010 (GameSir G7 SE) names only the GIP family and set-configuration-before-claim.
    let g7SE = registry.record(for: DeviceIdentifier(vendorID: 0x3537, productID: 0x1010))
    #expect(g7SE?.recordID == "3537-1010")
    #expect(registry.runtimeProfile(for: binding) == g7SE?.withRecordID(nil))
    let xusb = try bound(observed(interfaces: [registryInterface(0, 0xFF, 0x5D, 0x01)]))
    let xusbProfile = try #require(registry.runtimeProfile(for: xusb))
    #expect(xusbProfile.physicalProtocolVariant == .wired)
    #expect(xusbProfile.transportProfile.inputEndpoint == 0x81)
    #expect(!xusbProfile.transportProfile.needsSetConfiguration)
  }

  @Test
  func signatureBindingFailsClosedUntilItsClaimedInterfaceIsObserved() throws {
    let binding = try bound(
      PhysicalDevice(deviceClass: 0xFF, deviceSubclass: 0x47, deviceProtocol: 0xD0)
    )
    let profile = try #require(registry.runtimeProfile(for: binding)).transportProfile
    func violation(_ interfaces: [PhysicalInterfaceSignature]?) -> ProtocolBindingReason? {
      self.violation(
        of: binding,
        USBTransportResolution(
          profile: profile,
          physicalDevice: PhysicalDevice(interfaces: interfaces)
        )
      )
    }
    #expect(
      registry.makeDriver(for: binding, identifier: uncatalogued, claimed: nil).failureReason
        == .interfaceContractMismatch
    )
    #expect(violation(nil) == .interfaceContractMismatch)
    #expect(violation([registryInterface(0, 0xFF, 0x47, 0xD0)]) == .interfaceContractMismatch)
    #expect(violation([registryInterface(0, 0xFF, 0x5D, 0x01)]) == .interfaceContractMismatch)
    let gip = PhysicalInterfaceSignature(
      interfaceNumber: 0,
      alternateSetting: 0,
      interfaceClass: 0xFF,
      interfaceSubclass: 0x47,
      interfaceProtocol: 0xD0,
      endpoints: [
        PhysicalEndpointSignature(address: 0x81, direction: .in, transferType: .interrupt),
        PhysicalEndpointSignature(address: 0x01, direction: .out, transferType: .interrupt),
      ]
    )
    // Observed endpoints must be the resolved ones; the family defaults are 0x82/0x02.
    #expect(violation([gip]) == .interfaceContractMismatch)
    let resolved = USBDescriptorTransportResolver.resolve(
      configured: profile,
      observed: PhysicalDevice(interfaces: [gip])
    )
    #expect((resolved.inputEndpoint, resolved.outputEndpoint) == (0x81, 0x01))
    #expect(
      self.violation(
        of: binding,
        USBTransportResolution(profile: resolved, physicalDevice: PhysicalDevice(interfaces: [gip]))
      ) == nil
    )
  }

  @Test
  func catalogEndpointPinsStayAuthoritativeOverTheObservedDescriptor() throws {
    // 1532:0A29 pins 129/1; a descriptor naming 0x82/0x02 does not override it.
    let record = try #require(
      registry.record(for: DeviceIdentifier(vendorID: 0x1532, productID: 0x0A29))
    )
    let observedDefaults = PhysicalDevice(interfaces: [
      PhysicalInterfaceSignature(
        interfaceNumber: 0,
        alternateSetting: 0,
        interfaceClass: 0xFF,
        endpoints: [
          PhysicalEndpointSignature(address: 0x82, direction: .in, transferType: .interrupt),
          PhysicalEndpointSignature(address: 0x02, direction: .out, transferType: .interrupt),
        ]
      )
    ])
    let resolved = USBDescriptorTransportResolver.resolve(
      configured: record.transportProfile,
      observed: observedDefaults
    )
    #expect((resolved.inputEndpoint, resolved.outputEndpoint) == (0x81, 0x01))
  }

  private func observed(interfaces: [PhysicalInterfaceSignature]) -> PhysicalDevice {
    PhysicalDevice(
      vendorID: uncatalogued.controllerIdentity.vendorID,
      productID: uncatalogued.controllerIdentity.productID,
      configurationValue: 1,
      interfaces: interfaces
    )
  }

  /// The failure `makeDriver` returns for this claim, or nil when it builds a driver.
  private func violation(
    of binding: ProtocolBinding,
    _ claimed: USBTransportResolution
  ) -> ProtocolBindingReason? {
    registry.makeDriver(for: binding, identifier: uncatalogued, claimed: claimed).failureReason
  }

  /// A claim from the device's own configuration descriptor: the bound interface with the
  /// family triple and exactly the profile's interrupt endpoint pair.
  private func descriptorClaim(
    for binding: ProtocolBinding,
    _ interfaceClass: UInt8,
    _ subclass: UInt8,
    _ interfaceProtocol: UInt8
  ) throws -> USBTransportResolution {
    let profile = try #require(registry.runtimeProfile(for: binding)).transportProfile
    let interface = PhysicalInterfaceSignature(
      interfaceNumber: profile.interfaceNumber,
      alternateSetting: profile.alternateSetting,
      interfaceClass: interfaceClass,
      interfaceSubclass: subclass,
      interfaceProtocol: interfaceProtocol,
      endpoints: [
        PhysicalEndpointSignature(
          address: profile.inputEndpoint,
          direction: .in,
          transferType: .interrupt
        ),
        PhysicalEndpointSignature(
          address: profile.outputEndpoint,
          direction: .out,
          transferType: .interrupt
        ),
      ]
    )
    return USBTransportResolution(
      profile: profile,
      physicalDevice: observed(interfaces: [interface])
    )
  }

  private func bound(_ device: PhysicalDevice) throws -> ProtocolBinding {
    let classification = registry.classify(device, backend: .ioUSBHost)
    guard case .bound(let binding) = classification else {
      Issue.record("did not bind: \(classification)")
      throw SignatureBindingFailure()
    }
    return binding
  }
}

private struct SignatureBindingFailure: Error {}

extension Result {
  /// The failure, or nil on success.
  var failureReason: Failure? {
    guard case .failure(let failure) = self else { return nil }
    return failure
  }
}

/// Interface facts as the IOUSBHost registry publishes them: no endpoint descriptors.
func registryInterface(
  _ number: UInt8,
  _ interfaceClass: UInt8,
  _ subclass: UInt8,
  _ interfaceProtocol: UInt8
) -> PhysicalInterfaceSignature {
  PhysicalInterfaceSignature(
    interfaceNumber: number,
    alternateSetting: 0,
    interfaceClass: interfaceClass,
    interfaceSubclass: subclass,
    interfaceProtocol: interfaceProtocol,
    configurationValue: 1,
    hostTransport: .usb,
    usbRoute: .ioUSBHost
  )
}
