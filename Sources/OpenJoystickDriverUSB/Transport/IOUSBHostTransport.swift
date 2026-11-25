import Foundation
import IOKit
import IOUSBHost
public import OpenJoystickDriverKit

/// Direct app-side raw USB transport backed by Apple's IOUSBHost framework.
///
/// This backend owns accessible vendor-specific interfaces without requiring a
/// DriverKit extension. Services that require OJD's restricted DEXT are filtered
/// by `OpenJoystickDriverUSBTransportProvider` before callers see them.
public actor IOUSBHostTransportProvider: USBTransportProvider {
  /// Creates the provider.
  public init() {}

  /// Lists the raw USB devices that the IOUSBHost registry shows, in vendor, product, location and
  /// service order.
  ///
  /// - Throws: ``USBTransportError`` when the registry cannot be matched.
  public func devices() throws -> [USBTransportDevice] {
    try Self.devices(from: Self.deviceFacts())
  }

  /// Opens the interface `options.interfaceNumber` of `device` for raw USB transfers.
  ///
  /// The configuration is set first, only when the device does not already run it. The open waits
  /// up to one second for the interface service to appear.
  ///
  /// - Throws: ``USBTransportError/notSupported`` for a device that is not on the raw USB route,
  ///   ``USBTransportError/notFound`` when the interface does not appear, and the error that
  ///   ``openError(_:interfaceOwner:processID:)`` maps when IOUSBHost refuses the open.
  public func open(
    _ device: USBTransportDevice,
    options: USBTransportOpenOptions
  ) async throws -> any USBTransportSession {
    guard device.route == .rawUSB else { throw USBTransportError.notSupported }

    try await Self.configureDevice(device, options: options)

    let service = try await Self.waitForInterfaceService(
      device: device,
      interfaceNumber: options.interfaceNumber
    )
    defer { IOObjectRelease(service) }

    do {
      let interface = try Self.openInterface(
        service: service,
        device: device,
        interfaceNumber: options.interfaceNumber
      )
      if options.alternateSetting != 0 {
        try interface.selectAlternateSetting(Int(options.alternateSetting))
      }
      return IOUSBHostTransportSession(
        interface: interface,
        device: device,
        interfaceNumber: options.interfaceNumber
      )
    } catch { throw Self.openError(error, interfaceService: service) }
  }

  /// Opens the interface `service`, number `interfaceNumber` of `device`, with its own queue.
  static func openInterface(
    service: io_service_t,
    device: USBTransportDevice,
    interfaceNumber: UInt8
  ) throws -> IOUSBHostInterface {
    try unsafe IOUSBHostInterface(
      __ioService: service,
      options: [],
      queue: DispatchQueue(
        label: "com.openjoystickdriver.iousbhost.\(device.locationID).\(interfaceNumber)"
      ),
      interestHandler: nil
    )
  }

  /// Returns when the exclusive owner of the interface lets go, by an IOKit interest notification
  /// on the interface service.
  static func waitForRelease(of device: USBTransportDevice, interfaceNumber: UInt8) async throws {
    guard let service = try interfaceService(for: device, interfaceNumber: interfaceNumber)
    else { throw USBTransportError.notFound }
    defer { IOObjectRelease(service) }
    let watch = InterfaceReleaseWatch()
    try watch.start(service: service)
    await withTaskCancellationHandler {
      await watch.wait()
    } onCancel: {
      watch.finish()
    }
    watch.stop()
  }

  /// The owner the interface of `device` names, or nil when it names none or does not exist.
  static func interfaceExclusiveOwner(
    of device: USBTransportDevice,
    interfaceNumber: UInt8
  ) -> String? {
    guard let service = try? interfaceService(for: device, interfaceNumber: interfaceNumber)
    else { return nil }
    defer { IOObjectRelease(service) }
    return interfaceExclusiveOwner(of: service)
  }

  /// Returns the `UsbExclusiveOwner` property of `interfaceService`, or nil when it has none.
  static func interfaceExclusiveOwner(of interfaceService: io_service_t) -> String? {
    unsafe IORegistryEntryCreateCFProperty(
      interfaceService,
      exclusiveOwnerKey as CFString,
      kCFAllocatorDefault,
      0
    )?.takeRetainedValue() as? String
  }

  /// The IORegistry property that names the client holding a USB device or interface open.
  static let exclusiveOwnerKey = "UsbExclusiveOwner"

  /// Maps the open failure `error` of the interface `interfaceService` to a transport error.
  private static func openError(
    _ error: any Error,
    interfaceService: io_service_t
  ) -> USBTransportError {
    openError(
      IOReturn(truncatingIfNeeded: (error as NSError).code),
      interfaceOwner: interfaceExclusiveOwner(of: interfaceService),
      processID: getpid()
    )
  }

  /// A failed open of an interface that names an owner other than process `processID` is
  /// ``USBTransportError/ownedByAnotherClient(owner:)`` whatever `code` is, because macOS 27
  /// refuses such an open with `kIOReturnInternalError` as well as `kIOReturnExclusiveAccess`.
  ///
  /// Access refusals stay `accessDenied`.
  static func openError(
    _ code: IOReturn,
    interfaceOwner: String?,
    processID: Int32
  ) -> USBTransportError {
    let mapped = transportError(code)
    guard let interfaceOwner, !interfaceOwner.hasPrefix("pid \(processID),"),
      mapped != .accessDenied
    else {
      return transportError(
        code,
        exclusiveOwner: code == kIOReturnExclusiveAccess ? interfaceOwner : nil
      )
    }
    return .ownedByAnotherClient(owner: interfaceOwner)
  }

  /// The device's own `UsbExclusiveOwner` registry property, such as `pid 11070, steam_osx`.
  ///
  /// It is read without a parent search, because a hub's owner is not the device's.
  public func exclusiveOwner(of device: USBTransportDevice) throws -> String? {
    guard device.route == .rawUSB else { throw USBTransportError.notSupported }
    let service = try Self.deviceService(for: device)
    defer { IOObjectRelease(service) }
    return unsafe IORegistryEntryCreateCFProperty(
      service,
      Self.exclusiveOwnerKey as CFString,
      kCFAllocatorDefault,
      0
    )?.takeRetainedValue() as? String
  }

  /// Resets the USB device.
  ///
  /// - Throws: ``USBTransportError/notSupported`` for a device that is not on the raw USB route,
  ///   ``USBTransportError/notFound`` when it is not listed, and the mapped IOUSBHost error
  ///   otherwise.
  public func resetDevice(_ device: USBTransportDevice) throws {
    guard device.route == .rawUSB else { throw USBTransportError.notSupported }
    let service = try Self.deviceService(for: device)
    defer { IOObjectRelease(service) }
    do {
      let hostDevice = try unsafe IOUSBHostDevice(
        __ioService: service,
        options: [],
        queue: nil,
        interestHandler: nil
      )
      defer { hostDevice.destroy() }
      try hostDevice.reset()
    } catch { throw Self.transportError(error) }
  }

  /// Converts the device `facts` to raw USB transport devices, sorted by vendor, product, location
  /// and service ID.
  static func devices(from facts: [IOUSBHostDeviceFacts]) -> [USBTransportDevice] {
    facts.map { device in
      USBTransportDevice(
        route: .rawUSB,
        serviceID: device.serviceID,
        vendorID: device.vendorID,
        productID: device.productID,
        locationID: device.locationID,
        observedPhysicalLocationIdentifier: device.locationID,
        productName: device.productName,
        serialNumber: device.serialNumber,
        manufacturer: device.manufacturer,
        deviceRelease: device.deviceRelease
      )
    }.sorted { lhs, rhs in
      (lhs.vendorID, lhs.productID, lhs.locationID, lhs.serviceID) < (
        rhs.vendorID, rhs.productID, rhs.locationID, rhs.serviceID
      )
    }
  }

  /// Sends SET_CONFIGURATION only when the device does not already run the requested
  /// configuration, since it terminates every open interface of the device.
  ///
  /// The current value is the device service's own `kUSBCurrentConfiguration` registry property
  /// (`kUSBHostDevicePropertyCurrentConfiguration`), which the host family publishes for the live
  /// device state, including configurations another client or enumeration selected. It is read
  /// without a parent search, which would find a hub's value for an unconfigured device.
  /// `IOUSBHostDevice.configurationDescriptor` is documented only for the configuration selected
  /// "after a successful setConfiguration call", and needs a device client to read.
  ///
  /// A GIP device gets the reads of ``MicrosoftOSDescriptor`` first, as a Windows host sends them.
  private static func configureDevice(
    _ device: USBTransportDevice,
    options: USBTransportOpenOptions
  ) async throws {
    guard let value = options.configurationValue else { return }
    let service = try deviceService(for: device)
    defer { IOObjectRelease(service) }
    let current =
      unsafe IORegistryEntryCreateCFProperty(
        service,
        "kUSBCurrentConfiguration" as CFString,
        kCFAllocatorDefault,
        0
      )?.takeRetainedValue() as? UInt64
    guard options.setsConfiguration(current: current.flatMap(UInt8.init(exactly:))) else { return }
    do {
      let hostDevice = try unsafe IOUSBHostDevice(
        __ioService: service,
        options: [],
        queue: nil,
        interestHandler: nil
      )
      defer { hostDevice.destroy() }
      if isGIPDevice(service) { await probeWindowsDescriptors(hostDevice, device: device) }
      try hostDevice.__configure(withValue: Int(value), matchInterfaces: true)
    } catch { throw transportError(error) }
  }

  /// Polls up to 20 times, 50 ms apart, until the interface `interfaceNumber` of `device` appears.
  ///
  /// - Throws: ``USBTransportError/notFound`` when it never appears.
  private static func waitForInterfaceService(
    device: USBTransportDevice,
    interfaceNumber: UInt8
  ) async throws -> io_service_t {
    for attempt in 0..<20 {
      if let service = try interfaceService(for: device, interfaceNumber: interfaceNumber) {
        return service
      }
      if attempt < 19 { try await Task.sleep(nanoseconds: 50_000_000) }
    }
    throw USBTransportError.notFound
  }

  /// Reads the facts of every `IOUSBHostDevice` service that has a vendor, product, location and
  /// registry entry ID.
  private static func deviceFacts() throws -> [IOUSBHostDeviceFacts] {
    try matchingServices(className: "IOUSBHostDevice") { service in
      guard let vendorID = uint16Property(service, key: "idVendor"),
        let productID = uint16Property(service, key: "idProduct"),
        let locationID = uint32Property(service, key: "locationID"),
        let serviceID = registryEntryID(service)
      else { return nil }
      return IOUSBHostDeviceFacts(
        serviceID: serviceID,
        vendorID: vendorID,
        productID: productID,
        locationID: locationID,
        productName: stringProperty(service, keys: ["USB Product Name", "Product Name"]),
        serialNumber: stringProperty(service, keys: ["USB Serial Number", "Serial Number"]),
        manufacturer: stringProperty(service, keys: ["USB Vendor Name", "Vendor Name"]),
        deviceRelease: uint16Property(service, key: "bcdDevice")
      )
    }
  }

  /// Returns the `IOUSBHostInterface` service `interfaceNumber` of `device`, or nil when none
  /// matches.
  ///
  /// Only the vendor-specific class and the original Xbox class match.
  static func interfaceService(
    for device: USBTransportDevice,
    interfaceNumber: UInt8
  ) throws -> io_service_t? {
    try firstMatchingService(className: "IOUSBHostInterface") { service in
      uint16Property(service, key: "idVendor") == device.vendorID
        && uint16Property(service, key: "idProduct") == device.productID
        && uint32Property(service, key: "locationID") == device.locationID
        && uint8Property(service, key: "bInterfaceNumber") == interfaceNumber
        // Vendor class (XUSB, GIP, vendor protocols) or the original Xbox XID class, as in
        // `USBDescriptorTransportResolver.discover`.
        && [0xFF, 0x58].contains(uint8Property(service, key: "bInterfaceClass"))
    }
  }

  /// Returns the `IOUSBHostDevice` service of `device`.
  ///
  /// - Throws: ``USBTransportError/notFound`` when no service matches the vendor, product and
  ///   location.
  static func deviceService(for device: USBTransportDevice) throws -> io_service_t {
    guard
      let service = try firstMatchingService(
        className: "IOUSBHostDevice",
        matches: { service in
          uint16Property(service, key: "idVendor") == device.vendorID
            && uint16Property(service, key: "idProduct") == device.productID
            && uint32Property(service, key: "locationID") == device.locationID
        }
      )
    else { throw USBTransportError.notFound }
    return service
  }

  /// Returns the non-nil results of `transform` over the services of `className`.
  private static func matchingServices<T>(
    className: String,
    transform: (io_service_t) -> T?
  ) throws -> [T] {
    var iterator: io_iterator_t = 0
    let result = unsafe IOServiceGetMatchingServices(
      kIOMainPortDefault,
      IOServiceMatching(className),
      &iterator
    )
    guard result == kIOReturnSuccess else { throw transportError(result) }
    defer { IOObjectRelease(iterator) }

    var values: [T] = []
    while case let service = IOIteratorNext(iterator), service != 0 {
      if let value = transform(service) { values.append(value) }
      IOObjectRelease(service)
    }
    return values
  }

  /// Returns the first service of `className` for which `matches` is true, or nil when none is.
  private static func firstMatchingService(
    className: String,
    matches: (io_service_t) -> Bool
  ) throws -> io_service_t? {
    var iterator: io_iterator_t = 0
    let result = unsafe IOServiceGetMatchingServices(
      kIOMainPortDefault,
      IOServiceMatching(className),
      &iterator
    )
    guard result == kIOReturnSuccess else { throw transportError(result) }
    defer { IOObjectRelease(iterator) }

    while case let service = IOIteratorNext(iterator), service != 0 {
      if matches(service) { return service }
      IOObjectRelease(service)
    }
    return nil
  }

  /// The options that make a property search look through the parents of a service.
  private static let recursiveParentSearch = IOOptionBits(
    kIORegistryIterateRecursively | kIORegistryIterateParents
  )

  /// Searches the property `key` on `service` and then on its parents.
  private static func property(_ service: io_service_t, key: String) -> AnyObject? {
    unsafe IORegistryEntrySearchCFProperty(
      service,
      kIOServicePlane,
      key as CFString,
      kCFAllocatorDefault,
      recursiveParentSearch
    )
  }

  /// Reads the property `key` as an 8-bit unsigned integer, or nil when it is missing or out of
  /// range.
  static func uint8Property(_ service: io_service_t, key: String) -> UInt8? {
    uint64Property(service, key: key).flatMap(UInt8.init(exactly:))
  }

  /// Reads the property `key` as a 16-bit unsigned integer, or nil when it is missing or out of
  /// range.
  private static func uint16Property(_ service: io_service_t, key: String) -> UInt16? {
    uint64Property(service, key: key).flatMap(UInt16.init(exactly:))
  }

  /// Reads the property `key` as a 32-bit unsigned integer, or nil when it is missing or out of
  /// range.
  private static func uint32Property(_ service: io_service_t, key: String) -> UInt32? {
    uint64Property(service, key: key).flatMap(UInt32.init(exactly:))
  }

  /// Reads the property `key` as a 64-bit unsigned integer, or nil when it is missing or not one.
  private static func uint64Property(_ service: io_service_t, key: String) -> UInt64? {
    property(service, key: key) as? UInt64
  }

  /// Returns the first string property among `keys`, or nil when none is a string.
  private static func stringProperty(_ service: io_service_t, keys: [String]) -> String? {
    for key in keys { if let value = property(service, key: key) as? String { return value } }
    return nil
  }

  /// Returns the registry entry ID of `service`, or nil when IOKit refuses it.
  private static func registryEntryID(_ service: io_service_t) -> UInt64? {
    var value: UInt64 = 0
    return unsafe IORegistryEntryGetRegistryEntryID(service, &value) == kIOReturnSuccess
      ? value : nil
  }
}

/// The facts of one `IOUSBHostDevice` service.
struct IOUSBHostDeviceFacts: Equatable, Sendable {
  /// The registry entry ID of the service.
  let serviceID: UInt64
  /// The USB vendor ID.
  let vendorID: UInt16
  /// The USB product ID.
  let productID: UInt16
  /// The USB location ID.
  let locationID: UInt32
  /// The product name, when the registry has one.
  let productName: String?
  /// The serial number, when the registry has one.
  let serialNumber: String?
  /// The manufacturer name, when the registry has one.
  var manufacturer: String?
  /// The `bcdDevice` release number, when the registry has one.
  var deviceRelease: UInt16?
}
