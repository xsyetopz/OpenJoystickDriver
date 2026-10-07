import Testing

@testable import OpenJoystickDriverKit

struct USBSignatureDiscoveryTests {
  @Test
  func unconfiguredUncataloguedGIPDeviceBindsWithItsDescriptorEndpoints() async throws {
    // Uncatalogued device shaped like the owner's Razer Wolverine TE: device class FF/47/D0,
    // unconfigured, GIP on interface 0 at 0x81/0x01.
    let device = usbDevice(vendorID: 0x1234, productID: 0x5678, route: .ioUSBHost)
    let provider = SignatureDiscoveryProvider(
      device: device,
      passive: unconfiguredGIP(device),
      configured: configuredGIP(device, input: 0x81, output: 0x01)
    )
    let manager = makeManager(provider)

    let identifier = runtimeIdentifier(device)
    #expect(
      await manager.handleUSBDeviceAdded(device, provider: provider) == .claimed([identifier])
    )
    await provider.session.waitForFirstRead()

    // Discovery only reads configuration 1; the pipeline's open sends SET_CONFIGURATION.
    #expect(await provider.descriptorReads == [1])
    #expect(await manager.deviceInfos[identifier]?.binding.id.rawValue == "xbox.gip:usb")
    #expect(
      await provider.options
        == USBTransportOpenOptions(configurationValue: 1, interfaceNumber: 0, alternateSetting: 0)
    )
    #expect(await provider.session.writes.first?.endpoint == 0x01)
    #expect(await provider.session.readEndpoints.first == 0x81)
    let description = try #require(await manager.connectedDeviceDescriptions().first)
    #expect(description.protocolBinding.rawValue == "xbox.gip:usb")
    #expect((description.inputEndpoint, description.outputEndpoint) == (0x81, 0x01))
    let result = description.bindingResult
    #expect((result.outcome, result.rule) == (.bound, .interfaceSignature))
    #expect(result.catalogRecordID == nil)
    await manager.stop()
  }

  @Test
  func unconfiguredCataloguedRowWithoutPinsIsConfiguredByTheOpen() async {
    // 1532:0A43 names only the GIP family and does not set configuration before the claim.
    let device = usbDevice(vendorID: 0x1532, productID: 0x0A43, route: .ioUSBHost)
    let provider = SignatureDiscoveryProvider(
      device: device,
      passive: unconfiguredGIP(device),
      configured: configuredGIP(device, input: 0x81, output: 0x01)
    )
    let manager = makeManager(provider)

    let identifier = runtimeIdentifier(device)
    #expect(
      await manager.handleUSBDeviceAdded(device, provider: provider) == .claimed([identifier])
    )
    await provider.session.waitForFirstRead()

    #expect(await provider.descriptorReads == [1])
    #expect(await provider.options?.configurationValue == 1)
    #expect(await provider.session.writes.first?.endpoint == 0x01)
    #expect(await provider.session.readEndpoints.first == 0x81)
    let result = await manager.connectedDeviceDescriptions().first?.bindingResult
    #expect(result?.rule == .catalogRecord)
    #expect(result?.catalogRecordID == "1532-0a43")
    await manager.stop()
  }

  @Test
  func rejectedCataloguedRowReportsItsResolvedInterfaces() async {
    // A catalogued model classifies on identity alone; its interfaces come from resolution.
    let device = usbDevice(vendorID: 0x1532, productID: 0x0A43, route: .ioUSBHost)
    let wrongInterface = PhysicalDevice(
      serviceIdentity: device.serviceIdentity,
      vendorID: device.vendorID,
      productID: device.productID,
      interfaces: [descriptorInterface(0, 0xFF, 0x5D, 0x01, input: 0x81, output: 0x01)]
    )
    let provider = SignatureDiscoveryProvider(
      device: device,
      passive: unconfiguredGIP(device),
      configured: wrongInterface
    )
    let manager = makeManager(provider)

    #expect(await manager.handleUSBDeviceAdded(device, provider: provider) == .ignored)
    let result = await manager.unboundDeviceDescriptions().first?.bindingResult
    #expect(result?.interfaces.map(\.interfaceSubclass) == [0x5D])
    #expect(
      result?.rejectedCandidates == [
        .init(
          protocolID: .xboxGIP,
          reason: .interfaceContractMismatch,
          catalogRecordID: "1532-0a43"
        )
      ]
    )
  }

  @Test
  func configuredCataloguedRowWithoutPinsResolvesItsDescriptorEndpoints() async {
    let device = usbDevice(vendorID: 0x1532, productID: 0x0A43, route: .ioUSBHost)
    let provider = SignatureDiscoveryProvider(
      device: device,
      passive: configuredRegistryOnly(device),
      configured: configuredGIP(device, input: 0x81, output: 0x01)
    )
    let manager = makeManager(provider)

    let identifier = runtimeIdentifier(device)
    #expect(
      await manager.handleUSBDeviceAdded(device, provider: provider) == .claimed([identifier])
    )
    await provider.session.waitForFirstRead()

    #expect(await provider.descriptorReads == [1])
    #expect(await provider.options?.configurationValue == nil)
    #expect(await provider.session.writes.first?.endpoint == 0x01)
    #expect(await provider.session.readEndpoints.first == 0x81)
    await manager.stop()
  }

  @Test
  func configuredSignatureDeviceStillReadsItsDescriptorEndpoints() async {
    // After a first run the device stays configured and the registry publishes interface triples.
    let device = usbDevice(vendorID: 0x1234, productID: 0x5678, route: .ioUSBHost)
    let provider = SignatureDiscoveryProvider(
      device: device,
      passive: configuredRegistryOnly(device),
      configured: configuredGIP(device, input: 0x81, output: 0x01)
    )
    let manager = makeManager(provider)

    let identifier = runtimeIdentifier(device)
    #expect(
      await manager.handleUSBDeviceAdded(device, provider: provider) == .claimed([identifier])
    )
    await provider.session.waitForFirstRead()

    #expect(await provider.session.writes.first?.endpoint == 0x01)
    #expect(await provider.session.readEndpoints.first == 0x81)
    await manager.stop()
  }

  @Test
  func descriptorContractViolationLeavesTheDeviceUnboundBeforeAnyWrite() async {
    let device = usbDevice(vendorID: 0x1234, productID: 0x5678, route: .ioUSBHost)
    let wrongInterface = PhysicalDevice(
      serviceIdentity: device.serviceIdentity,
      vendorID: device.vendorID,
      productID: device.productID,
      interfaces: [descriptorInterface(0, 0xFF, 0x5D, 0x01, input: 0x81, output: 0x01)]
    )
    let provider = SignatureDiscoveryProvider(
      device: device,
      passive: unconfiguredGIP(device),
      configured: wrongInterface
    )
    let manager = makeManager(provider)

    #expect(await manager.handleUSBDeviceAdded(device, provider: provider) == .ignored)

    #expect(await provider.descriptorReads == [1])
    #expect(await provider.openCount == 0)
    #expect(await provider.session.writes.isEmpty)
    let unbound = await manager.unboundDeviceDescriptions()
    #expect(unbound.map(\.reason) == [.interfaceContractMismatch])
    #expect(
      unbound.map(\.rejectedCandidates) == [
        [.init(protocolID: .xboxGIP, reason: .interfaceContractMismatch)]
      ]
    )
    #expect(unbound.map(\.accessBackend) == [.ioUSBHost])
    // The configured observation's interfaces are reported, not the passive device-class facts.
    #expect(unbound.first?.interfaces.map(\.interfaceSubclass) == [0x5D])
  }

  @Test(arguments: [
    (DeviceIdentifier(vendorID: 0x1234, productID: 0x5678), USBTransportError?.some(.accessDenied)),
    (DeviceIdentifier(vendorID: 0x1234, productID: 0x5678), USBTransportError?.none),
    (DeviceIdentifier(vendorID: 0x1532, productID: 0x0A43), USBTransportError?.some(.inputOutput)),
  ])
  func unreadableDescriptorOfAnUnpinnedDeviceIsRetried(
    model: DeviceIdentifier,
    error: USBTransportError?
  ) async {
    // Never family-default endpoints and never a permanent unbound state for a failed read.
    let device = usbDevice(
      vendorID: model.controllerIdentity.vendorID,
      productID: model.controllerIdentity.productID,
      route: .ioUSBHost
    )
    let provider = SignatureDiscoveryProvider(
      device: device,
      passive: configuredRegistryOnly(device),
      configured: nil,
      configurationError: error
    )
    let manager = makeManager(provider)

    #expect(await manager.handleUSBDeviceAdded(device, provider: provider) == .retry)
    #expect(await provider.descriptorReads == [1])
    #expect(await provider.openCount == 0)
    #expect(await manager.unboundDeviceDescriptions().isEmpty)
  }

  @Test
  func registryOnlyDescriptorFactsLeaveASignatureDeviceUnbound() async {
    let device = usbDevice(vendorID: 0x1234, productID: 0x5678, route: .ioUSBHost)
    let provider = SignatureDiscoveryProvider(
      device: device,
      passive: configuredRegistryOnly(device),
      configured: configuredRegistryOnly(device)
    )
    let manager = makeManager(provider)

    #expect(await manager.handleUSBDeviceAdded(device, provider: provider) == .ignored)
    #expect(await provider.openCount == 0)
    #expect(await manager.unboundDeviceDescriptions().map(\.reason) == [.interfaceContractMismatch])
  }

  @Test
  func uncataloguedDeviceWithoutASignatureIsReportedWithNoProtocolMatch() async {
    let device = usbDevice(vendorID: 0x1234, productID: 0x5678, route: .ioUSBHost)
    let plain = PhysicalDevice(
      serviceIdentity: device.serviceIdentity,
      vendorID: device.vendorID,
      productID: device.productID,
      configurationValue: 1,
      interfaces: [registryInterface(0, 0xFF, 0x00, 0x00)]
    )
    let provider = SignatureDiscoveryProvider(device: device, passive: plain, configured: nil)
    let manager = makeManager(provider)

    #expect(await manager.handleUSBDeviceAdded(device, provider: provider) == .ignored)
    #expect(await provider.descriptorReads.isEmpty)
    #expect(await manager.unboundDeviceDescriptions().map(\.reason) == [.noProtocolMatch])
  }

  @Test
  func driverKitRouteNeverReadsTheConfiguration() async {
    // 045E:02EA is a catalogued GIP row reached through the DEXT in production.
    let device = usbDevice(vendorID: 0x045E, productID: 0x02EA, route: .usbDriverKit)
    let provider = SignatureDiscoveryProvider(
      device: device,
      passive: unconfiguredGIP(device),
      configured: configuredGIP(device, input: 0x81, output: 0x01)
    )
    let manager = makeManager(provider)

    #expect(
      await manager.handleUSBDeviceAdded(device, provider: provider)
        == .claimed([runtimeIdentifier(device)])
    )
    #expect(await provider.descriptorReads.isEmpty)
    await manager.stop()
  }

  private func makeManager(_ provider: SignatureDiscoveryProvider) -> DeviceManager {
    DeviceManager(dispatcher: LoggingOutputDispatcher(), usbTransportProvider: provider)
  }

  private func configuredRegistryOnly(_ device: USBTransportDevice) -> PhysicalDevice {
    PhysicalDevice(
      serviceIdentity: device.serviceIdentity,
      vendorID: device.vendorID,
      productID: device.productID,
      deviceClass: 0xFF,
      deviceSubclass: 0x47,
      deviceProtocol: 0xD0,
      configurationValue: 1,
      interfaces: [registryInterface(0, 0xFF, 0x47, 0xD0)]
    )
  }

  private func usbDevice(
    vendorID: UInt16,
    productID: UInt16,
    route: USBTransportRoute
  ) -> USBTransportDevice {
    USBTransportDevice(
      route: route,
      serviceID: 90,
      vendorID: vendorID,
      productID: productID,
      locationID: 91
    )
  }

  private func runtimeIdentifier(_ device: USBTransportDevice) -> DeviceIdentifier {
    DeviceIdentifier(
      vendorID: device.vendorID,
      productID: device.productID,
      locationID: device.locationID,
      interfaceNumber: 0
    )
  }

  private func unconfiguredGIP(_ device: USBTransportDevice) -> PhysicalDevice {
    PhysicalDevice(
      serviceIdentity: device.serviceIdentity,
      vendorID: device.vendorID,
      productID: device.productID,
      deviceRelease: 0x0101,
      deviceClass: 0xFF,
      deviceSubclass: 0x47,
      deviceProtocol: 0xD0
    )
  }

  private func configuredGIP(
    _ device: USBTransportDevice,
    input: UInt8,
    output: UInt8
  ) -> PhysicalDevice {
    PhysicalDevice(
      serviceIdentity: device.serviceIdentity,
      vendorID: device.vendorID,
      productID: device.productID,
      deviceClass: 0xFF,
      deviceSubclass: 0x47,
      deviceProtocol: 0xD0,
      configurationValue: 1,
      interfaces: [descriptorInterface(0, 0xFF, 0x47, 0xD0, input: input, output: output)]
    )
  }

  private func descriptorInterface(
    _ number: UInt8,
    _ interfaceClass: UInt8,
    _ subclass: UInt8,
    _ interfaceProtocol: UInt8,
    input: UInt8,
    output: UInt8
  ) -> PhysicalInterfaceSignature {
    PhysicalInterfaceSignature(
      interfaceNumber: number,
      alternateSetting: 0,
      interfaceClass: interfaceClass,
      interfaceSubclass: subclass,
      interfaceProtocol: interfaceProtocol,
      endpoints: [
        PhysicalEndpointSignature(address: input, direction: .in, transferType: .interrupt),
        PhysicalEndpointSignature(address: output, direction: .out, transferType: .interrupt),
      ]
    )
  }
}
