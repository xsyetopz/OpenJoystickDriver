import Foundation
import IOKit
import IOUSBHost
import OpenJoystickDriverKit

/// Direct app-side raw USB transport backed by Apple's IOUSBHost framework.
///
/// This backend owns accessible vendor-specific interfaces without requiring a
/// DriverKit extension. Services that require OJD's restricted DEXT are filtered
/// by `OpenJoystickDriverUSBTransportProvider` before callers see them.
public actor IOUSBHostTransportProvider: USBTransportProvider {
  public init() {}

  public func devices() throws -> [USBTransportDevice] {
    try Self.devices(from: Self.deviceFacts())
  }

  public func open(
    _ device: USBTransportDevice,
    options: USBTransportOpenOptions
  ) async throws -> any USBTransportSession {
    guard device.route == .ioUSBHost else { throw USBTransportError.notSupported }

    try Self.configureDevice(device, options: options)

    let service = try await Self.waitForInterfaceService(
      device: device,
      interfaceNumber: options.interfaceNumber
    )
    defer { IOObjectRelease(service) }

    do {
      let interface = try IOUSBHostInterface(
        __ioService: service,
        options: [],
        queue: DispatchQueue(
          label: "com.openjoystickdriver.iousbhost.\(device.locationID).\(options.interfaceNumber)"
        ),
        interestHandler: nil
      )
      if options.alternateSetting != 0 {
        try interface.selectAlternateSetting(Int(options.alternateSetting))
      }
      return IOUSBHostTransportSession(interface: interface)
    } catch { throw Self.transportError(error) }
  }

  public func resetDevice(_ device: USBTransportDevice) throws {
    guard device.route == .ioUSBHost else { throw USBTransportError.notSupported }
    let service = try Self.deviceService(for: device)
    defer { IOObjectRelease(service) }
    do {
      let hostDevice = try IOUSBHostDevice(
        __ioService: service,
        options: [],
        queue: nil,
        interestHandler: nil
      )
      defer { hostDevice.destroy() }
      try hostDevice.reset()
    } catch { throw Self.transportError(error) }
  }

  static func devices(from facts: [IOUSBHostDeviceFacts]) -> [USBTransportDevice] {
    facts.map { device in
      USBTransportDevice(
        route: .ioUSBHost,
        serviceID: device.serviceID,
        vendorID: device.vendorID,
        productID: device.productID,
        locationID: device.locationID,
        observedPhysicalLocationIdentifier: device.locationID,
        productName: device.productName,
        serialNumber: device.serialNumber
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
  private static func configureDevice(
    _ device: USBTransportDevice,
    options: USBTransportOpenOptions
  ) throws {
    guard let value = options.configurationValue else { return }
    let service = try deviceService(for: device)
    defer { IOObjectRelease(service) }
    let current =
      IORegistryEntryCreateCFProperty(
        service,
        "kUSBCurrentConfiguration" as CFString,
        kCFAllocatorDefault,
        0
      )?.takeRetainedValue() as? UInt64
    guard options.setsConfiguration(current: current.flatMap(UInt8.init(exactly:))) else { return }
    do {
      let hostDevice = try IOUSBHostDevice(
        __ioService: service,
        options: [],
        queue: nil,
        interestHandler: nil
      )
      defer { hostDevice.destroy() }
      try hostDevice.__configure(withValue: Int(value), matchInterfaces: true)
    } catch { throw transportError(error) }
  }

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
        serialNumber: stringProperty(service, keys: ["USB Serial Number", "Serial Number"])
      )
    }
  }

  private static func interfaceService(
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

  private static func matchingServices<T>(
    className: String,
    transform: (io_service_t) -> T?
  ) throws -> [T] {
    var iterator: io_iterator_t = 0
    let result = IOServiceGetMatchingServices(
      kIOMasterPortDefault,
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

  private static func firstMatchingService(
    className: String,
    matches: (io_service_t) -> Bool
  ) throws -> io_service_t? {
    var iterator: io_iterator_t = 0
    let result = IOServiceGetMatchingServices(
      kIOMasterPortDefault,
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

  private static let recursiveParentSearch = IOOptionBits(
    kIORegistryIterateRecursively | kIORegistryIterateParents
  )

  private static func property(_ service: io_service_t, key: String) -> AnyObject? {
    IORegistryEntrySearchCFProperty(
      service,
      kIOServicePlane,
      key as CFString,
      kCFAllocatorDefault,
      recursiveParentSearch
    )
  }

  private static func uint8Property(_ service: io_service_t, key: String) -> UInt8? {
    uint64Property(service, key: key).flatMap(UInt8.init(exactly:))
  }

  private static func uint16Property(_ service: io_service_t, key: String) -> UInt16? {
    uint64Property(service, key: key).flatMap(UInt16.init(exactly:))
  }

  private static func uint32Property(_ service: io_service_t, key: String) -> UInt32? {
    uint64Property(service, key: key).flatMap(UInt32.init(exactly:))
  }

  private static func uint64Property(_ service: io_service_t, key: String) -> UInt64? {
    property(service, key: key) as? UInt64
  }

  private static func stringProperty(_ service: io_service_t, keys: [String]) -> String? {
    for key in keys { if let value = property(service, key: key) as? String { return value } }
    return nil
  }

  private static func registryEntryID(_ service: io_service_t) -> UInt64? {
    var value: UInt64 = 0
    return IORegistryEntryGetRegistryEntryID(service, &value) == kIOReturnSuccess ? value : nil
  }

  static func deviceRequest(for request: USBControlTransferRequest) -> IOUSBDeviceRequest {
    IOUSBDeviceRequest(
      bmRequestType: request.requestType,
      bRequest: request.request,
      wValue: request.value,
      wIndex: request.index,
      wLength: request.length
    )
  }

  /// IOUSBHost timeouts are seconds, where zero means no timeout.
  static func completionTimeout(milliseconds: UInt32) -> TimeInterval {
    TimeInterval(milliseconds) / 1_000
  }

  /// IOUSBHost requires a zero completion timeout for interrupt pipes; bulk pipes honor it.
  static func pipeCompletionTimeout(endpointAttributes: UInt8, milliseconds: UInt32) -> TimeInterval
  { endpointAttributes & 0x03 == 0x02 ? completionTimeout(milliseconds: milliseconds) : 0 }

  static func transportError(_ error: Error) -> USBTransportError {
    let nsError = error as NSError
    return transportError(IOReturn(truncatingIfNeeded: nsError.code))
  }

  static func transportError(_ code: IOReturn) -> USBTransportError {
    switch code {
    case kIOReturnTimeout, kIOReturnAborted: return .timeout
    case kIOReturnNoDevice, kIOReturnNotAttached, kIOReturnNotOpen, kIOReturnNotResponding:
      return .disconnected
    case kIOReturnNotPermitted, kIOReturnExclusiveAccess, kIOReturnNotPrivileged:
      return .accessDenied
    case kIOReturnNotFound: return .notFound
    case kIOReturnUnsupported, kIOReturnBadArgument: return .notSupported
    case kIOReturnIOError: return .inputOutput
    default: return .platform(code: code, message: String(describing: code))
    }
  }
}

struct IOUSBHostDeviceFacts: Equatable, Sendable {
  let serviceID: UInt64
  let vendorID: UInt16
  let productID: UInt16
  let locationID: UInt32
  let productName: String?
  let serialNumber: String?
}

// `@unchecked Sendable` because `IOUSBHostPipe` is not annotated `Sendable`, and awaiting its
// nonisolated `enqueueIORequest` sends it out of the session actor. Only the session actor
// creates, aborts, and drops pipes; the box carries one across that single await.
private final class IOUSBHostPipeBox: @unchecked Sendable {
  let pipe: IOUSBHostPipe
  init(_ pipe: IOUSBHostPipe) { self.pipe = pipe }
}

private actor IOUSBHostTransportSession: USBTransportSession {
  private let interface: IOUSBHostInterface
  private var pipes: [UInt8: IOUSBHostPipeBox] = [:]
  private var isClosed = false
  private var isDestroyed = false
  // Actor methods are reentrant at every `await`, so `close()` can run while a transfer is
  // suspended. The interface owns the `ioData` buffers, so it is destroyed only once no
  // transfer is in flight.
  private var inFlightTransfers = 0

  var inputOwnership: HIDInputOwnership { isClosed ? .unknown : .exclusive }

  init(interface: IOUSBHostInterface) { self.interface = interface }

  func write(endpoint: UInt8, data: [UInt8], timeout: UInt32) async throws -> Int {
    guard !isClosed else { throw USBTransportError.disconnected }
    guard USBEndpointDirection(endpointAddress: endpoint) == .out, !data.isEmpty else {
      throw USBTransportError.notSupported
    }
    beginTransfer()
    defer { endTransfer() }
    do {
      let buffer = try interface.ioData(withCapacity: data.count)
      Self.copy(data, into: buffer)
      return try await transfer(endpoint: endpoint, buffer: buffer, timeout: timeout)
    } catch { throw closeIfDisconnected(error) }
  }

  func read(endpoint: UInt8, length: Int, timeout: UInt32) async throws -> [UInt8] {
    guard !isClosed else { throw USBTransportError.disconnected }
    guard USBEndpointDirection(endpointAddress: endpoint) == .in, length > 0 else {
      throw USBTransportError.notSupported
    }
    beginTransfer()
    defer { endTransfer() }
    do {
      let buffer = try interface.ioData(withCapacity: length)
      let count = try await transfer(endpoint: endpoint, buffer: buffer, timeout: timeout)
      guard !isClosed else { throw USBTransportError.disconnected }
      return Array(Data(bytes: buffer.bytes, count: min(count, buffer.length)))
    } catch { throw closeIfDisconnected(error) }
  }

  @discardableResult
  func controlTransfer(
    _ request: USBControlTransferRequest,
    timeout: UInt32
  ) async throws -> [UInt8] {
    guard !isClosed else { throw USBTransportError.disconnected }
    beginTransfer()
    defer { endTransfer() }
    do {
      let buffer: NSMutableData?
      switch request.dataStage {
      case .none: buffer = nil
      case .output(let data):
        let output = try interface.ioData(withCapacity: data.count)
        Self.copy(data, into: output)
        buffer = output
      case .input(let length): buffer = try interface.ioData(withCapacity: Int(length))
      }
      let (status, count) = try await interface.__enqueue(
        IOUSBHostTransportProvider.deviceRequest(for: request),
        data: buffer,
        completionTimeout: IOUSBHostTransportProvider.completionTimeout(milliseconds: timeout)
      )
      guard !isClosed else { throw USBTransportError.disconnected }
      guard status == kIOReturnSuccess else {
        throw IOUSBHostTransportProvider.transportError(status)
      }
      guard request.direction == .in, let buffer else { return [] }
      return Array(Data(bytes: buffer.bytes, count: min(count, buffer.length)))
    } catch { throw closeIfDisconnected(error) }
  }

  func close() {
    guard !isClosed else { return }
    isClosed = true
    for box in pipes.values { try? box.pipe.__abort(with: .synchronous) }
    pipes.removeAll()
    destroyInterfaceIfIdle()
  }

  private func beginTransfer() { inFlightTransfers += 1 }

  private func endTransfer() {
    inFlightTransfers -= 1
    destroyInterfaceIfIdle()
  }

  private func destroyInterfaceIfIdle() {
    guard isClosed, inFlightTransfers == 0, !isDestroyed else { return }
    isDestroyed = true
    interface.destroy()
  }

  private func transfer(endpoint: UInt8, buffer: NSMutableData, timeout: UInt32) async throws -> Int
  {
    let pipe = try pipe(for: endpoint)
    do {
      let result = try await pipe.pipe.enqueueIORequest(
        with: buffer,
        completionTimeout: IOUSBHostTransportProvider.pipeCompletionTimeout(
          endpointAttributes: pipe.pipe.descriptors.pointee.descriptor.bmAttributes,
          milliseconds: timeout
        )
      )
      guard result.0 == kIOReturnSuccess else {
        throw IOUSBHostTransportProvider.transportError(result.0)
      }
      return result.1
    } catch let error as USBTransportError { throw error } catch {
      throw IOUSBHostTransportProvider.transportError(error)
    }
  }

  private static func copy(_ data: [UInt8], into buffer: NSMutableData) {
    data.withUnsafeBytes { source in
      guard let baseAddress = source.baseAddress else { return }
      buffer.mutableBytes.copyMemory(from: baseAddress, byteCount: source.count)
    }
  }

  private func closeIfDisconnected(_ error: Error) -> USBTransportError {
    let transportError =
      error as? USBTransportError ?? IOUSBHostTransportProvider.transportError(error)
    if transportError.isDisconnected { close() }
    return transportError
  }

  private func pipe(for endpoint: UInt8) throws -> IOUSBHostPipeBox {
    if let pipe = pipes[endpoint] { return pipe }
    do {
      let pipe = IOUSBHostPipeBox(try interface.copyPipe(withAddress: Int(endpoint)))
      pipes[endpoint] = pipe
      return pipe
    } catch { throw IOUSBHostTransportProvider.transportError(error) }
  }
}
