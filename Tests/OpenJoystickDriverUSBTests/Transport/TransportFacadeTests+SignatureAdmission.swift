import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverUSB

extension TransportFacadeTests {
  @Test
  func uncataloguedDirectDevicesAreAdmittedOnlyWithKnownSignature() async throws {
    let razer = device(route: .rawUSB, serviceID: 1, vendorID: 0x1532, productID: 0x0A15)
    let plain = device(route: .rawUSB, serviceID: 2, vendorID: 0x1234, productID: 0x5678)
    let provider = OpenJoystickDriverUSBTransportProvider(
      ioUSBHostProvider: FakeUSBTransportProvider(devicesResult: .success([razer, plain])),
      usbDriverKitProvider: FakeUSBTransportProvider(),
      supportedRawUSBModels: [],
      requiredDriverKitModels: []
    ) { device in
      PhysicalDevice(
        serviceAddress: device.serviceAddress,
        vendorID: device.vendorID,
        productID: device.productID,
        deviceClass: 0xFF,
        deviceSubclass: device.serviceID == 1 ? 0x47 : 0x00,
        deviceProtocol: device.serviceID == 1 ? 0xD0 : 0x00
      )
    }

    #expect(try await provider.devices() == [razer])
    #expect(await provider.physicalDeviceObservation(for: razer)?.deviceSubclass == 0x47)
  }

  @Test
  func configurationObservationIsReadOnlyThroughIOUSBHostForSameService() async throws {
    let direct = device(route: .rawUSB, serviceID: 3)
    let calls = ConfigurationCallRecorder()
    let provider = OpenJoystickDriverUSBTransportProvider(
      ioUSBHostProvider: FakeUSBTransportProvider(),
      usbDriverKitProvider: FakeUSBTransportProvider(),
      supportedRawUSBModels: [],
      requiredDriverKitModels: [],
      ioUSBHostObservation: { _ in nil },
      ioUSBHostConfigurationObservation: { device, value in
        calls.record(value)
        return PhysicalDevice(serviceAddress: device.serviceAddress)
      }
    )

    #expect(
      try await provider.configurationObservation(for: direct, configurationValue: 1)?
        .serviceAddress == direct.serviceAddress
    )
    await #expect(throws: USBTransportError.notSupported) {
      try await provider.configurationObservation(
        for: self.device(route: .usbExtension, serviceID: 4),
        configurationValue: 1
      )
    }
    #expect(calls.values == [1])
  }
}

private final class ConfigurationCallRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var recorded: [UInt8?] = []

  var values: [UInt8?] { lock.withLock { recorded } }

  func record(_ value: UInt8?) { lock.withLock { recorded.append(value) } }
}

extension TransportFacadeTests {
  @Test
  func signatureAdmissionIsCachedWhileServiceStaysEnumerated() async throws {
    let razer = device(route: .rawUSB, serviceID: 5, vendorID: 0x1532, productID: 0x0A15)
    let plain = device(route: .rawUSB, serviceID: 6, vendorID: 0x1234, productID: 0x5678)
    let pending = device(route: .rawUSB, serviceID: 7, vendorID: 0x1234, productID: 0x9999)
    let reads = ObservationReadRecorder()
    let provider = OpenJoystickDriverUSBTransportProvider(
      ioUSBHostProvider: FakeUSBTransportProvider(
        devicesResult: .success([razer, plain, pending])
      ),
      usbDriverKitProvider: FakeUSBTransportProvider(),
      supportedRawUSBModels: [],
      requiredDriverKitModels: []
    ) { device in
      // The admitted device's second read fails; it must stay admitted.
      guard reads.record(device.serviceID) == 1 || device.serviceID != 5 else {
        throw USBTransportError.accessDenied
      }
      switch device.serviceID {
      case 5:
        return PhysicalDevice(
          serviceAddress: device.serviceAddress,
          deviceClass: 0xFF,
          deviceSubclass: 0x47,
          deviceProtocol: 0xD0
        )
      case 6:
        return PhysicalDevice(
          serviceAddress: device.serviceAddress,
          configurationValue: 1,
          interfaces: [PhysicalInterfaceSignature(interfaceNumber: 0, interfaceClass: 0x03)]
        )
      default:
        // Unconfigured without a signature: looked at again on the next poll.
        return PhysicalDevice(serviceAddress: device.serviceAddress, deviceClass: 0x00)
      }
    }

    #expect(try await provider.devices() == [razer])
    #expect(try await provider.devices() == [razer])
    #expect(reads.count(5) == 1)
    #expect(reads.count(6) == 1)
    #expect(reads.count(7) == 2)
  }
}

private final class ObservationReadRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var counts: [UInt64: Int] = [:]

  /// Records one read and returns how many reads of this service there have been.
  func record(_ serviceID: UInt64) -> Int {
    lock.withLock {
      counts[serviceID, default: 0] += 1
      return counts[serviceID, default: 0]
    }
  }

  func count(_ serviceID: UInt64) -> Int { lock.withLock { counts[serviceID, default: 0] } }
}
