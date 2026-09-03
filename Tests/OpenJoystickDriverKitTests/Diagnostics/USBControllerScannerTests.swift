import Testing

@testable import OpenJoystickDriverKit

struct USBControllerScannerTests {
  @Test func scannerCarriesObservedTopologyClassificationAndReconciliation() async throws {
    let device = USBTransportDevice(
      route: .ioUSBHost,
      serviceID: 7,
      vendorID: 0x045E,
      productID: 0x028E,
      locationID: 9
    )
    let observation = ControllerTransportObservation(
      device: device,
      interfaces: [
        USBInterfaceTransportFacts(
          interfaceNumber: 0,
          alternateSetting: 0,
          interfaceClass: 0xFF,
          interfaceSubclass: 0x5D,
          interfaceProtocol: 0x01,
          configurationValue: 1,
          endpoints: [
            USBEndpointTransportFacts(
              address: 0xA1,
              transferType: .interrupt,
              direction: .in,
              maxPacketSize: 64,
              interval: 4
            ),
            USBEndpointTransportFacts(
              address: 0x17,
              transferType: .interrupt,
              direction: .out,
              maxPacketSize: 64,
              interval: 4
            )
          ]
        )
      ]
    )
    let descriptions = try await USBControllerScanner.scanVendorSpecific(
      using: ScannerProvider(device: device, observation: observation)
    )

    let description = try #require(descriptions.first)
    #expect(description.transportObservation == observation)
    #expect(description.classification?.selected == .xusb)
    #expect(description.reconciliation?.knownVariant == .xbox360)
    #expect(description.reconciliation?.hasConflict == false)
  }
}

private actor ScannerProvider: USBTransportObservationProvider {
  let device: USBTransportDevice
  let observation: ControllerTransportObservation

  init(device: USBTransportDevice, observation: ControllerTransportObservation) {
    self.device = device
    self.observation = observation
  }

  func devices() throws -> [USBTransportDevice] { [device] }

  func transportObservations() throws -> [ControllerTransportObservation] { [observation] }

  func open(_ device: USBTransportDevice, options: USBTransportOpenOptions) throws
    -> any USBTransportSession
  { ScannerSession() }
}

private final class ScannerSession: USBTransportSession, @unchecked Sendable {
  func writeInterruptPacket(endpoint: UInt8, data: [UInt8], timeout: UInt32) throws -> Int { 0 }

  func readInterruptPacket(endpoint: UInt8, length: Int, timeout: UInt32) throws -> [UInt8] { [] }
}
