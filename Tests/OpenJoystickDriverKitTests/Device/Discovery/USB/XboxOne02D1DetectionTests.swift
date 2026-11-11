import OpenJoystickDriverTestSupport
import SwifterKit
import Testing

@testable import OpenJoystickDriverKit
@testable import OpenJoystickDriverUSB

/// A DriverKit transport that publishes one service and refuses every open.
private struct SingleServiceTransport: DriverTransport {
  struct OpenRefused: Error {}

  let service: DriverService

  func services(matching _: DriverServiceMatch) -> [DriverService] { [service] }

  func open(_: DriverService, type _: UInt32) throws -> any DriverConnection {
    throw OpenRefused()
  }
}

/// Issue #18: pins how `045E:02D1` (Xbox One model 1537) reaches raw USB detection.
struct XboxOne02D1DetectionTests {
  private static let vendorID: UInt16 = 0x045E
  private static let productID: UInt16 = 0x02D1

  @Test
  func dextRouteServiceIsClaimedOnInterfaceZero() async {
    let device = USBTransportDevice(
      route: .usbExtension,
      serviceID: 40,
      vendorID: Self.vendorID,
      productID: Self.productID,
      locationID: 40
    )
    let provider = USBDiscoveryRecordingProvider(devices: [device])
    let manager = DeviceManager(
      dispatcher: LoggingOutputDispatcher(),
      installationKey: testPortKeyInstallationKey,
      usbTransportProvider: provider
    )

    #expect(
      await manager.handleUSBDeviceAdded(device, provider: provider)
        == .claimed([
          LogicalControllerID(
            vendorID: Self.vendorID,
            productID: Self.productID,
            locationID: 40,
            interfaceNumber: 0
          )
        ])
    )
    await manager.stop()
  }

  @Test
  func extensionMatchesTheModel() {
    #expect(USBDriverKitExtensionConfiguration.microsoftProductIDs.contains(Self.productID))
  }

  private static let parentLocationID: UInt32 = 0x1410_0000

  /// A DEXT service as the extension publishes it: the generated personality lists seven
  /// products, so SwifterKit writes `idProductArray` and no scalar `idProduct`.
  private static let dextService = DriverService(
    id: 41,
    name: "SwifterKitRuntimeService",
    properties: [
      "idVendor": .unsignedInteger(UInt64(vendorID)),
      "idProductArray": .array(
        USBDriverKitExtensionConfiguration.microsoftProductIDs.map {
          .unsignedInteger(UInt64($0))
        }
      ),
      "bInterfaceNumber": .unsignedInteger(0),
    ]
  )

  /// The `IOUSBHostDevice` the DEXT service sits on.
  private static let parent = USBDriverKitParentDevice(
    vendorID: vendorID,
    productID: productID,
    locationID: parentLocationID,
    productName: "Controller",
    serialNumber: "0123456789"
  )

  /// The device the DEXT route lists for the service: identity from the parent USB device, the
  /// service's registry ID for the user-client open.
  private static let dextDevice = USBTransportDevice(
    route: .usbExtension,
    serviceID: 41,
    vendorID: vendorID,
    productID: productID,
    locationID: parentLocationID,
    observedPhysicalLocationIdentifier: parentLocationID,
    productName: "Controller",
    serialNumber: "0123456789"
  )

  /// The service's personality has no scalar `idProduct`, so the product comes from the parent
  /// `IOUSBHostDevice`, as recorded in `docs/testing/xbox-one-02d1.md`.
  @Test
  func dextServiceTakesIdentityFromParentUSBDevice() {
    #expect(
      USBDriverKitTransportProvider.device(Self.dextService, parent: Self.parent) == Self.dextDevice
    )
  }

  /// Without a parent USB device the service still yields no device.
  @Test
  func dextServiceWithoutParentYieldsNoDevice() {
    #expect(USBDriverKitTransportProvider.device(Self.dextService) == nil)
  }

  @Test
  func providerListsDextServiceThroughParentLookup() async throws {
    let parent = Self.parent
    let provider = USBDriverKitTransportProvider(
      client: DriverClient(transport: SingleServiceTransport(service: Self.dextService))
    ) { _ in parent }

    let devices = try await provider.devices()
    let observations = await provider.physicalDeviceObservations()

    #expect(devices == [Self.dextDevice])
    #expect(observations.count == 1)
    let observation = try #require(observations.first)
    #expect(observation.serviceAddress == Self.dextDevice.serviceAddress)
    #expect(observation.vendorID == Self.vendorID)
    #expect(observation.productID == Self.productID)
    #expect(observation.productName == Self.dextDevice.productName)
    #expect(observation.serialNumber == Self.dextDevice.serialNumber)
    #expect(observation.physicalLocationIdentifier == Self.parentLocationID)
  }

  @Test
  func facadeSelectsDextRouteModel() {
    let direct = USBTransportDevice(
      route: .rawUSB,
      serviceID: 42,
      vendorID: Self.vendorID,
      productID: Self.productID,
      locationID: Self.parentLocationID
    )
    let model = ControllerModelID(direct)
    #expect(
      OpenJoystickDriverUSBTransportProvider.selectDevices(
        direct: [direct],
        driverKit: [Self.dextDevice],
        supportedRawUSBModels: [model],
        requiredDriverKitModels: [model]
      ) == [Self.dextDevice]
    )
  }

  @Test
  func facadeKeepsTheModelOffDirectIOUSBHostWithoutADextService() {
    let direct = USBTransportDevice(
      route: .rawUSB,
      serviceID: 42,
      vendorID: Self.vendorID,
      productID: Self.productID,
      locationID: 42
    )
    let model = ControllerModelID(direct)
    #expect(
      OpenJoystickDriverUSBTransportProvider.selectDevices(
        direct: [direct],
        driverKit: [],
        supportedRawUSBModels: [model],
        requiredDriverKitModels: [model]
      ).isEmpty
    )
  }
}
