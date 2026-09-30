import Testing

@testable import OpenJoystickDriverKit

/// Wired Xbox 360 controllers each light a distinct ring LED slot, and a detached pad frees its.
struct USBStartupPlayerSlotTests {
  /// 0E6F:011F is a pinned wired XUSB row (0x81/0x02).
  private static let vendorID: UInt16 = 0x0E6F
  private static let productID: UInt16 = 0x011F

  @Test
  func wiredXbox360ControllersOfOneModelTakeDistinctReusablePlayerSlots() async {
    let manager = DeviceManager(dispatcher: LoggingOutputDispatcher())
    let first = Self.wiredPad(serviceID: 90)
    let second = Self.wiredPad(serviceID: 95)
    let third = Self.wiredPad(serviceID: 96)

    #expect(await Self.ringLED(of: first, on: manager) == 0x06)
    #expect(await Self.ringLED(of: second, on: manager) == 0x07)
    _ = await manager.removeUSBRole(Self.identifier(first.device))
    #expect(await Self.ringLED(of: third, on: manager) == 0x06)
    await manager.stop()
  }

  private static func ringLED(of pad: WiredPad, on manager: DeviceManager) async -> UInt8? {
    _ = await manager.handleUSBDeviceAdded(pad.device, provider: pad.provider)
    await pad.provider.session.waitForFirstRead()
    let writes = await pad.provider.session.writes
    guard writes.count == 1, writes[0].data.count == 3, writes[0].data.prefix(2) == [0x01, 0x03]
    else { return nil }
    return writes[0].data[2]
  }

  private struct WiredPad {
    let device: USBTransportDevice
    let provider: SignatureDiscoveryProvider
  }

  private static func wiredPad(serviceID: UInt64) -> WiredPad {
    let device = USBTransportDevice(
      route: .ioUSBHost,
      serviceID: serviceID,
      vendorID: vendorID,
      productID: productID,
      locationID: UInt32(serviceID) + 1
    )
    let interface = PhysicalInterfaceSignature(
      interfaceNumber: 0,
      alternateSetting: 0,
      interfaceClass: 0xFF,
      interfaceSubclass: 0x5D,
      interfaceProtocol: 0x01,
      endpoints: [
        PhysicalEndpointSignature(address: 0x81, direction: .in, transferType: .interrupt),
        PhysicalEndpointSignature(address: 0x02, direction: .out, transferType: .interrupt),
      ]
    )
    func observation(_ interface: PhysicalInterfaceSignature) -> PhysicalDevice {
      PhysicalDevice(
        serviceIdentity: device.serviceIdentity,
        vendorID: vendorID,
        productID: productID,
        configurationValue: 1,
        interfaces: [interface]
      )
    }
    return WiredPad(
      device: device,
      provider: SignatureDiscoveryProvider(
        device: device,
        passive: observation(registryInterface(0, 0xFF, 0x5D, 0x01)),
        configured: observation(interface)
      )
    )
  }

  private static func identifier(_ device: USBTransportDevice) -> DeviceIdentifier {
    DeviceIdentifier(
      vendorID: device.vendorID,
      productID: device.productID,
      locationID: device.locationID,
      interfaceNumber: 0
    )
  }
}
