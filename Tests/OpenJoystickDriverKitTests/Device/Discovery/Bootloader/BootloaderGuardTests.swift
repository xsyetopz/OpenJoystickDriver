import Foundation
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit

/// The 8BitDo bootloader identities `2DC8:3208` and `2DC8:5750` receive no traffic, with or
/// without a record, so no host transfer reaches a pad that waits for a firmware image.
struct BootloaderGuardTests {
  static let identities: [UInt16] = [0x3208, 0x5750]

  @Test(arguments: identities)
  func genericRawUSBBindingSendsNothing(productID: UInt16) async {
    let device = USBTransportDevice(
      route: .rawUSB,
      serviceID: 90,
      vendorID: 0x2DC8,
      productID: productID,
      locationID: 91
    )
    // A GIP interface signature binds a protocol for any other uncatalogued identity.
    let unconfigured = PhysicalDevice(
      serviceAddress: device.serviceAddress,
      vendorID: device.vendorID,
      productID: device.productID,
      deviceRelease: 0x0101,
      deviceClass: 0xFF,
      deviceSubclass: 0x47,
      deviceProtocol: 0xD0
    )
    let gip = PhysicalDevice(
      serviceAddress: device.serviceAddress,
      vendorID: device.vendorID,
      productID: device.productID,
      deviceClass: 0xFF,
      deviceSubclass: 0x47,
      deviceProtocol: 0xD0,
      configurationValue: 1,
      interfaces: [
        PhysicalInterfaceSignature(
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
      ]
    )
    let provider = SignatureDiscoveryProvider(
      device: device,
      passive: unconfigured,
      configured: gip
    )
    let manager = DeviceManager(
      dispatcher: LoggingOutputDispatcher(),
      installationKey: testPortKeyInstallationKey,
      usbTransportProvider: provider
    )

    #expect(await manager.handleUSBDeviceAdded(device, provider: provider) == .ignored)

    #expect(await provider.descriptorReads.isEmpty)
    #expect(await provider.openCount == 0)
    #expect(await provider.session.writes.isEmpty)
    #expect(await manager.connectedDeviceDescriptions().isEmpty)
    let unbound = await manager.unboundDeviceDescriptions()
    #expect(unbound.map(\.reason) == [.bootloaderIdentity])
    #expect(unbound.map(\.productID) == [productID])
    await manager.stop()
  }

  @Test(arguments: identities)
  func genericHIDBindingSendsNothing(productID: UInt16) async {
    let backend = ScriptedHIDAccessBackend()
    await backend.enableOutputReports()
    await backend.enableFeatureReports()
    // A gamepad descriptor binds `HIDDescriptor` for any other uncatalogued identity.
    let connection = HIDDeviceConnection(
      physicalDevice: PhysicalDevice(
        vendorID: 0x2DC8,
        productID: productID,
        productName: "Bootloader",
        transportProperty: "USB",
        physicalLocationIdentifier: 7,
        interfaces: [gamepadHIDInterface(host: .usb)]
      ),
      routingAddress: .ioKit(locationID: 7, interfaceNumber: nil)
    )
    await backend.setConnectionSnapshots([
      HIDDeviceConnectionSnapshot(connection: connection, ownership: .exclusive)
    ])
    let manager = DeviceManager(
      dispatcher: LoggingOutputDispatcher(),
      installationKey: testPortKeyInstallationKey,
      hidManager: HIDManager(backend: backend)
    )

    await manager.handleHIDEvent(.connected(connection: connection, ownership: .exclusive))

    #expect(await manager.connectedDeviceDescriptions().isEmpty)
    #expect(await backend.recordedOutputReports().isEmpty)
    #expect(await backend.recordedFeatureReports().isEmpty)
    #expect(await backend.recordedFeatureReadCount() == 0)
    #expect(await manager.unboundDeviceDescriptions().map(\.reason) == [.bootloaderIdentity])
    await manager.stop()
  }

  @Test(arguments: identities)
  func classificationBindsNoProtocol(productID: UInt16) {
    let registry = ProtocolDriverRegistry()
    let device = PhysicalDevice(
      vendorID: 0x2DC8,
      productID: productID,
      interfaces: [gamepadHIDInterface(host: .usb)]
    )
    for backend in [DeviceAccessBackend.hid, .rawUSB] {
      #expect(registry.classify(device, backend: backend) == .unsupported(.bootloaderIdentity))
    }
  }

  @Test
  func theControllerDetailSaysTheDeviceIsABootloader() {
    let key = ProtocolBindingReason.bootloaderIdentity.explanationKey
    #expect(key == "ui.controllers.bootloaderIdentity")
    #expect(Localization().string(key) != key)
  }

  @Test
  func onlyTheTwoBootloaderIdentitiesAreRefused() {
    #expect(ControllerModelID(vendorID: 0x2DC8, productID: 0x310A).isBootloaderIdentity == false)
    #expect(ControllerModelID(vendorID: 0x1234, productID: 0x3208).isBootloaderIdentity == false)
  }

  @Test(arguments: identities)
  func modeSelectionReadsNothing(productID: UInt16) async {
    let reader = CountingProbeReader()
    let selection = await ProtocolDriverRegistry().selectMode(
      of: ControllerModelID(vendorID: 0x2DC8, productID: productID),
      backend: .hid,
      reader: reader
    )
    #expect(selection == .noModes)
    #expect(await reader.reads == 0)
  }
}

private actor ProbeReadCount {
  private(set) var value = 0
  func increment() { value += 1 }
}

private struct CountingProbeReader: ControllerModeProbeReader {
  private let count = ProbeReadCount()

  var reads: Int { get async { await count.value } }

  func readFeatureReport(
    _ request: PhysicalHIDFeatureReadRequest
  ) async -> PhysicalHIDReportResult<Data> {
    await count.increment()
    return .unavailable
  }
}
