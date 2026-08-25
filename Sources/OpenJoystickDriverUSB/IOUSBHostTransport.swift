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

  public func open(_ device: USBTransportDevice, options: USBTransportOpenOptions) async throws
    -> any USBTransportSession
  {
    guard device.route == .ioUSBHost else { throw USBTransportError.notSupported }

    if let configurationValue = options.configurationValue {
      try Self.configureDevice(device, value: configurationValue)
    }

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

  static func devices(from facts: [IOUSBHostDeviceFacts]) -> [USBTransportDevice] {
    facts.map { device in
      USBTransportDevice(
        route: .ioUSBHost,
        serviceID: device.serviceID,
        vendorID: device.vendorID,
        productID: device.productID,
        locationID: device.locationID,
        productName: device.productName,
        serialNumber: device.serialNumber
      )
    }.sorted { lhs, rhs in
      (lhs.vendorID, lhs.productID, lhs.locationID, lhs.serviceID) < (
        rhs.vendorID, rhs.productID, rhs.locationID, rhs.serviceID
      )
    }
  }

  private static func configureDevice(_ device: USBTransportDevice, value: UInt8) throws {
    let service = try deviceService(for: device)
    defer { IOObjectRelease(service) }
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

  private static func waitForInterfaceService(device: USBTransportDevice, interfaceNumber: UInt8)
    async throws -> io_service_t
  {
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

  private static func interfaceService(for device: USBTransportDevice, interfaceNumber: UInt8)
    throws -> io_service_t?
  {
    try firstMatchingService(className: "IOUSBHostInterface") { service in
      uint16Property(service, key: "idVendor") == device.vendorID
        && uint16Property(service, key: "idProduct") == device.productID
        && uint32Property(service, key: "locationID") == device.locationID
        && uint8Property(service, key: "bInterfaceNumber") == interfaceNumber
        && uint8Property(service, key: "bInterfaceClass") == 0xFF
    }
  }

  private static func deviceService(for device: USBTransportDevice) throws -> io_service_t {
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

  private static func matchingServices<T>(className: String, transform: (io_service_t) -> T?) throws
    -> [T]
  {
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

  private static func firstMatchingService(className: String, matches: (io_service_t) -> Bool)
    throws -> io_service_t?
  {
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

  static func transportError(_ error: Error) -> USBTransportError {
    let nsError = error as NSError
    return transportError(IOReturn(truncatingIfNeeded: nsError.code))
  }

  static func transportError(_ code: IOReturn) -> USBTransportError {
    switch code {
    case kIOReturnTimeout, kIOReturnAborted: return .timeout
    case kIOReturnNoDevice, kIOReturnNotAttached, kIOReturnNotOpen: return .disconnected
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

private final class IOUSBHostPipeBox: @unchecked Sendable {
  let pipe: IOUSBHostPipe
  init(_ pipe: IOUSBHostPipe) { self.pipe = pipe }
}

private actor IOUSBHostTransportSession: USBTransportSession {
  private let interface: IOUSBHostInterface
  private var pipes: [UInt8: IOUSBHostPipeBox] = [:]
  private var isClosed = false

  init(interface: IOUSBHostInterface) { self.interface = interface }

  func writeInterruptPacket(endpoint: UInt8, data: [UInt8], timeout: UInt32) async throws -> Int {
    guard !isClosed else { throw USBTransportError.disconnected }
    let buffer = try interface.ioData(withCapacity: data.count)
    data.withUnsafeBytes { source in
      guard let baseAddress = source.baseAddress else { return }
      buffer.mutableBytes.copyMemory(from: baseAddress, byteCount: source.count)
    }
    let (_, count) = try await transfer(endpoint: endpoint, buffer: buffer)
    return count
  }

  func readInterruptPacket(endpoint: UInt8, length: Int, timeout: UInt32) async throws -> [UInt8] {
    guard !isClosed else { throw USBTransportError.disconnected }
    guard length > 0 else { throw USBTransportError.notSupported }
    let buffer = try interface.ioData(withCapacity: length)
    let (_, count) = try await transfer(endpoint: endpoint, buffer: buffer)
    return Array(Data(bytes: buffer.bytes, count: min(count, buffer.length)))
  }

  func close() {
    guard !isClosed else { return }
    isClosed = true
    for box in pipes.values { try? box.pipe.__abort(with: .synchronous) }
    pipes.removeAll()
    interface.destroy()
  }

  private func transfer(endpoint: UInt8, buffer: NSMutableData) async throws -> (IOReturn, Int) {
    let pipe = try pipe(for: endpoint)
    do {
      // IOUSBHost requires a zero completion timeout for interrupt pipes.
      let result = try await pipe.pipe.enqueueIORequest(with: buffer, completionTimeout: 0)
      guard result.0 == kIOReturnSuccess else {
        throw IOUSBHostTransportProvider.transportError(result.0)
      }
      return result
    } catch let error as USBTransportError { throw error } catch {
      throw IOUSBHostTransportProvider.transportError(error)
    }
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
