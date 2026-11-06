import IOKit
import OpenJoystickDriverKit
import SwifterKit

/// The identity of the `IOUSBHostDevice` a DEXT service sits on, read from the IORegistry.
struct USBDriverKitParentDevice: Sendable, Hashable {
  /// The USB vendor ID.
  var vendorID: UInt16
  /// The USB product ID.
  var productID: UInt16
  /// The USB location ID, when the registry has one.
  var locationID: UInt32?
  /// The product name, when the registry has one.
  var productName: String?
  /// The serial number, when the registry has one.
  var serialNumber: String?
  /// The manufacturer name, when the registry has one.
  var manufacturer: String?
  /// The `bcdDevice` release number, when the registry has one.
  var deviceRelease: UInt16?
}

/// Host adapter for services owned by OJD's restricted USBDriverKit extension.
public actor USBDriverKitTransportProvider: USBPhysicalDeviceObservationProvider {
  /// The client that lists and opens the extension's services.
  private let client: DriverClient
  /// Reads the parent device of the extension service with the given registry entry ID.
  private let parentDevice: @Sendable (UInt64) -> USBDriverKitParentDevice?
  /// The extension services of the latest listing, by registry entry ID.
  private var servicesByID: [UInt64: DriverService] = [:]
  /// The parent devices of the latest listing, by service ID.
  private var parentsByID: [UInt64: USBDriverKitParentDevice] = [:]
  /// DEXT services the latest `devices()` could not identify, so each is logged once.
  private var unlistedServiceIDs: Set<UInt64> = []

  /// Creates the provider over `client`.
  public init(client: DriverClient = DriverClient()) {
    self.init(client: client, parentDevice: Self.registryParentDevice(serviceID:))
  }

  /// Creates the provider over `client` with the given parent device reader.
  init(
    client: DriverClient,
    parentDevice: @escaping @Sendable (UInt64) -> USBDriverKitParentDevice?
  ) {
    self.client = client
    self.parentDevice = parentDevice
  }

  /// Lists the USB devices that the extension's services drive.
  ///
  /// A service that no vendor and product ID identifies is left out and logged once.
  ///
  /// - Throws: The error of the driver client when it cannot list the services.
  public func devices() async throws -> [USBTransportDevice] {
    let services = try await client.services(
      matching: USBDriverKitExtensionConfiguration.driver.serviceMatch
    )
    servicesByID = Dictionary(uniqueKeysWithValues: services.map { ($0.id, $0) })
    parentsByID = services.reduce(into: [:]) { parents, service in
      parents[service.id] = parentDevice(service.id)
    }
    let devices = services.map { ($0.id, Self.device($0, parent: parentsByID[$0.id])) }
    // The facade keeps a DEXT model off direct IOUSBHost, so an unlisted service hides its
    // controller entirely; say so once per service rather than on every poll.
    let unlisted = Set(devices.compactMap { $0.1 == nil ? $0.0 : nil })
    for serviceID in unlisted.subtracting(unlistedServiceIDs).sorted() {
      print(
        "[USBDriverKitTransport] DEXT service \(serviceID) not listed: neither a parent "
          + "IOUSBHostDevice nor the service itself has a scalar idVendor and idProduct"
      )
    }
    unlistedServiceIDs = unlisted
    return devices.compactMap(\.1)
  }

  /// Returns the observations of the services of the latest listing, in service ID order.
  public func physicalDeviceObservations() throws -> [PhysicalDevice] {
    servicesByID.values.sorted { $0.id < $1.id }.compactMap {
      Self.physicalDeviceObservation(from: $0, parent: parentsByID[$0.id])
    }
  }

  /// Opens the extension service of `device` and applies the configuration and alternate setting of
  /// `options`.
  ///
  /// The listing is refreshed when the service is not known yet. An exclusive-access failure names
  /// the owner that the IOUSBHost interface shows.
  ///
  /// - Throws: ``USBTransportError/notSupported`` for a device that is not on the extension route,
  ///   ``USBTransportError/notFound`` when the service is not listed, and the mapped driver error
  ///   otherwise.
  public func open(
    _ device: USBTransportDevice,
    options: USBTransportOpenOptions
  ) async throws -> any USBTransportSession {
    guard device.route == .usbExtension else { throw USBTransportError.notSupported }
    let service: DriverService
    if let cached = servicesByID[device.serviceID] {
      service = cached
    } else {
      _ = try await devices()
      guard let rediscovered = servicesByID[device.serviceID] else {
        throw USBTransportError.notFound
      }
      service = rediscovered
    }

    do {
      let driverSession = try await client.open(service)
      let runtime = try await DriverRuntimeConnection.connect(
        session: driverSession,
        requiring: .usb
      )
      let context = await DriverContext(runtime: runtime)
      let session = USBDriverKitTransportSession(context: context) { await runtime.close() }
      do {
        if let configuration = options.configurationValue {
          try await session.controlTransfer(
            USBControlTransferRequest(
              kind: .standard,
              recipient: .device,
              request: USBRequest.setConfiguration,
              value: UInt16(configuration)
            ),
            timeout: 5_000
          )
        }
        if options.alternateSetting != 0 {
          try await context.usbSelectAlternateSetting(options.alternateSetting)
        }
        return session
      } catch {
        await session.close()
        throw Self.transportError(error)
      }
    } catch {
      let mapped = Self.transportError(error)
      guard case .ownedByAnotherClient(nil) = mapped else { throw mapped }
      throw USBTransportError.ownedByAnotherClient(
        owner: IOUSBHostTransportProvider.interfaceExclusiveOwner(
          of: device,
          interfaceNumber: options.interfaceNumber
        )
      )
    }
  }

  /// The device a DEXT service drives, identified by the parent `IOUSBHostDevice` first and the
  /// service's own properties second.
  ///
  /// The service carries its personality, which lists the products as `idProductArray` when the
  /// extension matches more than one, so without a parent it has no scalar `idProduct` and yields
  /// nil.
  static func device(
    _ service: DriverService,
    parent: USBDriverKitParentDevice? = nil
  ) -> USBTransportDevice? {
    guard let vendorID = parent?.vendorID ?? uint16Property(service.properties["idVendor"]),
      let productID = parent?.productID ?? uint16Property(service.properties["idProduct"])
    else { return nil }
    let observedPhysicalLocationIdentifier =
      parent?.locationID
      ?? uint32Property(service.properties["locationID"])
      ?? uint32Property(service.properties["LocationID"])
    let locationID = observedPhysicalLocationIdentifier ?? UInt32(truncatingIfNeeded: service.id)
    return USBTransportDevice(
      route: .usbExtension,
      serviceID: service.id,
      vendorID: vendorID,
      productID: productID,
      locationID: locationID,
      observedPhysicalLocationIdentifier: observedPhysicalLocationIdentifier,
      productName: parent?.productName
        ?? stringProperty(
          service.properties["USB Product Name"] ?? service.properties["Product Name"]
        ),
      serialNumber: parent?.serialNumber
        ?? stringProperty(
          service.properties["USB Serial Number"] ?? service.properties["Serial Number"]
        ),
      manufacturer: parent?.manufacturer,
      deviceRelease: parent?.deviceRelease
    )
  }

  /// The observation of the device `device(_:parent:)` lists for a DEXT service.
  static func physicalDeviceObservation(
    from service: DriverService,
    parent: USBDriverKitParentDevice? = nil
  ) -> PhysicalDevice? {
    guard let device = device(service, parent: parent) else { return nil }
    return PhysicalDevice(
      serviceAddress: device.serviceAddress,
      vendorID: device.vendorID,
      productID: device.productID,
      productName: device.productName,
      serialNumber: device.serialNumber,
      physicalLocationIdentifier: device.observedPhysicalLocationIdentifier,
      interfaces: [
        PhysicalInterfaceSignature(
          hostTransport: .usb,
          accessBackend: .usbExtension,
          usbRoute: .usbExtension
        )
      ]
    )
  }

  /// The identity of the nearest `IOUSBHostDevice` among the service-plane parents of the
  /// IORegistry entry `serviceID`, at most 8 levels up.
  ///
  /// Nil when there is no such parent or it has no `idVendor` and `idProduct`.
  static func registryParentDevice(serviceID: UInt64) -> USBDriverKitParentDevice? {
    var entry = IOServiceGetMatchingService(
      kIOMainPortDefault,
      IORegistryEntryIDMatching(serviceID)
    )
    guard entry != 0 else { return nil }
    var depth = 0
    while IOObjectConformsTo(entry, "IOUSBHostDevice") == 0 {
      var parent: io_registry_entry_t = 0
      let result = IORegistryEntryGetParentEntry(entry, kIOServicePlane, &parent)
      IOObjectRelease(entry)
      depth += 1
      guard result == KERN_SUCCESS else { return nil }
      entry = parent
      guard depth <= 8 else {
        IOObjectRelease(entry)
        return nil
      }
    }
    defer { IOObjectRelease(entry) }
    func value(_ key: String) -> Any? {
      IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?
        .takeRetainedValue()
    }
    func string(_ keys: [String]) -> String? { keys.lazy.compactMap { value($0) as? String }.first }
    guard let vendorID = (value("idVendor") as? UInt64).flatMap(UInt16.init(exactly:)),
      let productID = (value("idProduct") as? UInt64).flatMap(UInt16.init(exactly:))
    else { return nil }
    return USBDriverKitParentDevice(
      vendorID: vendorID,
      productID: productID,
      locationID: (value("locationID") as? UInt64).flatMap(UInt32.init(exactly:)),
      productName: string(["USB Product Name", "Product Name"]),
      serialNumber: string(["USB Serial Number", "Serial Number"]),
      manufacturer: string(["USB Vendor Name", "Vendor Name"]),
      deviceRelease: (value("bcdDevice") as? UInt64).flatMap(UInt16.init(exactly:))
    )
  }

  /// Reads `property` as a 16-bit unsigned integer, or nil when it is missing or out of range.
  private static func uint16Property(_ property: DriverProperty?) -> UInt16? {
    guard let value = unsignedProperty(property) else { return nil }
    return UInt16(exactly: value)
  }

  /// Reads `property` as a 32-bit unsigned integer, or nil when it is missing or out of range.
  private static func uint32Property(_ property: DriverProperty?) -> UInt32? {
    guard let value = unsignedProperty(property) else { return nil }
    return UInt32(exactly: value)
  }

  /// Reads `property` as an unsigned integer, or nil when it is missing, negative or not a number.
  private static func unsignedProperty(_ property: DriverProperty?) -> UInt64? {
    switch property {
    case .unsignedInteger(let value): value
    case .integer(let value) where value >= 0: UInt64(value)
    default: nil
    }
  }

  /// Reads `property` as a string, or nil when it is not one.
  private static func stringProperty(_ property: DriverProperty?) -> String? {
    guard case .string(let value) = property else { return nil }
    return value
  }

  /// Converts `request` to the extension's control request.
  static func controlRequest(for request: USBControlTransferRequest) -> USBControlRequest {
    USBControlRequest(
      requestType: request.requestType,
      request: request.request,
      value: request.value,
      index: request.index,
      length: request.length
    )
  }

  /// Maps a driver, runtime or context `error` to a transport error.
  static func transportError(_ error: Error) -> USBTransportError {
    if let transportError = error as? USBTransportError { return transportError }
    switch error as? USBRuntimeError {
    case .emptyTransfer, .directionMismatch, .invalidOutputLength, .transferTooLarge,
      .invalidBundleRing, .invalidBundledTransfer, .invalidEndpointPolicy:
      return .notSupported
    case .invalidResponse, nil: break
    }
    if let contextError = error as? DriverContextError {
      return contextError == .notConnected ? .disconnected : .notSupported
    }
    guard let driverKitError = error as? DriverKitError else {
      return .platform(code: 0, message: String(describing: error))
    }
    switch driverKitError.kind {
    case .serviceUnavailable, .sessionClosed: return .disconnected
    case .invalidServiceClass, .bufferTooLarge: return .notSupported
    case .ioReturn(let code):
      switch code {
      case kIOReturnTimeout: return .timeout
      case kIOReturnNoDevice, kIOReturnNotAttached, kIOReturnNotOpen: return .disconnected
      case kIOReturnExclusiveAccess: return .ownedByAnotherClient(owner: nil)
      case kIOReturnNotPermitted, kIOReturnNotPrivileged: return .accessDenied
      case kIOReturnNotFound: return .notFound
      case kIOReturnUnsupported: return .notSupported
      case kIOReturnIOError: return .inputOutput
      default: return .platform(code: code, message: driverKitError.description)
      }
    }
  }
}

/// The raw USB session of one opened extension service.
actor USBDriverKitTransportSession: USBTransportSession {
  /// The driver context that carries the transfers.
  private let context: DriverContext
  /// Closes the connection to the driver runtime.
  private let closeRuntime: @Sendable () async -> Void
  /// Whether the session is closed.
  private var isClosed = false

  /// Exclusive while the session is open, and unknown after it closes.
  var inputOwnership: HIDInputOwnership { isClosed ? .unknown : .exclusive }

  /// Creates the session over `context`, which `closeRuntime` shuts down.
  init(context: DriverContext, closeRuntime: @escaping @Sendable () async -> Void) {
    self.context = context
    self.closeRuntime = closeRuntime
  }

  /// Writes `data` to the endpoint `endpoint` and returns the number of bytes written.
  ///
  /// - Throws: ``USBTransportError/disconnected`` when the session is closed, and the mapped driver
  ///   error otherwise.
  func write(endpoint: UInt8, data: [UInt8], timeout: UInt32) async throws -> Int {
    guard !isClosed else { throw USBTransportError.disconnected }
    do {
      return Int(
        try await context.usbWrite(endpoint: endpoint, data: data, timeout: timeout)
          .bytesTransferred
      )
    } catch { throw USBDriverKitTransportProvider.transportError(error) }
  }

  /// Reads up to `length` bytes from the endpoint `endpoint`.
  ///
  /// - Throws: ``USBTransportError/disconnected`` when the session is closed, and the mapped driver
  ///   error otherwise.
  func read(endpoint: UInt8, length: Int, timeout: UInt32) async throws -> [UInt8] {
    guard !isClosed else { throw USBTransportError.disconnected }
    do {
      return try await context.usbRead(endpoint: endpoint, length: length, timeout: timeout).data
    } catch { throw USBDriverKitTransportProvider.transportError(error) }
  }

  /// Sends the control transfer `request` and returns the bytes it received.
  ///
  /// - Throws: ``USBTransportError/disconnected`` when the session is closed, and the mapped driver
  ///   error otherwise.
  @discardableResult
  func controlTransfer(
    _ request: USBControlTransferRequest,
    timeout: UInt32
  ) async throws -> [UInt8] {
    guard !isClosed else { throw USBTransportError.disconnected }
    do {
      return try await context.usbControlTransfer(
        USBDriverKitTransportProvider.controlRequest(for: request),
        data: request.outputData,
        timeout: timeout
      ).data
    } catch { throw USBDriverKitTransportProvider.transportError(error) }
  }

  /// Closes the session and the driver runtime connection.
  func close() async {
    guard !isClosed else { return }
    isClosed = true
    await closeRuntime()
  }
}
