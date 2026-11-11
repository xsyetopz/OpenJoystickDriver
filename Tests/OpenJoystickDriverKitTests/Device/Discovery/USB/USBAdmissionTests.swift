import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit

@Suite(.timeLimit(.minutes(2)))
struct USBDetectionAdmissionTests {
  @Test
  func claimedInterfaceOutsideTheBoundContractIsLeftUnbound() async {
    let device = USBTransportDevice(
      route: .rawUSB,
      serviceID: 2,
      vendorID: 0x045E,
      productID: 0x02EA,
      locationID: 2
    )
    let xusbInterface = PhysicalInterfaceSignature(
      interfaceNumber: 0,
      alternateSetting: 0,
      interfaceClass: 0xFF,
      interfaceSubclass: 0x5D,
      interfaceProtocol: 0x01,
      endpoints: [
        PhysicalEndpointSignature(address: 0x82, direction: .in, transferType: .interrupt),
        PhysicalEndpointSignature(address: 0x02, direction: .out, transferType: .interrupt),
      ]
    )
    let provider = USBDiscoveryRecordingProvider(
      devices: [device],
      physicalDevice: PhysicalDevice(
        serviceAddress: device.serviceAddress,
        vendorID: device.vendorID,
        productID: device.productID,
        interfaces: [xusbInterface]
      )
    )
    let manager = DeviceManager(
      dispatcher: LoggingOutputDispatcher(),
      installationKey: testPortKeyInstallationKey,
      usbTransportProvider: provider
    )

    #expect(await manager.handleUSBDeviceAdded(device, provider: provider) == .ignored)
    #expect(await manager.connectedLogicalControllerIDs().isEmpty)
    #expect(await manager.unboundDeviceDescriptions().map(\.reason) == [.interfaceContractMismatch])
    await manager.stop()
  }

  @Test
  func unsupportedDeviceNeverInvokesProfileResolution() async {
    let unknown = USBTransportDevice(
      route: .rawUSB,
      serviceID: 1,
      vendorID: 0x0001,
      productID: 0x0001,
      locationID: 1
    )
    let provider = USBDiscoveryRecordingProvider(
      devices: [],
      physicalDevice: PhysicalDevice(
        serviceAddress: unknown.serviceAddress,
        vendorID: unknown.vendorID,
        productID: unknown.productID
      )
    )
    let manager = DeviceManager(
      dispatcher: LoggingOutputDispatcher(),
      installationKey: testPortKeyInstallationKey,
      usbTransportProvider: provider
    )

    #expect(await manager.handleUSBDeviceAdded(unknown, provider: provider) == .ignored)
    #expect(await provider.resolutionCount == 0)
    #expect(await provider.observationResolutionCount == 0)
    #expect(
      await manager.unboundDeviceDescriptions() == [
        UnboundDeviceSnapshot(
          vendorID: 0x0001,
          productID: 0x0001,
          name: nil,
          connection: "USB",
          accessBackend: .rawUSB,
          reason: .noProtocolMatch,
          rejectedCandidates: [],
          interfaces: []
        )
      ]
    )
  }

  @Test
  func competingPhysicalUSBRouteSkipsDescriptorResolution() async {
    let direct = USBTransportDevice(
      route: .rawUSB,
      serviceID: 1,
      vendorID: 1_118,
      productID: 721,
      locationID: 9,
      serialNumber: "serial"
    )
    let driverKit = USBTransportDevice(
      route: .usbExtension,
      serviceID: 2,
      vendorID: 1_118,
      productID: 721,
      locationID: 10,
      serialNumber: "serial"
    )
    let provider = USBDiscoveryRecordingProvider(devices: [direct, driverKit])
    let manager = DeviceManager(
      dispatcher: LoggingOutputDispatcher(),
      installationKey: testPortKeyInstallationKey,
      usbTransportProvider: provider
    )

    #expect(
      await manager.handleUSBDeviceAdded(direct, provider: provider)
        == .claimed([
          LogicalControllerID(
            vendorID: 1_118,
            productID: 721,
            serialNumber: "serial",
            locationID: 9,
            interfaceNumber: 0
          )
        ])
    )
    #expect(await provider.resolutionCount == 1)

    #expect(await manager.handleUSBDeviceAdded(driverKit, provider: provider) == .retry)
    #expect(await provider.resolutionCount == 1)
    await manager.stop()
  }

  @Test
  func unresolvedServiceIsRetriedAfterItDisappears() async {
    let device = USBTransportDevice(
      route: .rawUSB,
      serviceID: 11,
      vendorID: 1_118,
      productID: 721,
      locationID: 9
    )
    let claimed = LogicalControllerID(
      vendorID: 1_118,
      productID: 721,
      locationID: 9,
      interfaceNumber: 0
    )
    let provider = USBDiscoveryRecordingProvider(devices: [])
    let manager = DeviceManager(
      dispatcher: LoggingOutputDispatcher(),
      installationKey: testPortKeyInstallationKey,
      usbTransportProvider: provider
    )

    #expect(await manager.handleUSBDeviceAdded(device, provider: provider) == .retry)
    await provider.setDevices([device])
    #expect(await manager.handleUSBDeviceAdded(device, provider: provider) == .claimed([claimed]))
    await manager.stop()
  }

  @Test
  func serviceReuseWithChangedDeviceFactsRemainsUnacknowledged() async {
    let original = USBTransportDevice(
      route: .rawUSB,
      serviceID: 11,
      vendorID: 0x045E,
      productID: 0x02D1,
      locationID: 9
    )
    let replacement = USBTransportDevice(
      route: .rawUSB,
      serviceID: 11,
      vendorID: 0x3537,
      productID: 0x1010,
      locationID: 10
    )
    let provider = USBDiscoveryRecordingProvider(devices: [replacement])
    let manager = DeviceManager(
      dispatcher: LoggingOutputDispatcher(),
      installationKey: testPortKeyInstallationKey,
      usbTransportProvider: provider
    )

    #expect(await manager.handleUSBDeviceAdded(original, provider: provider) == .retry)
  }

  @Test
  func enumerationFailureKeepsAcknowledgedServicesForSuccessfulRecovery() async {
    let device = USBTransportDevice(
      route: .rawUSB,
      serviceID: 31,
      vendorID: 0x045E,
      productID: 0x02D1,
      locationID: 9
    )
    let provider = USBEnumerationPollingProvider(replies: [
      .devices([device]), .failure(.accessDenied), .devices([device]), .devices([]),
    ])
    var tracker = USBEnumerationTracker()

    let attached = tracker.events(for: await pollUSBEnumeration(from: provider))
    #expect(attached == [.attached(device)])
    tracker.acknowledge(device)

    let failed = tracker.events(for: await pollUSBEnumeration(from: provider))
    #expect(failed == [.accessFailure(.transport(.accessDenied))])

    let recovered = tracker.events(for: await pollUSBEnumeration(from: provider))
    #expect(recovered.isEmpty)
    let detached = tracker.events(for: await pollUSBEnumeration(from: provider))
    #expect(detached == [.detached(device)])
  }

  @Test
  func changedFactsForReusedServiceEmitDetachBeforeAttach() async {
    let original = USBTransportDevice(
      route: .rawUSB,
      serviceID: 32,
      vendorID: 0x045E,
      productID: 0x02D1,
      locationID: 9,
      productName: "Original"
    )
    let replacement = USBTransportDevice(
      route: .rawUSB,
      serviceID: 32,
      vendorID: 0x045E,
      productID: 0x02D1,
      locationID: 10,
      productName: "Replacement"
    )
    let provider = USBEnumerationPollingProvider(replies: [
      .devices([original]), .devices([replacement]),
    ])
    var tracker = USBEnumerationTracker()

    #expect(tracker.events(for: await pollUSBEnumeration(from: provider)) == [.attached(original)])
    tracker.acknowledge(original)

    let changed = tracker.events(for: await pollUSBEnumeration(from: provider))
    #expect(changed == [.detached(original), .attached(replacement)])
  }

  @Test
  func physicalObservationMustIdentifyTheExactEnumeratedService() async {
    let device = USBTransportDevice(
      route: .rawUSB,
      serviceID: 11,
      vendorID: 1_118,
      productID: 721,
      locationID: 9
    )
    let otherService = PhysicalDevice(
      serviceAddress: ControllerConnectionAddress.usbService(route: .rawUSB, serviceID: 12),
      vendorID: device.vendorID,
      productID: device.productID,
      physicalLocationIdentifier: device.locationID
    )
    let provider = USBDiscoveryRecordingProvider(devices: [device], physicalDevice: otherService)
    let manager = DeviceManager(
      dispatcher: LoggingOutputDispatcher(),
      installationKey: testPortKeyInstallationKey,
      usbTransportProvider: provider
    )

    #expect(await manager.handleUSBDeviceAdded(device, provider: provider) == .retry)
    #expect(await manager.deviceInfos.isEmpty)
    await manager.stop()
  }

  @Test
  func competingClaimsRetryAfterPostAwaitRecheckAndLaterClaimWithoutReplug() async {
    let device = USBTransportDevice(
      route: .rawUSB,
      serviceID: 11,
      vendorID: 1_118,
      productID: 721,
      locationID: 9
    )
    let claimed = LogicalControllerID(
      vendorID: 1_118,
      productID: 721,
      locationID: 9,
      interfaceNumber: 0
    )
    let provider = USBResolutionRaceProvider(device: device)
    let manager = DeviceManager(
      dispatcher: LoggingOutputDispatcher(),
      installationKey: testPortKeyInstallationKey,
      usbTransportProvider: provider
    )

    let firstClaim = Task { await manager.handleUSBDeviceAdded(device, provider: provider) }
    let secondClaim = Task { await manager.handleUSBDeviceAdded(device, provider: provider) }
    await provider.waitForResolutionCount(2)

    await provider.resumeNextResolution()
    await provider.waitForOpenCount(1)
    await provider.resumeNextResolution()

    let outcomes = [await firstClaim.value, await secondClaim.value]
    #expect(outcomes.contains(.claimed([claimed])))
    #expect(outcomes.contains(.retry))
    #expect(await provider.openCount == 1)

    await manager.stop()
    await provider.setResolutionSuspended(false)

    #expect(await manager.handleUSBDeviceAdded(device, provider: provider) == .claimed([claimed]))
    await provider.waitForOpenCount(2)
    #expect(await provider.openCount == 2)
    await manager.stop()
  }
}
