import IOKit
import OpenJoystickDriverKit
import SwifterKit

/// Host adapter for services owned by OJD's restricted USBDriverKit extension.
public actor USBDriverKitTransportProvider: USBPhysicalDeviceObservationProvider {
  private let client: DriverClient
  private var servicesByID: [UInt64: DriverService] = [:]

  public init(client: DriverClient = DriverClient()) { self.client = client }

  public func devices() async throws -> [USBTransportDevice] {
    let services = try await client.services(
      matching: VirtualHIDExtensionConfiguration.xboxUSB.serviceMatch
    )
    servicesByID = Dictionary(uniqueKeysWithValues: services.map { ($0.id, $0) })
    return services.compactMap(Self.device)
  }

  public func physicalDeviceObservations() throws -> [PhysicalDevice] {
    servicesByID.values.sorted { $0.id < $1.id }.compactMap(Self.physicalDeviceObservation(from:))
  }

  public func open(
    _ device: USBTransportDevice,
    options: USBTransportOpenOptions
  ) async throws -> any USBTransportSession {
    guard device.route == .usbDriverKit else { throw USBTransportError.notSupported }
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
    } catch { throw Self.transportError(error) }
  }

  static func device(_ service: DriverService) -> USBTransportDevice? {
    guard let vendorID = uint16Property(service.properties["idVendor"]),
      let productID = uint16Property(service.properties["idProduct"])
    else { return nil }
    let observedPhysicalLocationIdentifier =
      uint32Property(service.properties["locationID"])
      ?? uint32Property(service.properties["LocationID"])
    let locationID = observedPhysicalLocationIdentifier ?? UInt32(truncatingIfNeeded: service.id)
    return USBTransportDevice(
      route: .usbDriverKit,
      serviceID: service.id,
      vendorID: vendorID,
      productID: productID,
      locationID: locationID,
      observedPhysicalLocationIdentifier: observedPhysicalLocationIdentifier,
      productName: stringProperty(
        service.properties["USB Product Name"] ?? service.properties["Product Name"]
      ),
      serialNumber: stringProperty(
        service.properties["USB Serial Number"] ?? service.properties["Serial Number"]
      )
    )
  }

  static func physicalDeviceObservation(from service: DriverService) -> PhysicalDevice? {
    guard let device = device(service) else { return nil }
    return PhysicalDevice(
      serviceIdentity: device.serviceIdentity,
      vendorID: device.vendorID,
      productID: device.productID,
      productName: device.productName,
      serialNumber: device.serialNumber,
      physicalLocationIdentifier: device.observedPhysicalLocationIdentifier,
      interfaces: [
        PhysicalInterfaceSignature(
          hostTransport: .usb,
          accessBackend: .usbDriverKit,
          usbRoute: .usbDriverKit
        )
      ]
    )
  }

  private static func uint16Property(_ property: DriverProperty?) -> UInt16? {
    guard let value = unsignedProperty(property) else { return nil }
    return UInt16(exactly: value)
  }

  private static func uint32Property(_ property: DriverProperty?) -> UInt32? {
    guard let value = unsignedProperty(property) else { return nil }
    return UInt32(exactly: value)
  }

  private static func unsignedProperty(_ property: DriverProperty?) -> UInt64? {
    switch property {
    case .unsignedInteger(let value): value
    case .integer(let value) where value >= 0: UInt64(value)
    default: nil
    }
  }

  private static func stringProperty(_ property: DriverProperty?) -> String? {
    guard case .string(let value) = property else { return nil }
    return value
  }

  static func controlRequest(for request: USBControlTransferRequest) -> USBControlRequest {
    USBControlRequest(
      requestType: request.requestType,
      request: request.request,
      value: request.value,
      index: request.index,
      length: request.length
    )
  }

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
      case kIOReturnNotPermitted, kIOReturnExclusiveAccess, kIOReturnNotPrivileged:
        return .accessDenied
      case kIOReturnNotFound: return .notFound
      case kIOReturnUnsupported: return .notSupported
      case kIOReturnIOError: return .inputOutput
      default: return .platform(code: code, message: driverKitError.description)
      }
    }
  }
}

actor USBDriverKitTransportSession: USBTransportSession {
  private let context: DriverContext
  private let closeRuntime: @Sendable () async -> Void
  private var isClosed = false

  var inputOwnership: HIDInputOwnership { isClosed ? .unknown : .exclusive }

  init(context: DriverContext, closeRuntime: @escaping @Sendable () async -> Void) {
    self.context = context
    self.closeRuntime = closeRuntime
  }

  func write(endpoint: UInt8, data: [UInt8], timeout: UInt32) async throws -> Int {
    guard !isClosed else { throw USBTransportError.disconnected }
    do {
      return Int(
        try await context.usbWrite(endpoint: endpoint, data: data, timeout: timeout)
          .bytesTransferred
      )
    } catch { throw USBDriverKitTransportProvider.transportError(error) }
  }

  func read(endpoint: UInt8, length: Int, timeout: UInt32) async throws -> [UInt8] {
    guard !isClosed else { throw USBTransportError.disconnected }
    do {
      return try await context.usbRead(endpoint: endpoint, length: length, timeout: timeout).data
    } catch { throw USBDriverKitTransportProvider.transportError(error) }
  }

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

  func close() async {
    guard !isClosed else { return }
    isClosed = true
    await closeRuntime()
  }
}
