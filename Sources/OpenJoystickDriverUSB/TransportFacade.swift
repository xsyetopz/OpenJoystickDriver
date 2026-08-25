import OpenJoystickDriverKit

/// Generic raw USB facade that selects an Apple transport from ownership evidence.
///
/// Accessible vendor-specific interfaces use app-side IOUSBHost. Devices covered
/// by OJD's restricted entitlement, or currently observed behind the DEXT, use
/// USBDriverKit. An open failure never falls through to a
/// different backend.
public actor OpenJoystickDriverUSBTransportProvider: USBTransportProvider {
  private let ioUSBHostProvider: any USBTransportProvider
  private let usbDriverKitProvider: any USBTransportProvider
  private let supportedRawUSBModels: Set<USBTransportModel>
  private let requiredDriverKitModels: Set<USBTransportModel>

  public init() {
    ioUSBHostProvider = IOUSBHostTransportProvider()
    usbDriverKitProvider = USBDriverKitTransportProvider()
    supportedRawUSBModels = Set(
      ParserRegistry().rawUSBProfileIdentifiers().map(USBTransportModel.init)
    )
    requiredDriverKitModels = Set(
      USBDriverKitExtensionConfiguration.microsoftProductIDs.map {
        USBTransportModel(
          vendorID: USBDriverKitExtensionConfiguration.microsoftVendorID,
          productID: $0
        )
      }
    )
  }

  init(
    ioUSBHostProvider: any USBTransportProvider,
    usbDriverKitProvider: any USBTransportProvider,
    supportedRawUSBModels: Set<USBTransportModel>,
    requiredDriverKitModels: Set<USBTransportModel>
  ) {
    self.ioUSBHostProvider = ioUSBHostProvider
    self.usbDriverKitProvider = usbDriverKitProvider
    self.supportedRawUSBModels = supportedRawUSBModels
    self.requiredDriverKitModels = requiredDriverKitModels
  }

  public func devices() async throws -> [USBTransportDevice] {
    let direct: Result<[USBTransportDevice], Error>
    do { direct = .success(try await ioUSBHostProvider.devices()) } catch {
      direct = .failure(error)
    }
    let driverKit: Result<[USBTransportDevice], Error>
    do { driverKit = .success(try await usbDriverKitProvider.devices()) } catch {
      driverKit = .failure(error)
    }

    switch (direct, driverKit) {
    case (.failure(let directError), .failure): throw directError
    case (.success(let directDevices), .success(let driverKitDevices)):
      return Self.selectDevices(
        direct: directDevices,
        driverKit: driverKitDevices,
        supportedRawUSBModels: supportedRawUSBModels,
        requiredDriverKitModels: requiredDriverKitModels
      )
    case (.success(let directDevices), .failure):
      return Self.selectDevices(
        direct: directDevices,
        driverKit: [],
        supportedRawUSBModels: supportedRawUSBModels,
        requiredDriverKitModels: requiredDriverKitModels
      )
    case (.failure, .success(let driverKitDevices)):
      return Self.selectDevices(
        direct: [],
        driverKit: driverKitDevices,
        supportedRawUSBModels: supportedRawUSBModels,
        requiredDriverKitModels: requiredDriverKitModels
      )
    }
  }

  public func open(_ device: USBTransportDevice, options: USBTransportOpenOptions) async throws
    -> any USBTransportSession
  {
    switch device.route {
    case .ioUSBHost: return try await ioUSBHostProvider.open(device, options: options)
    case .usbDriverKit: return try await usbDriverKitProvider.open(device, options: options)
    }
  }

  static func selectDevices(
    direct: [USBTransportDevice],
    driverKit: [USBTransportDevice],
    supportedRawUSBModels: Set<USBTransportModel>,
    requiredDriverKitModels: Set<USBTransportModel>
  ) -> [USBTransportDevice] {
    let observedDriverKitLocations = Set(driverKit.map(USBTransportLocation.init))
    let selectedDirect = direct.filter { device in
      supportedRawUSBModels.contains(USBTransportModel(device))
        && !requiredDriverKitModels.contains(USBTransportModel(device))
        && !observedDriverKitLocations.contains(USBTransportLocation(device))
    }
    let selectedDriverKit = driverKit.filter {
      supportedRawUSBModels.contains(USBTransportModel($0))
    }
    return (selectedDriverKit + selectedDirect).sorted(by: deviceOrder)
  }

  private static func deviceOrder(_ lhs: USBTransportDevice, _ rhs: USBTransportDevice) -> Bool {
    (lhs.vendorID, lhs.productID, lhs.locationID, lhs.route.rawValue, lhs.serviceID) < (
      rhs.vendorID, rhs.productID, rhs.locationID, rhs.route.rawValue, rhs.serviceID
    )
  }
}

struct USBTransportModel: Hashable, Sendable {
  let vendorID: UInt16
  let productID: UInt16

  init(vendorID: UInt16, productID: UInt16) {
    self.vendorID = vendorID
    self.productID = productID
  }

  init(_ device: USBTransportDevice) {
    self.init(vendorID: device.vendorID, productID: device.productID)
  }

  init(_ identifier: DeviceIdentifier) {
    self.init(vendorID: identifier.vendorID, productID: identifier.productID)
  }
}

private struct USBTransportLocation: Hashable, Sendable {
  let vendorID: UInt16
  let productID: UInt16
  let locationID: UInt32

  init(_ device: USBTransportDevice) {
    vendorID = device.vendorID
    productID = device.productID
    locationID = device.locationID
  }
}
