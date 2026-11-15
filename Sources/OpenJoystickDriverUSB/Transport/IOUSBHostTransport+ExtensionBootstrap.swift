import Foundation
import IOKit
import IOUSBHost
import OpenJoystickDriverKit

extension IOUSBHostTransportProvider {
  /// Configures a Microsoft device without claiming its data interface or sending GIP packets.
  ///
  /// The host device is retained until configuration completes, then released so the extension
  /// can own the published interface. No seize, reset, alternate-setting or pipe operation occurs.
  static func bootstrapForExtension(_ device: USBTransportDevice) async throws -> Bool {
    guard device.route == .rawUSB,
      device.vendorID == USBDriverKitExtensionConfiguration.microsoftVendorID,
      USBDriverKitExtensionConfiguration.microsoftProductIDs.contains(device.productID)
    else { return false }
    let service = try deviceService(for: device)
    defer { IOObjectRelease(service) }
    guard try bootstrapState(service, device: device).canInspect else { return false }
    do {
      let host = try IOUSBHostDevice(
        __ioService: service,
        options: [],
        queue: nil,
        interestHandler: nil
      )
      defer { host.destroy() }
      return try await USBExtensionBootstrap.prepare(
        state: { try bootstrapState(service, device: device) },
        descriptor: {
          let pointer = try host.configurationDescriptor(withConfigurationValue: 1)
          let length = Int(UInt16(littleEndian: pointer.pointee.wTotalLength))
          guard length >= 9 else { throw USBTransportError.notSupported }
          return Array(UnsafeRawBufferPointer(start: UnsafeRawPointer(pointer), count: length))
        },
        currentConfiguration: {
          // USB 2.0 GET_CONFIGURATION is a device-to-host, one-byte standard request.
          let request = try USBControlTransferRequest(
            kind: .standard,
            recipient: .device,
            request: 8,
            dataStage: .input(length: 1)
          )
          let buffer = try host.ioData(withCapacity: 1)
          let (status, count) = try await host.__enqueue(
            deviceRequest(for: request),
            data: buffer,
            completionTimeout: 1
          )
          guard status == kIOReturnSuccess else { throw transportError(status) }
          guard count == 1 else { throw USBTransportError.inputOutput }
          return buffer.bytes.load(as: UInt8.self)
        },
        configure: { try host.__configure(withValue: 1, matchInterfaces: true) }
      )
    } catch let error as USBTransportError {
      throw error
    } catch {
      throw transportError(error)
    }
  }

  /// Reads only this device's properties and descendants, never its hub's configuration.
  private static func bootstrapState(
    _ service: io_service_t,
    device: USBTransportDevice
  ) throws -> USBExtensionBootstrapState {
    var identifier: UInt64 = 0
    guard IORegistryEntryGetRegistryEntryID(service, &identifier) == KERN_SUCCESS,
      identifier == device.serviceID
    else { throw USBTransportError.disconnected }
    let current =
      IORegistryEntryCreateCFProperty(
        service,
        "kUSBCurrentConfiguration" as CFString,
        kCFAllocatorDefault,
        0
      )?.takeRetainedValue() as? UInt64
    let owner =
      IORegistryEntryCreateCFProperty(
        service,
        exclusiveOwnerKey as CFString,
        kCFAllocatorDefault,
        0
      )?.takeRetainedValue() as? String
    var iterator: io_iterator_t = 0
    let result = IORegistryEntryCreateIterator(
      service,
      kIOServicePlane,
      IOOptionBits(kIORegistryIterateRecursively),
      &iterator
    )
    guard result == KERN_SUCCESS else { throw transportError(result) }
    defer { IOObjectRelease(iterator) }
    var hasInterfaces = false
    while case let child = IOIteratorNext(iterator), child != 0 {
      if IOObjectConformsTo(child, "IOUSBHostInterface") != 0 { hasInterfaces = true }
      IOObjectRelease(child)
    }
    return USBExtensionBootstrapState(
      configuration: current.flatMap(UInt8.init(exactly:)),
      hasInterfaces: hasInterfaces,
      ownedByAnotherClient: owner.map { !$0.hasPrefix("pid \(getpid()),") } ?? false
    )
  }
}
