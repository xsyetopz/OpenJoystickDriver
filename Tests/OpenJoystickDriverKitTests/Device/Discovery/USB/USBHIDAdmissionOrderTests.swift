import Testing

@testable import OpenJoystickDriverKit

/// A controller reachable over HID and raw USB ends on the raw-USB route whichever route admits
/// first.
struct USBHIDAdmissionOrderTests {
  private let device = USBTransportDevice(
    route: .ioUSBHost,
    serviceID: 90,
    vendorID: 0x1234,
    productID: 0x5678,
    locationID: 91
  )

  private struct Outcome: Equatable {
    let sources: [DeviceDiscoverySource]
    let ownerships: [ControllerOwnershipObservation]
    let releasedLocations: [UInt32]
  }

  private func observation(_ endpoints: [PhysicalEndpointSignature]?) -> PhysicalDevice {
    PhysicalDevice(
      serviceIdentity: device.serviceIdentity,
      vendorID: device.vendorID,
      productID: device.productID,
      configurationValue: 1,
      interfaces: [
        PhysicalInterfaceSignature(
          interfaceNumber: 0,
          alternateSetting: 0,
          interfaceClass: 0xFF,
          interfaceSubclass: 0x47,
          interfaceProtocol: 0xD0,
          endpoints: endpoints
        )
      ]
    )
  }

  private func makeProvider() -> SignatureDiscoveryProvider {
    SignatureDiscoveryProvider(
      device: device,
      passive: observation(nil),
      configured: observation([
        PhysicalEndpointSignature(address: 0x81, direction: .in, transferType: .interrupt),
        PhysicalEndpointSignature(address: 0x01, direction: .out, transferType: .interrupt),
      ])
    )
  }

  private func hidConnection(native: Bool) -> HIDDeviceConnection {
    HIDDeviceConnection(
      physicalDevice: PhysicalDevice(
        vendorID: device.vendorID,
        productID: device.productID,
        productName: "Test pad",
        transportProperty: "USB",
        physicalLocationIdentifier: 91,
        interfaces: [gamepadHIDInterface(host: .usb)],
        nativePassThrough: native
      ),
      routingLocationID: 91
    )
  }

  private func admit(hidFirst: Bool, native: Bool = false) async -> Outcome {
    let backend = ClaimRecordingHIDAccessBackend()
    let provider = makeProvider()
    let manager = DeviceManager(
      dispatcher: LoggingOutputDispatcher(),
      hidManager: HIDManager(backend: backend),
      usbTransportProvider: provider
    )
    let hid = hidConnection(native: native)
    if hidFirst { await manager.handleHIDEvent(.connected(connection: hid, ownership: .exclusive)) }
    // A raw-USB admission that meets a HID pipeline retries; the next poll admits again. A native
    // controller is acknowledged instead, so it never retries.
    for _ in 0..<2 {
      let outcome = await manager.handleUSBDeviceAdded(device, provider: provider)
      if outcome != .retry { break }
    }
    if !hidFirst {
      await manager.handleHIDEvent(.connected(connection: hid, ownership: .exclusive))
    }
    let snapshots = await manager.connectedDeviceDescriptions()
    let outcome = Outcome(
      sources: snapshots.map(\.discoverySource),
      ownerships: snapshots.map(\.physicalOwnership),
      releasedLocations: await backend.releasedLocations()
    )
    await manager.stop()
    return outcome
  }

  @Test
  func admissionOrderDoesNotChangeRouteOrExposure() async {
    let usbFirst = await admit(hidFirst: false)
    let hidFirst = await admit(hidFirst: true)

    #expect(usbFirst.sources == [.rawUSB])
    #expect(usbFirst.ownerships == [.exclusiveRawUSB])
    #expect(hidFirst.sources == usbFirst.sources)
    #expect(hidFirst.ownerships == usbFirst.ownerships)
    // The HID pipeline's claim is released so the device is not left seized behind the USB route.
    #expect(hidFirst.releasedLocations == [91])
  }

  @Test
  func nativePassThroughWinsInEitherOrder() async {
    let usbFirst = await admit(hidFirst: false, native: true)
    let hidFirst = await admit(hidFirst: true, native: true)

    #expect(usbFirst.sources == [.hid])
    #expect(usbFirst.ownerships == [.nativeGamepad])
    #expect(hidFirst == usbFirst)
  }

  @Test
  func nativeControllerAcknowledgesItsUSBServiceOnceAndReleasesItWhenGone() async throws {
    let provider = makeProvider()
    let manager = DeviceManager(
      dispatcher: LoggingOutputDispatcher(),
      hidManager: HIDManager(backend: ClaimRecordingHIDAccessBackend()),
      usbTransportProvider: provider
    )
    let hid = hidConnection(native: true)
    await manager.handleHIDEvent(.connected(connection: hid, ownership: .unknown))

    for _ in 0..<3 {
      #expect(await manager.handleUSBDeviceAdded(device, provider: provider) == .ignored)
    }
    #expect(await manager.nativeShadowedUSBServices.count == 1)
    var enumeration = USBEnumerationTracker()
    enumeration.acknowledge(device)
    await manager.releaseNativeShadowedUSBServices(in: &enumeration)
    #expect(enumeration.acknowledgedDevices[device.serviceIdentity] != nil)

    await manager.handleHIDEvent(.disconnected(connection: hid))
    await manager.releaseNativeShadowedUSBServices(in: &enumeration)
    #expect(enumeration.acknowledgedDevices.isEmpty)
    #expect(await manager.nativeShadowedUSBServices.isEmpty)
    guard case .claimed = await manager.handleUSBDeviceAdded(device, provider: provider) else {
      Issue.record("The USB service is admitted once the native controller is gone")
      await manager.stop()
      return
    }
    await manager.stop()
  }
}
