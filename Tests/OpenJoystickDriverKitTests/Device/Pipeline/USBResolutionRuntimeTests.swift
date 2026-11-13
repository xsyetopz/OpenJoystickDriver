import Foundation
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit

struct USBResolutionRuntimeTests {
  @Test
  func deviceManagerResolvedProfileReachesOpenStartupWriteAndFirstRead() async {
    let identifier = LogicalControllerID(vendorID: 0x045E, productID: 0x028E)
    let resolved = DeviceTransportProfile(
      inputEndpoint: 0x84,
      outputEndpoint: 0x04,
      interfaceNumber: 2,
      alternateSetting: 1,
      needsSetConfiguration: true
    )
    let device = USBTransportDevice(
      route: .rawUSB,
      serviceID: 7,
      vendorID: identifier.model.vendorID,
      productID: identifier.model.productID,
      locationID: 8
    )
    let physicalDevice = PhysicalDevice(
      serviceAddress: device.serviceAddress,
      vendorID: device.vendorID,
      productID: device.productID,
      physicalLocationIdentifier: device.locationID
    )
    let provider = USBManagerResolutionProvider(
      device: device,
      resolvedProfile: resolved,
      physicalDevice: physicalDevice
    )
    let manager = DeviceManager(
      dispatcher: LoggingOutputDispatcher(),
      installationKey: testPortKeyInstallationKey,
      usbTransportProvider: provider
    )

    let runtimeIdentifier = LogicalControllerID(
      vendorID: identifier.model.vendorID,
      productID: identifier.model.productID,
      locationID: device.locationID,
      interfaceNumber: resolved.interfaceNumber
    )
    #expect(
      await manager.handleUSBDeviceAdded(device, provider: provider)
        == .claimed([runtimeIdentifier])
    )
    await provider.waitForOpen()
    await provider.session.waitForFirstRead()

    #expect(await provider.options == USBTransportOpenOptions(transportProfile: resolved))
    #expect(await manager.deviceInfos[runtimeIdentifier]?.physicalDevice == physicalDevice)
    #expect(
      await provider.session.writes == [
        USBWriteRecord(endpoint: resolved.outputEndpoint, data: [0x01, 0x03, 0x06])
      ]
    )
    #expect(await provider.session.readEndpoints == [resolved.inputEndpoint])
    await manager.stop()
  }

  @Test
  func usbDiscoveryRetainsObservationUntilExactServiceDetaches() async {
    let device = USBTransportDevice(
      route: .rawUSB,
      serviceID: 27,
      vendorID: 0x045E,
      productID: 0x028E,
      locationID: 28
    )
    let physicalDevice = PhysicalDevice(
      serviceAddress: device.serviceAddress,
      vendorID: device.vendorID,
      productID: device.productID,
      deviceRelease: 0x0110,
      physicalLocationIdentifier: device.locationID
    )
    let provider = USBManagerResolutionProvider(
      device: device,
      resolvedProfile: .gipDefault,
      physicalDevice: physicalDevice
    )
    let manager = DeviceManager(
      dispatcher: LoggingOutputDispatcher(),
      installationKey: testPortKeyInstallationKey,
      usbTransportProvider: provider
    )
    let detection = Task { await manager.runUSBDetection() }
    let identifier = LogicalControllerID(
      vendorID: device.vendorID,
      productID: device.productID,
      locationID: device.locationID,
      interfaceNumber: DeviceTransportProfile.gipDefault.interfaceNumber
    )

    await provider.waitForOpen()
    #expect(await manager.deviceInfos[identifier]?.physicalDevice == physicalDevice)

    await provider.setDevices([])
    await waitUntil("the removed device is dropped") {
      await manager.deviceInfos[identifier] == nil
    }
    #expect(await manager.deviceInfos[identifier] == nil)

    detection.cancel()
    await detection.value
    await manager.stop()
  }

  @Test
  func usbDetectionReResolvesChangedFactsForTheSameServiceIdentity() async {
    let original = USBTransportDevice(
      route: .rawUSB,
      serviceID: 37,
      vendorID: 0x045E,
      productID: 0x02D1,
      locationID: 38,
      productName: "Original service facts"
    )
    let replacement = USBTransportDevice(
      route: .rawUSB,
      serviceID: 37,
      vendorID: 0x045E,
      productID: 0x02D1,
      locationID: 38,
      productName: "Replacement service facts"
    )
    let provider = USBManagerResolutionProvider(device: original, resolvedProfile: .gipDefault)
    let manager = DeviceManager(
      dispatcher: LoggingOutputDispatcher(),
      installationKey: testPortKeyInstallationKey,
      usbTransportProvider: provider
    )
    let detection = Task { await manager.runUSBDetection() }
    let identifier = LogicalControllerID(
      vendorID: original.vendorID,
      productID: original.productID,
      locationID: original.locationID,
      interfaceNumber: DeviceTransportProfile.gipDefault.interfaceNumber
    )

    await provider.waitForOpenCount(1)
    await provider.setDevices([replacement])
    await provider.waitForOpenCount(2)

    #expect(await provider.resolutionCount == 2)
    #expect(await manager.deviceInfos[identifier]?.name == "Replacement service facts")

    detection.cancel()
    await detection.value
    await manager.stop()
  }

  @Test
  func usbDetectionKeepsAcknowledgedServiceAcrossEnumerationFailureAndRecovery() async {
    let device = USBTransportDevice(
      route: .rawUSB,
      serviceID: 39,
      vendorID: 0x045E,
      productID: 0x02D1,
      locationID: 40
    )
    let provider = USBManagerResolutionProvider(device: device, resolvedProfile: .gipDefault)
    let manager = DeviceManager(
      dispatcher: LoggingOutputDispatcher(),
      installationKey: testPortKeyInstallationKey,
      usbTransportProvider: provider
    )
    let detection = Task { await manager.runUSBDetection() }
    let identifier = LogicalControllerID(
      vendorID: device.vendorID,
      productID: device.productID,
      locationID: device.locationID,
      interfaceNumber: DeviceTransportProfile.gipDefault.interfaceNumber
    )

    await provider.waitForOpenCount(1)
    await provider.failNextEnumeration(.accessDenied)
    await provider.waitForDevicesCallCount(3)
    await provider.waitForDevicesCallCount(5)

    #expect(await manager.deviceInfos[identifier] != nil)
    let resolutionCount = await provider.resolutionCount
    #expect(resolutionCount == 1)

    detection.cancel()
    await detection.value
    await manager.stop()
  }

  @Test
  func stopInvalidatesUSBAdmissionHeldInNoncooperativeResolution() async {
    let device = USBTransportDevice(
      route: .rawUSB,
      serviceID: 41,
      vendorID: 0x045E,
      productID: 0x02D1,
      locationID: 42
    )
    let provider = USBManagerResolutionProvider(device: device, resolvedProfile: .gipDefault)
    await provider.suspendResolutions()
    let manager = DeviceManager(
      dispatcher: LoggingOutputDispatcher(),
      installationKey: testPortKeyInstallationKey,
      usbTransportProvider: provider
    )
    let detection = Task { await manager.runUSBDetection() }
    await provider.waitForResolutionCount(1)

    await manager.stop()
    await provider.resumeResolutions()
    await detection.value

    #expect(await manager.deviceInfos.isEmpty)
    #expect(await manager.pipelines.isEmpty)
    let devicesCallCount = await provider.devicesCallCount
    let openCount = await provider.openCount
    #expect(devicesCallCount == 1)
    #expect(openCount == 0)
  }

  @Test
  func resolvedProfileReachesOpenHandshakeReadAndWrite() async throws {
    let identifier = LogicalControllerID(vendorID: 0x045E, productID: 0x028E)
    let resolved = DeviceTransportProfile(
      inputEndpoint: 0x84,
      outputEndpoint: 0x04,
      interfaceNumber: 2,
      alternateSetting: 1,
      needsSetConfiguration: true
    )
    let device = USBTransportDevice(
      route: .rawUSB,
      serviceID: 7,
      vendorID: identifier.model.vendorID,
      productID: identifier.model.productID,
      locationID: 8
    )
    let provider = USBRuntimeRecordingProvider()
    let parser = try catalogParser(identifier.model, transportProfile: resolved)
    let pipeline = DevicePipeline(
      identifier: identifier,
      transport: .usb(device: device),
      driver: parser,
      dispatcher: LoggingOutputDispatcher(),
      // A wired XUSB pad sends no driver startup output; the manager's slot LED is its only
      // startup write, so assign one as DeviceManager does.
      startupPlayerIndicator: .player1,
      usbTransportProvider: provider,
      transportProfile: resolved
    )

    let result = await pipeline.openDeviceWithRetry(provider: provider, device: device)
    let handle = try #require(
      ifCaseOpened(result),
      "expected the configured fallback profile to reach open"
    )
    #expect(await provider.options == USBTransportOpenOptions(transportProfile: resolved))

    // startUSBPipeline activates the pipeline and installs the handle before the handshake;
    // USB writes are accepted only for that current handle.
    await pipeline.activateForTesting()
    await pipeline.setUSBHandleForTesting(handle)
    #expect(await pipeline.performUSBHandshake(handle: handle))
    try await pipeline.sendUSBStartupOutputPackets(handle: handle)
    _ = try await pipeline.readInterrupt(handle: handle, inEndpoint: resolved.inputEndpoint)

    let writeEndpoints = await provider.session.writeEndpoints
    let readEndpoints = await provider.session.readEndpoints
    #expect(!writeEndpoints.isEmpty)
    #expect(writeEndpoints.allSatisfy { $0 == resolved.outputEndpoint })
    #expect(readEndpoints == [resolved.inputEndpoint])
  }

  private func ifCaseOpened(_ result: DevicePipeline.USBOpenResult) -> (any USBTransportSession)? {
    guard case .opened(let handle) = result else { return nil }
    return handle
  }
}
