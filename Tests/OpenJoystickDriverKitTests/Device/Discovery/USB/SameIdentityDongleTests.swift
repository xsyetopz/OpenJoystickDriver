import Foundation
import ProtocolPacketFixtures
import Testing

@testable import OpenJoystickDriverKit

/// Two controllers of one uncatalogued identity (ZD Ultimate Legend dongle `413D:2204`, no serial
/// number) at different USB locations, bound by interface signature. Each must light its own
/// player slot and take only its own rumble.
struct SameIdentityDongleTests {
  private typealias Receiver = ProtocolPacketFixtures.XUSBReceiver

  private static let vendorID: UInt16 = 0x413D
  private static let productID: UInt16 = 0x2204

  @Test
  func wiredSignaturePadsOfOneIdentityLightDistinctPlayerSlots() async {
    let manager = DeviceManager(dispatcher: LoggingOutputDispatcher())
    let first = Self.pad(serviceID: 310, interfaceProtocol: 0x01, outEndpoint: 0x01)
    let second = Self.pad(serviceID: 320, interfaceProtocol: 0x01, outEndpoint: 0x01)

    for pad in [first, second] {
      _ = await manager.handleUSBDeviceAdded(pad.device, provider: pad.provider)
      #expect(await Self.waitUntil { await pad.session.writeCount >= 1 })
    }

    #expect(await first.session.writes.first == [0x01, 0x03, 0x06])
    #expect(await second.session.writes.first == [0x01, 0x03, 0x07])
    await manager.stop()
  }

  @Test
  func singleSlotReceiversOfOneIdentityLightDistinctPlayerSlots() async {
    let manager = DeviceManager(dispatcher: LoggingOutputDispatcher())
    let first = Self.pad(serviceID: 410, interfaceProtocol: 0x81, outEndpoint: 0x01)
    let second = Self.pad(serviceID: 420, interfaceProtocol: 0x81, outEndpoint: 0x01)

    for pad in [first, second] {
      _ = await manager.handleUSBDeviceAdded(pad.device, provider: pad.provider)
      // Presence inquiry, then the ring LED once the pad reports itself connected.
      #expect(await Self.waitUntil { await pad.session.writeCount >= 2 })
    }

    #expect(await first.session.writes.last.map(Self.receiverLED) == 0x46)
    #expect(await second.session.writes.last.map(Self.receiverLED) == 0x47)
    await manager.stop()
  }

  @Test
  func rumbleForOneWiredSignaturePadReachesOnlyThatPad() async {
    let manager = DeviceManager(dispatcher: LoggingOutputDispatcher())
    let first = Self.pad(serviceID: 510, interfaceProtocol: 0x01, outEndpoint: 0x01)
    let second = Self.pad(serviceID: 520, interfaceProtocol: 0x01, outEndpoint: 0x01)
    for pad in [first, second] {
      _ = await manager.handleUSBDeviceAdded(pad.device, provider: pad.provider)
      #expect(await Self.waitUntil { await pad.session.writeCount >= 1 })
    }
    let rumble = ControllerOutputCommand.setRumble(
      RumbleIntensities(leftMain: UnipolarValue(byte: 0x80)),
      duration: .milliseconds(5_000)
    )

    for pad in [first, second] {
      let identifier = Self.identifier(pad.device)
      let result = await manager.sendControllerOutput(
        rumble,
        for: identifier,
        runtimeIdentifier: identifier.runtimeIdentifier
      )
      #expect(result == ControllerOutputResult(.delivered))
    }

    let rumblePacket: [UInt8] = [0x00, 0x08, 0x00, 0x80, 0x00, 0x00, 0x00, 0x00]
    #expect(await first.session.writes.filter { $0 == rumblePacket }.count == 1)
    #expect(await second.session.writes.filter { $0 == rumblePacket }.count == 1)
    await manager.stop()
  }

  @Test
  func rumbleForOneConnectedReceiverReachesOnlyThatReceiver() async {
    let manager = DeviceManager(dispatcher: LoggingOutputDispatcher())
    let first = Self.pad(serviceID: 610, interfaceProtocol: 0x81, outEndpoint: 0x01)
    let second = Self.pad(serviceID: 620, interfaceProtocol: 0x81, outEndpoint: 0x01)
    for pad in [first, second] {
      _ = await manager.handleUSBDeviceAdded(pad.device, provider: pad.provider)
      #expect(await Self.waitUntil { await pad.session.writeCount >= 2 })
    }

    for (pad, left, right) in [(first, UInt8(0x80), UInt8(0x10)), (second, 0x20, 0x40)] {
      let identifier = Self.identifier(pad.device)
      let result = await manager.sendControllerOutput(
        .setRumble(
          RumbleIntensities(
            leftMain: UnipolarValue(byte: left),
            rightMain: UnipolarValue(byte: right)
          ),
          duration: .milliseconds(5_000)
        ),
        for: identifier,
        runtimeIdentifier: identifier.runtimeIdentifier
      )
      #expect(result == ControllerOutputResult(.delivered))
    }

    let firstRumble = await first.session.writes.filter(Self.isReceiverRumble)
    let secondRumble = await second.session.writes.filter(Self.isReceiverRumble)
    #expect(firstRumble == [[0x00, 0x01, 0x0F, 0xC0, 0x00, 0x80, 0x10, 0, 0, 0, 0, 0]])
    #expect(secondRumble == [[0x00, 0x01, 0x0F, 0xC0, 0x00, 0x20, 0x40, 0, 0, 0, 0, 0]])
    await manager.stop()
  }

  @Test
  func wiredSignaturePadWithOutEndpointTwoIsAdmittedAndTakesRumble() async {
    let manager = DeviceManager(dispatcher: LoggingOutputDispatcher())
    let pad = Self.pad(serviceID: 710, interfaceProtocol: 0x01, outEndpoint: 0x02)
    _ = await manager.handleUSBDeviceAdded(pad.device, provider: pad.provider)
    #expect(await Self.waitUntil { await pad.session.writeCount >= 1 })

    let identifier = Self.identifier(pad.device)
    let result = await manager.sendControllerOutput(
      .setRumble(
        RumbleIntensities(leftMain: UnipolarValue(byte: 0x80)),
        duration: .milliseconds(5_000)
      ),
      for: identifier,
      runtimeIdentifier: identifier.runtimeIdentifier
    )

    #expect(result == ControllerOutputResult(.delivered))
    let rumblePacket: [UInt8] = [0x00, 0x08, 0x00, 0x80, 0x00, 0x00, 0x00, 0x00]
    #expect(await pad.session.writes.filter { $0 == rumblePacket }.count == 1)
    #expect(await Set(pad.session.writeEndpoints) == [0x02])
    await manager.stop()
  }

  private static func isReceiverRumble(_ write: [UInt8]) -> Bool {
    write.count == 12 && write.prefix(4) == [0x00, 0x01, 0x0F, 0xC0]
  }

  private static func receiverLED(_ write: [UInt8]) -> UInt8? {
    write.count == 12 && write.prefix(3) == [0x00, 0x00, 0x08] ? write[3] : nil
  }

  private struct Pad {
    let device: USBTransportDevice
    let provider: DongleProvider
    let session: RecoveryUSBSession
  }

  private static func pad(serviceID: UInt64, interfaceProtocol: UInt8, outEndpoint: UInt8) -> Pad {
    let device = USBTransportDevice(
      route: .ioUSBHost,
      serviceID: serviceID,
      vendorID: vendorID,
      productID: productID,
      locationID: UInt32(serviceID) + 1
    )
    let descriptor = PhysicalDevice(
      serviceIdentity: device.serviceIdentity,
      vendorID: vendorID,
      productID: productID,
      configurationValue: 1,
      interfaces: [
        PhysicalInterfaceSignature(
          interfaceNumber: 0,
          alternateSetting: 0,
          interfaceClass: 0xFF,
          interfaceSubclass: 0x5D,
          interfaceProtocol: interfaceProtocol,
          endpoints: [
            PhysicalEndpointSignature(address: 0x81, direction: .in, transferType: .interrupt),
            PhysicalEndpointSignature(
              address: outEndpoint,
              direction: .out,
              transferType: .interrupt
            ),
          ]
        )
      ]
    )
    let reads: [Result<[UInt8], USBTransportError>] =
      interfaceProtocol == 0x81 ? [.success([UInt8](Receiver.presenceConnected))] : []
    let session = RecoveryUSBSession(readResults: reads, readError: .timeout)
    return Pad(
      device: device,
      provider: DongleProvider(device: device, descriptor: descriptor, session: session),
      session: session
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

  private static func waitUntil(condition: @escaping @Sendable () async -> Bool) async -> Bool {
    let deadline = ContinuousClock.now.advanced(by: .seconds(10))
    while ContinuousClock.now < deadline {
      if await condition() { return true }
      try? await Task.sleep(for: .milliseconds(1))
    }
    return await condition()
  }
}

/// A configured one-interface device whose single session is scripted by the test.
private actor DongleProvider: USBTransportProvider {
  let device: USBTransportDevice
  let descriptor: PhysicalDevice
  let session: RecoveryUSBSession

  init(device: USBTransportDevice, descriptor: PhysicalDevice, session: RecoveryUSBSession) {
    self.device = device
    self.descriptor = descriptor
    self.session = session
  }

  func devices() -> [USBTransportDevice] { [device] }

  func physicalDeviceObservation(for device: USBTransportDevice) -> PhysicalDevice? { descriptor }

  /// Resolves like the IOUSBHost facade: unpinned endpoints come from the observed descriptor.
  func resolveTransport(
    for device: USBTransportDevice,
    configured profile: DeviceTransportProfile
  ) -> USBTransportResolution {
    USBTransportResolution(
      profile: USBDescriptorTransportResolver.resolve(configured: profile, observed: descriptor),
      physicalDevice: descriptor
    )
  }

  func configurationObservation(
    for device: USBTransportDevice,
    configurationValue: UInt8
  ) -> PhysicalDevice? { descriptor }

  func open(
    _ device: USBTransportDevice,
    options: USBTransportOpenOptions
  ) -> any USBTransportSession { session }
}
