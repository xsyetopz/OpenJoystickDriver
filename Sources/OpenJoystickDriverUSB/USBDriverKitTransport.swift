import IOKit
import OpenJoystickDriverKit
import SwifterKit

/// Host adapter for services owned by OJD's restricted USBDriverKit extension.
public actor USBDriverKitTransportProvider: USBTransportProvider {
  private let client: DriverClient
  private var servicesByID: [UInt64: DriverService] = [:]

  public init(client: DriverClient = DriverClient()) { self.client = client }

  public func devices() async throws -> [USBTransportDevice] {
    let services = try await client.services(
      matching: USBDriverKitExtensionConfiguration.driver.serviceMatch
    )
    servicesByID = Dictionary(uniqueKeysWithValues: services.map { ($0.id, $0) })
    return services.compactMap(Self.device)
  }

  public func open(_ device: USBTransportDevice, options: USBTransportOpenOptions) async throws
    -> any USBTransportSession
  {
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
      let session = try await client.open(service)
      let runtime = try await DriverRuntimeConnection.connect(session: session, requiring: .usb)
      let context = await DriverContext(runtime: runtime)
      do {
        if let configuration = options.configurationValue {
          _ = try await context.usbControlTransfer(
            USBControlRequest(
              requestType: USBRequestType.out | USBRequestType.standard | USBRequestType.device,
              request: USBRequest.setConfiguration,
              value: UInt16(configuration)
            )
          )
        }
        if options.alternateSetting != 0 {
          try await context.usbSelectAlternateSetting(options.alternateSetting)
        }
        return USBDriverKitTransportSession(runtime: runtime, context: context)
      } catch {
        await runtime.close()
        throw Self.transportError(error)
      }
    } catch let error as USBTransportError { throw error } catch {
      throw Self.transportError(error)
    }
  }

  static func device(_ service: DriverService) -> USBTransportDevice? {
    guard let vendorID = uint16Property(service.properties["idVendor"]),
      let productID = uint16Property(service.properties["idProduct"])
    else { return nil }
    let locationID =
      uint32Property(service.properties["locationID"]) ?? uint32Property(
        service.properties["LocationID"]
      ) ?? UInt32(truncatingIfNeeded: service.id)
    return USBTransportDevice(
      route: .usbDriverKit,
      serviceID: service.id,
      vendorID: vendorID,
      productID: productID,
      locationID: locationID,
      productName: stringProperty(
        service.properties["USB Product Name"] ?? service.properties["Product Name"]
      ),
      serialNumber: stringProperty(
        service.properties["USB Serial Number"] ?? service.properties["Serial Number"]
      )
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

  static func transportError(_ error: Error) -> USBTransportError {
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

private actor USBDriverKitTransportSession: USBTransportSession {
  private let runtime: DriverRuntimeConnection
  private let context: DriverContext
  private var isClosed = false

  init(runtime: DriverRuntimeConnection, context: DriverContext) {
    self.runtime = runtime
    self.context = context
  }

  func writeInterruptPacket(endpoint: UInt8, data: [UInt8], timeout: UInt32) async throws -> Int {
    guard !isClosed else { throw USBTransportError.disconnected }
    do {
      return Int(
        try await context.usbWrite(endpoint: endpoint, data: data, timeout: timeout)
          .bytesTransferred
      )
    } catch { throw USBDriverKitTransportProvider.transportError(error) }
  }

  func readInterruptPacket(endpoint: UInt8, length: Int, timeout: UInt32) async throws -> [UInt8] {
    guard !isClosed else { throw USBTransportError.disconnected }
    do {
      return try await context.usbRead(endpoint: endpoint, length: length, timeout: timeout).data
    } catch { throw USBDriverKitTransportProvider.transportError(error) }
  }

  func close() async {
    guard !isClosed else { return }
    isClosed = true
    await runtime.close()
  }
}
