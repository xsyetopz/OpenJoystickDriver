import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit

/// Catalog endpoint pins stay authoritative, but the claimed interface is still read and checked.
struct USBPinnedRowDiscoveryTests {
  /// Pinned rows and their family class triples: 1532:0A29 (GIP, 0x81/0x01) and 0E6F:011F
  /// (XUSB wired, 0x81/0x02).
  static let pinnedRows: [PinnedRow] = [
    PinnedRow(vendorID: 0x1532, productID: 0x0A29, triple: (0xFF, 0x47, 0xD0), output: 0x01),
    PinnedRow(vendorID: 0x0E6F, productID: 0x011F, triple: (0xFF, 0x5D, 0x01), output: 0x02),
  ]

  struct PinnedRow: Sendable {
    let vendorID: UInt16
    let productID: UInt16
    let triple: (UInt8, UInt8, UInt8)
    let output: UInt8
  }

  @Test(arguments: pinnedRows)
  func pinnedRowWithMatchingDescriptorRunsOnItsPins(_ row: PinnedRow) async {
    let device = usbDevice(row)
    let provider = provider(device, row, descriptor: interface(row.triple, 0x81, row.output))
    let manager = makeManager(provider)

    #expect(
      await manager.handleUSBDeviceAdded(device, provider: provider)
        == .claimed([runtimeIdentifier(device)])
    )
    #expect(await provider.descriptorReads == [1])
    await manager.stop()
  }

  @Test
  func pinnedGIPRowWritesToItsPinnedEndpoint() async {
    let row = Self.pinnedRows[0]
    let device = usbDevice(row)
    let provider = provider(device, row, descriptor: interface(row.triple, 0x81, 0x01))
    let manager = makeManager(provider)

    _ = await manager.handleUSBDeviceAdded(device, provider: provider)
    await provider.session.waitForFirstRead()
    #expect(await provider.session.writes.first?.endpoint == 0x01)
    #expect(await provider.session.readEndpoints.first == 0x81)
    await manager.stop()
  }

  @Test(arguments: pinnedRows)
  func pinnedRowWithWrongInterfaceTripleIsRefused(_ row: PinnedRow) async {
    let device = usbDevice(row)
    let wrong: (UInt8, UInt8, UInt8) =
      row.triple.1 == 0x47 ? (0xFF, 0x5D, 0x01) : (0xFF, 0x47, 0xD0)
    let provider = provider(device, row, descriptor: interface(wrong, 0x81, row.output))
    let manager = makeManager(provider)

    #expect(await manager.handleUSBDeviceAdded(device, provider: provider) == .ignored)
    #expect(await provider.openCount == 0)
    #expect(await manager.unboundDeviceDescriptions().map(\.reason) == [.interfaceContractMismatch])
  }

  @Test(arguments: pinnedRows)
  func pinnedRowWhosePinnedEndpointsAreAbsentIsRefused(_ row: PinnedRow) async {
    let device = usbDevice(row)
    let provider = provider(device, row, descriptor: interface(row.triple, 0x83, 0x03))
    let manager = makeManager(provider)

    #expect(await manager.handleUSBDeviceAdded(device, provider: provider) == .ignored)
    #expect(await provider.openCount == 0)
    #expect(await manager.unboundDeviceDescriptions().map(\.reason) == [.interfaceContractMismatch])
  }

  @Test
  func pinnedRowWithUnreadableDescriptorIsRetried() async {
    let row = Self.pinnedRows[0]
    let device = usbDevice(row)
    let provider = SignatureDiscoveryProvider(
      device: device,
      passive: registryOnly(device, row),
      configured: nil,
      configurationError: .inputOutput
    )
    let manager = makeManager(provider)

    #expect(await manager.handleUSBDeviceAdded(device, provider: provider) == .retry)
    #expect(await provider.descriptorReads == [1])
    #expect(await provider.openCount == 0)
  }

  private func provider(
    _ device: USBTransportDevice,
    _ row: PinnedRow,
    descriptor: PhysicalInterfaceSignature
  ) -> SignatureDiscoveryProvider {
    SignatureDiscoveryProvider(
      device: device,
      passive: registryOnly(device, row),
      configured: PhysicalDevice(
        serviceAddress: device.serviceAddress,
        vendorID: device.vendorID,
        productID: device.productID,
        configurationValue: 1,
        interfaces: [descriptor]
      )
    )
  }

  /// IORegistry facts: the row's triple on interface 0, without endpoints.
  private func registryOnly(_ device: USBTransportDevice, _ row: PinnedRow) -> PhysicalDevice {
    PhysicalDevice(
      serviceAddress: device.serviceAddress,
      vendorID: device.vendorID,
      productID: device.productID,
      configurationValue: 1,
      interfaces: [registryInterface(0, row.triple.0, row.triple.1, row.triple.2)]
    )
  }

  private func interface(
    _ triple: (UInt8, UInt8, UInt8),
    _ input: UInt8,
    _ output: UInt8
  ) -> PhysicalInterfaceSignature {
    PhysicalInterfaceSignature(
      interfaceNumber: 0,
      alternateSetting: 0,
      interfaceClass: triple.0,
      interfaceSubclass: triple.1,
      interfaceProtocol: triple.2,
      endpoints: [
        PhysicalEndpointSignature(address: input, direction: .in, transferType: .interrupt),
        PhysicalEndpointSignature(address: output, direction: .out, transferType: .interrupt),
      ]
    )
  }

  private func makeManager(_ provider: SignatureDiscoveryProvider) -> DeviceManager {
    DeviceManager(
      dispatcher: LoggingOutputDispatcher(),
      installationKey: testPortKeyInstallationKey,
      usbTransportProvider: provider
    )
  }

  private func usbDevice(_ row: PinnedRow) -> USBTransportDevice {
    USBTransportDevice(
      route: .rawUSB,
      serviceID: 90,
      vendorID: row.vendorID,
      productID: row.productID,
      locationID: 91
    )
  }

  private func runtimeIdentifier(_ device: USBTransportDevice) -> LogicalControllerID {
    LogicalControllerID(
      vendorID: device.vendorID,
      productID: device.productID,
      locationID: device.locationID,
      interfaceNumber: 0
    )
  }
}
