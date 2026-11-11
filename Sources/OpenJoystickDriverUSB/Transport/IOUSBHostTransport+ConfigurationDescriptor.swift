import Foundation
import IOKit
import IOUSBHost
import OpenJoystickDriverKit

extension IOUSBHostTransportProvider {
  /// Copies the descriptor of configuration `configurationValue` without claiming an interface or
  /// sending SET_CONFIGURATION.
  ///
  /// IOUSBHost answers from its descriptor cache and otherwise issues a GET_DESCRIPTOR read. Nil
  /// when the descriptor is shorter than its own header.
  ///
  /// The IORegistry publishes interface class triples but never endpoint descriptors, so this is
  /// the only source of the endpoint addresses that `xpad_probe` walks.
  static func cachedConfigurationDescriptor(
    of device: USBTransportDevice,
    configurationValue: UInt8
  ) throws -> [UInt8]? {
    guard device.route == .rawUSB else { throw USBTransportError.notSupported }
    let service = try deviceService(for: device)
    defer { IOObjectRelease(service) }
    do {
      let hostDevice = try unsafe IOUSBHostDevice(
        __ioService: service,
        options: [],
        queue: nil,
        interestHandler: nil
      )
      defer { hostDevice.destroy() }
      let descriptor = try unsafe hostDevice.configurationDescriptor(
        withConfigurationValue: Int(configurationValue)
      )
      let length = unsafe Int(UInt16(littleEndian: descriptor.pointee.wTotalLength))
      guard length >= 9 else { return nil }
      return unsafe Array(
        UnsafeRawBufferPointer(start: UnsafeRawPointer(descriptor), count: length)
      )
    } catch { throw transportError(error) }
  }
}
