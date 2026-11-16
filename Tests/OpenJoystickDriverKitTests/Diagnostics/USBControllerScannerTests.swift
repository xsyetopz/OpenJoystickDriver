import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct USBControllerScannerTests {
  @Test
  func scannerCarriesObservedTopologyAndCatalogBinding() async throws {
    let device = USBTransportDevice(
      route: .rawUSB,
      serviceID: 7,
      vendorID: 0x045E,
      productID: 0x028E,
      locationID: 9
    )
    let physicalDevice = PhysicalDevice(
      serviceAddress: device.serviceAddress,
      vendorID: device.vendorID,
      productID: device.productID,
      interfaces: [
        PhysicalInterfaceSignature(
          interfaceNumber: 0,
          alternateSetting: 0,
          interfaceClass: 0xFF,
          interfaceSubclass: 0x5D,
          interfaceProtocol: 0x01,
          configurationValue: 1,
          hostTransport: .usb,
          usbRoute: .rawUSB,
          endpoints: [
            PhysicalEndpointSignature(
              address: 0xA1,
              direction: .in,
              transferType: .interrupt,
              maxPacketSize: 64,
              interval: 4
            ),
            PhysicalEndpointSignature(
              address: 0x17,
              direction: .out,
              transferType: .interrupt,
              maxPacketSize: 64,
              interval: 4
            ),
          ]
        )
      ]
    )
    let descriptions = try await USBControllerScanner.scanVendorSpecific(
      using: ScannerProvider(device: device, observation: physicalDevice)
    )

    let description = try #require(descriptions.first)
    #expect(description.physicalDevice == physicalDevice)
    guard case .bound(let binding) = description.classification else {
      Issue.record("expected a binding, got \(String(describing: description.classification))")
      return
    }
    #expect(binding.protocolID == .xboxXUSB)
    #expect(binding.variant == .wired)
    #expect(binding.accessBackend == .rawUSB)
    #expect(binding.rule == .catalogRecord)
  }

  @Test
  func incompleteDriverKitRouteObservationDoesNotProduceNegativeClassification() async throws {
    let device = USBTransportDevice(
      route: .usbExtension,
      serviceID: 42,
      vendorID: 0x045E,
      productID: 0x028E,
      locationID: 42
    )
    let physicalDevice = PhysicalDevice(
      serviceAddress: device.serviceAddress,
      vendorID: device.vendorID,
      productID: device.productID,
      interfaces: [
        PhysicalInterfaceSignature(
          hostTransport: .usb,
          accessBackend: .usbExtension,
          usbRoute: .usbExtension
        )
      ]
    )
    let descriptions = try await USBControllerScanner.scanVendorSpecific(
      using: ScannerProvider(device: device, observation: physicalDevice)
    )

    let description = try #require(descriptions.first)
    #expect(description.physicalDevice == physicalDevice)
    #expect(description.classification == nil)
  }

  @Test
  func driverKitRouteClassifiesWithDriverKitBackend() async throws {
    let device = USBTransportDevice(
      route: .usbExtension,
      serviceID: 8,
      vendorID: 0x1234,
      productID: 0x5678,
      locationID: 10
    )
    let physicalDevice = PhysicalDevice(
      serviceAddress: device.serviceAddress,
      vendorID: device.vendorID,
      productID: device.productID,
      interfaces: [
        PhysicalInterfaceSignature(
          interfaceNumber: 0,
          alternateSetting: 0,
          interfaceClass: 0xFF,
          interfaceSubclass: 0x47,
          interfaceProtocol: 0xD0,
          hostTransport: .usb,
          accessBackend: .usbExtension,
          usbRoute: .usbExtension,
          endpoints: [
            PhysicalEndpointSignature(address: 0x81, direction: .in, transferType: .interrupt),
            PhysicalEndpointSignature(address: 0x01, direction: .out, transferType: .interrupt),
          ]
        )
      ]
    )
    let descriptions = try await USBControllerScanner.scanVendorSpecific(
      using: ScannerProvider(device: device, observation: physicalDevice)
    )

    let description = try #require(descriptions.first)
    guard case .bound(let binding) = description.classification else {
      Issue.record("expected a binding, got \(String(describing: description.classification))")
      return
    }
    #expect(binding.protocolID == .xboxGIP)
    #expect(binding.variant == .usb)
    #expect(binding.accessBackend == .usbExtension)
    #expect(binding.rule == .interfaceSignature)
  }

  @Test
  func partialEndpointFieldsDoNotProduceNegativeClassification() async throws {
    let incompleteEndpoints = [
      PhysicalEndpointSignature(direction: .in, transferType: .interrupt),
      PhysicalEndpointSignature(address: 0x81, transferType: .interrupt),
      PhysicalEndpointSignature(address: 0x81, direction: .in),
    ]

    for (index, endpoint) in incompleteEndpoints.enumerated() {
      let device = USBTransportDevice(
        route: .rawUSB,
        serviceID: UInt64(20 + index),
        vendorID: 0x045E,
        productID: 0x028E,
        locationID: UInt32(20 + index)
      )
      let physicalDevice = PhysicalDevice(
        serviceAddress: device.serviceAddress,
        vendorID: device.vendorID,
        productID: device.productID,
        interfaces: [
          PhysicalInterfaceSignature(
            interfaceNumber: 0,
            alternateSetting: 0,
            interfaceClass: 0xFF,
            interfaceSubclass: 0x5D,
            interfaceProtocol: 0x01,
            hostTransport: .usb,
            usbRoute: .rawUSB,
            endpoints: [endpoint]
          )
        ]
      )
      let descriptions = try await USBControllerScanner.scanVendorSpecific(
        using: ScannerProvider(device: device, observation: physicalDevice)
      )

      let description = try #require(descriptions.first)
      #expect(description.classification == nil)
    }
  }

  @Test
  func hidInterfaceOnRawUSBIsNeverGenericHID() async throws {
    let device = USBTransportDevice(
      route: .rawUSB,
      serviceID: 30,
      vendorID: 0x1234,
      productID: 0x5678,
      locationID: 30
    )
    let physicalDevice = PhysicalDevice(
      serviceAddress: device.serviceAddress,
      vendorID: device.vendorID,
      productID: device.productID,
      interfaces: [
        PhysicalInterfaceSignature(
          interfaceNumber: 0,
          alternateSetting: 0,
          interfaceClass: 0x03,
          interfaceSubclass: 0,
          interfaceProtocol: 0,
          hostTransport: .usb,
          usbRoute: .rawUSB,
          endpoints: [
            PhysicalEndpointSignature(address: 0x81, direction: .in, transferType: .interrupt)
          ],
          hidLayout: HIDLayoutSummary(reportDescriptor: Data(GamepadHIDDescriptor.descriptor))
        )
      ]
    )
    let descriptions = try await USBControllerScanner.scanVendorSpecific(
      using: ScannerProvider(device: device, observation: physicalDevice)
    )

    let description = try #require(descriptions.first)
    #expect(description.classification == .unsupported(.noProtocolMatch))
  }

  @Test
  func observedEmptyInterfaceListCanReportUnsupported() async throws {
    let device = USBTransportDevice(
      route: .rawUSB,
      serviceID: 40,
      vendorID: 0x1234,
      productID: 0x5678,
      locationID: 40
    )
    // A parsed configuration with no interfaces is represented by [];
    // unavailable configuration facts are represented by nil.
    let physicalDevice = PhysicalDevice(
      serviceAddress: device.serviceAddress,
      vendorID: device.vendorID,
      productID: device.productID,
      interfaces: []
    )
    let descriptions = try await USBControllerScanner.scanVendorSpecific(
      using: ScannerProvider(device: device, observation: physicalDevice)
    )

    let description = try #require(descriptions.first)
    #expect(description.classification == .unsupported(.noProtocolMatch))
  }

  @Test
  func uncataloguedSignatureDeviceListsItsBindingLikeCatalogRow() async throws {
    let device = USBTransportDevice(
      route: .rawUSB,
      serviceID: 41,
      vendorID: 0x1234,
      productID: 0x5678,
      locationID: 42
    )
    let physicalDevice = PhysicalDevice(
      serviceAddress: device.serviceAddress,
      vendorID: device.vendorID,
      productID: device.productID,
      deviceClass: 0xFF,
      deviceSubclass: 0x47,
      deviceProtocol: 0xD0
    )
    let descriptions = try await USBControllerScanner.scanVendorSpecific(
      using: ScannerProvider(device: device, observation: physicalDevice)
    )

    let description = try #require(descriptions.first)
    #expect(description.protocolBinding?.rawValue == "XboxGIP:USB")
    #expect(description.parameters.isEmpty)
    guard case .bound(let binding) = description.classification else {
      Issue.record("expected a binding, got \(String(describing: description.classification))")
      return
    }
    #expect(binding.matchedPredicates == [.deviceClassSignature])
  }
}

private actor ScannerProvider: USBPhysicalDeviceObservationProvider {
  let device: USBTransportDevice
  let observation: PhysicalDevice

  init(device: USBTransportDevice, observation: PhysicalDevice) {
    self.device = device
    self.observation = observation
  }

  func devices() -> [USBTransportDevice] { [device] }

  func physicalDeviceObservations() -> [PhysicalDevice] { [observation] }

  func open(
    _: USBTransportDevice,
    options _: USBTransportOpenOptions
  ) -> any USBTransportSession { ScannerSession() }
}

private final class ScannerSession: USBTransportSession, @unchecked Sendable {
  func controlTransfer(_: USBControlTransferRequest, timeout _: UInt32) throws -> [UInt8] {
    throw USBTransportError.notSupported
  }

  func write(endpoint _: UInt8, data _: [UInt8], timeout _: UInt32) -> Int { 0 }

  func read(endpoint _: UInt8, length _: Int, timeout _: UInt32) -> [UInt8] { [] }
}
