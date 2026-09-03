import IOKit
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverUSB

struct TransportFacadeTests {
  @Test func facadeExposesPassiveObservationCapabilityWithoutChangingAdmissionOwnership() {
    let provider: any USBTransportObservationProvider = OpenJoystickDriverUSBTransportProvider()
    _ = provider
    #expect(
      OpenJoystickDriverUSBTransportProvider.selectDevices(
        direct: [device(route: .ioUSBHost, serviceID: 1, vendorID: 0xFFFF, productID: 1)],
        driverKit: [],
        supportedRawUSBModels: [],
        requiredDriverKitModels: []
      ).isEmpty
    )
  }

  @Test func defaultProviderResolutionHookRetainsConfiguredProfile() async {
    let provider = FakeUSBTransportProvider()
    let configured = DeviceTransportProfile.gipDefault

    #expect(
      await provider.resolveTransportProfile(
        for: device(route: .ioUSBHost, serviceID: 1),
        configured: configured
      ) == configured
    )
  }

  @Test func driverKitResolutionDoesNotUseDescriptorRouteFallback() {
    let configured = DeviceTransportProfile.gipDefault
    let observation = ControllerTransportObservation(
      vendorID: 0x045E,
      productID: 0x0B12,
      interfaces: [
        USBInterfaceTransportFacts(
          interfaceNumber: 3,
          interfaceClass: 0xFF,
          endpoints: [
            USBEndpointTransportFacts(address: 0x84, isInterrupt: true, isInput: true),
            USBEndpointTransportFacts(address: 0x04, isInterrupt: true, isInput: false)
          ]
        )
      ]
    )

    #expect(
      OpenJoystickDriverUSBTransportProvider.resolveTransportProfile(
        route: .usbDriverKit,
        configured: configured,
        observation: observation
      ) == configured
    )
  }

  @Test func facadeResolutionUsesCompletePassiveInterruptPair() {
    let configured = DeviceTransportProfile.gipDefault
    let observation = ControllerTransportObservation(
      vendorID: 0x3537,
      productID: 0x1010,
      interfaces: [
        USBInterfaceTransportFacts(
          interfaceNumber: 2,
          alternateSetting: 1,
          interfaceClass: 0xFF,
          endpoints: [
            USBEndpointTransportFacts(address: 0x84, isInterrupt: true, isInput: true),
            USBEndpointTransportFacts(address: 0x04, isInterrupt: true, isInput: false)
          ]
        )
      ]
    )

    let resolved = OpenJoystickDriverUSBTransportProvider.resolveTransportProfile(
      route: .ioUSBHost,
      configured: configured,
      observation: observation
    )

    #expect(resolved.interfaceNumber == 2)
    #expect(resolved.alternateSetting == 1)
    #expect(resolved.inputEndpoint == 0x84)
    #expect(resolved.outputEndpoint == 0x04)
  }

  @Test func mapsUnsupportedAndBadArgumentToEquivalentUnsupportedTransportErrors() {
    #expect(IOUSBHostTransportProvider.transportError(kIOReturnUnsupported) == .notSupported)
    #expect(IOUSBHostTransportProvider.transportError(kIOReturnBadArgument) == .notSupported)
  }

  @Test func accessibleThirdPartyDeviceUsesDirectIOUSBHost() {
    let direct = device(route: .ioUSBHost, serviceID: 1, vendorID: 0x054C, productID: 0x0268)

    #expect(
      OpenJoystickDriverUSBTransportProvider.selectDevices(
        direct: [direct],
        driverKit: [],
        supportedRawUSBModels: [USBTransportModel(direct)],
        requiredDriverKitModels: []
      ) == [direct]
    )
  }

  @Test func entitlementRestrictedModelNeverFallsBackToDirectIOUSBHost() {
    let direct = device(route: .ioUSBHost, serviceID: 1, vendorID: 0x045E, productID: 0x0B12)

    #expect(
      OpenJoystickDriverUSBTransportProvider.selectDevices(
        direct: [direct],
        driverKit: [],
        supportedRawUSBModels: [USBTransportModel(direct)],
        requiredDriverKitModels: [USBTransportModel(vendorID: 0x045E, productID: 0x0B12)]
      ).isEmpty
    )
  }

  @Test func observedDriverKitOwnerWinsOnlyForTheSamePhysicalDevice() {
    let directClaimed = device(
      route: .ioUSBHost,
      serviceID: 1,
      vendorID: 0x3537,
      productID: 0x1010,
      locationID: 7
    )
    let driverKit = device(
      route: .usbDriverKit,
      serviceID: 2,
      vendorID: 0x3537,
      productID: 0x1010,
      locationID: 7
    )
    let anotherDirect = device(
      route: .ioUSBHost,
      serviceID: 3,
      vendorID: 0x3537,
      productID: 0x1010,
      locationID: 8
    )

    let selected = OpenJoystickDriverUSBTransportProvider.selectDevices(
      direct: [directClaimed, anotherDirect],
      driverKit: [driverKit],
      supportedRawUSBModels: [USBTransportModel(directClaimed)],
      requiredDriverKitModels: []
    )

    #expect(selected == [driverKit, anotherDirect])
  }

  @Test func oneDiscoveryBackendCanOperateWhenTheOtherIsUnavailable() async throws {
    let directDevice = device(route: .ioUSBHost, serviceID: 1)
    let direct = FakeUSBTransportProvider(devicesResult: .success([directDevice]))
    let unavailable = FakeUSBTransportProvider(devicesResult: .failure(.disconnected))
    let provider = OpenJoystickDriverUSBTransportProvider(
      ioUSBHostProvider: direct,
      usbDriverKitProvider: unavailable,
      supportedRawUSBModels: [USBTransportModel(directDevice)],
      requiredDriverKitModels: []
    )

    #expect(try await provider.devices() == [directDevice])
  }

  @Test func openDispatchesByRecordedRouteWithoutFallback() async {
    let direct = FakeUSBTransportProvider(openResult: .failure(.accessDenied))
    let driverKit = FakeUSBTransportProvider()
    let provider = OpenJoystickDriverUSBTransportProvider(
      ioUSBHostProvider: direct,
      usbDriverKitProvider: driverKit,
      supportedRawUSBModels: [USBTransportModel(vendorID: 0x1234, productID: 0x5678)],
      requiredDriverKitModels: []
    )

    do {
      _ = try await provider.open(
        device(route: .ioUSBHost, serviceID: 1),
        options: USBTransportOpenOptions(interfaceNumber: 2)
      )
      Issue.record("Expected the selected IOUSBHost backend to fail")
    } catch { #expect(error as? USBTransportError == .accessDenied) }
    #expect(await direct.openCount == 1)
    #expect(await driverKit.openCount == 0)
  }

  @Test func directDiscoveryUsesDeviceServiceBeforeInterfacesExist() {
    let devices = IOUSBHostTransportProvider.devices(from: [
      IOUSBHostDeviceFacts(
        serviceID: 10,
        vendorID: 0x1234,
        productID: 0x5678,
        locationID: 9,
        productName: "Controller",
        serialNumber: "serial"
      )
    ])

    #expect(
      devices == [
        device(
          route: .ioUSBHost,
          serviceID: 10,
          vendorID: 0x1234,
          productID: 0x5678,
          locationID: 9,
          productName: "Controller",
          serialNumber: "serial"
        )
      ]
    )
  }

  private func device(
    route: USBTransportRoute,
    serviceID: UInt64,
    vendorID: UInt16 = 0x1234,
    productID: UInt16 = 0x5678,
    locationID: UInt32 = 1,
    productName: String? = nil,
    serialNumber: String? = nil
  ) -> USBTransportDevice {
    USBTransportDevice(
      route: route,
      serviceID: serviceID,
      vendorID: vendorID,
      productID: productID,
      locationID: locationID,
      productName: productName,
      serialNumber: serialNumber
    )
  }
}

private actor FakeUSBTransportProvider: USBTransportProvider {
  private let devicesResult: Result<[USBTransportDevice], USBTransportError>
  private let openResult: Result<any USBTransportSession, USBTransportError>
  private(set) var openCount = 0

  init(
    devicesResult: Result<[USBTransportDevice], USBTransportError> = .success([]),
    openResult: Result<any USBTransportSession, USBTransportError> = .success(
      FakeUSBTransportSession()
    )
  ) {
    self.devicesResult = devicesResult
    self.openResult = openResult
  }

  func devices() throws -> [USBTransportDevice] { try devicesResult.get() }

  func open(_ device: USBTransportDevice, options: USBTransportOpenOptions) throws
    -> any USBTransportSession
  {
    openCount += 1
    return try openResult.get()
  }
}

private final class FakeUSBTransportSession: USBTransportSession, @unchecked Sendable {
  func writeInterruptPacket(endpoint: UInt8, data: [UInt8], timeout: UInt32) throws -> Int {
    data.count
  }

  func readInterruptPacket(endpoint: UInt8, length: Int, timeout: UInt32) throws -> [UInt8] { [] }
}
