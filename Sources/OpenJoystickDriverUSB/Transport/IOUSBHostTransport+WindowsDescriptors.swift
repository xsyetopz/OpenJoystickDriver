import Foundation
import IOKit
import IOUSBHost
import OpenJoystickDriverKit

/// The descriptor reads a Windows host sends to a device before it selects a configuration: the
/// configuration descriptor in one 255-byte request, then the Microsoft OS 1.0 string descriptor
/// (index 0xEE) and, when that names a vendor code, the extended compat ID descriptor.
///
/// Some third-party GIP firmware chooses between GIP and a fallback HID mode, which has another
/// product ID, from how the host reads its descriptors; XPadMac sends these reads for such pads.
/// macOS enumerates with a 64-byte configuration read and never asks for 0xEE.
enum MicrosoftOSDescriptor {
  /// The index of the Microsoft OS string descriptor.
  static let stringIndex: UInt8 = 0xEE
  /// The `wIndex` of the extended compat ID feature descriptor.
  static let compatIDFeatureIndex: UInt16 = 4
  /// The length of the extended compat ID header; a function section of 24 bytes follows it.
  static let compatIDHeaderLength: UInt16 = 16
  /// "MSFT100" in UTF-16LE, at bytes 2 through 15 of the OS string descriptor.
  static let signature: [UInt8] = Array("MSFT100".utf16.flatMap { [UInt8($0), 0] })

  /// GET_DESCRIPTOR(CONFIGURATION, 0) with a `wLength` of 255, as Windows asks for it.
  static func configurationRequest() throws -> USBControlTransferRequest {
    try descriptorRequest(type: 0x02, index: 0, length: 255)
  }

  /// GET_DESCRIPTOR(STRING, 0xEE) with a `wLength` of 18.
  static func stringRequest() throws -> USBControlTransferRequest {
    try descriptorRequest(type: 0x03, index: stringIndex, length: 18)
  }

  /// The vendor request that reads `length` bytes of the extended compat ID descriptor.
  static func compatIDRequest(
    vendorCode: UInt8,
    length: UInt16
  ) throws -> USBControlTransferRequest {
    try USBControlTransferRequest(
      kind: .vendor,
      recipient: .device,
      request: vendorCode,
      index: compatIDFeatureIndex,
      dataStage: .input(length: length)
    )
  }

  /// The vendor code of an OS string descriptor that carries the MSFT100 signature, or nil.
  static func vendorCode(fromString descriptor: [UInt8]) -> UInt8? {
    guard descriptor.count >= 18, descriptor[1] == 0x03,
      Array(descriptor[2..<16]) == signature
    else { return nil }
    return descriptor[16]
  }

  /// The `dwLength` of an extended compat ID header when the descriptor has at least one function
  /// section and fits a control transfer, or nil.
  static func compatIDLength(fromHeader header: [UInt8]) -> UInt16? {
    guard header.count >= 4 else { return nil }
    let length = header[0..<4].reversed().reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
    guard length > compatIDHeaderLength, length <= UInt32(UInt16.max) else { return nil }
    return UInt16(length)
  }

  /// The compatible IDs of the function sections of an extended compat ID descriptor, with their
  /// NUL padding removed.
  static func compatibleIDs(from descriptor: [UInt8]) -> [String] {
    guard descriptor.count > 8 else { return [] }
    let header = Int(compatIDHeaderLength)
    return (0..<Int(descriptor[8])).compactMap { section in
      let start = header + section * 24 + 2
      guard start + 8 <= descriptor.count else { return nil }
      return String(bytes: descriptor[start..<start + 8].prefix { $0 != 0 }, encoding: .ascii)
    }
  }

  private static func descriptorRequest(
    type: UInt8,
    index: UInt8,
    length: UInt16
  ) throws -> USBControlTransferRequest {
    try USBControlTransferRequest(
      kind: .standard,
      recipient: .device,
      request: 0x06,
      value: UInt16(type) << 8 | UInt16(index),
      dataStage: .input(length: length)
    )
  }
}

extension IOUSBHostTransportProvider {
  /// The device class triple of a GIP device: vendor-specific class, subclass 0x47, protocol 0xD0.
  static let gipDeviceClass: (UInt8, UInt8, UInt8) = (0xFF, 0x47, 0xD0)

  /// The milliseconds each descriptor read may take before the probe moves on.
  static let windowsDescriptorTimeoutMilliseconds: UInt32 = 500

  /// Whether the device `service` has the GIP device class triple.
  static func isGIPDevice(_ service: io_service_t) -> Bool {
    let triple = ["bDeviceClass", "bDeviceSubClass", "bDeviceProtocol"].map {
      uint8Property(service, key: $0)
    }
    return triple == [gipDeviceClass.0, gipDeviceClass.1, gipDeviceClass.2]
  }

  /// Sends the descriptor reads of ``MicrosoftOSDescriptor`` to `hostDevice` and logs what it
  /// answers.
  ///
  /// A device may stall any of them, as most non-Microsoft devices stall 0xEE, so each failure is
  /// logged and the configuration goes ahead.
  static func probeWindowsDescriptors(
    _ hostDevice: IOUSBHostDevice,
    device: USBTransportDevice
  ) async {
    let name = unsafe String(format: "%04x:%04x", device.vendorID, device.productID)
    func read(_ request: USBControlTransferRequest) async -> [UInt8]? {
      let result = await windowsDescriptorRead(request, from: hostDevice)
      if case .failure(let error) = result {
        print(
          "[IOUSBHostTransport] \(name): request 0x\(String(request.request, radix: 16)) "
            + "value 0x\(String(request.value, radix: 16)) failed: \(error)"
        )
      }
      return try? result.get()
    }
    guard let configuration = try? MicrosoftOSDescriptor.configurationRequest(),
      let string = try? MicrosoftOSDescriptor.stringRequest()
    else { return }
    if let bytes = await read(configuration) {
      print("[IOUSBHostTransport] \(name): 255-byte configuration read: \(bytes.count) bytes")
    }
    guard let osString = await read(string),
      let vendorCode = MicrosoftOSDescriptor.vendorCode(fromString: osString)
    else {
      print("[IOUSBHostTransport] \(name): no MSFT100 OS string descriptor")
      return
    }
    guard
      let header = try? MicrosoftOSDescriptor.compatIDRequest(
        vendorCode: vendorCode,
        length: MicrosoftOSDescriptor.compatIDHeaderLength
      ),
      let headerBytes = await read(header),
      let length = MicrosoftOSDescriptor.compatIDLength(fromHeader: headerBytes),
      let full = try? MicrosoftOSDescriptor.compatIDRequest(vendorCode: vendorCode, length: length),
      let descriptor = await read(full)
    else {
      print(
        "[IOUSBHostTransport] \(name): vendor code 0x\(String(vendorCode, radix: 16)), no compat ID"
      )
      return
    }
    let ids = MicrosoftOSDescriptor.compatibleIDs(from: descriptor)
    print(
      "[IOUSBHostTransport] \(name): vendor code 0x\(String(vendorCode, radix: 16)), "
        + "compat IDs \(ids)"
    )
  }

  private static func windowsDescriptorRead(
    _ request: USBControlTransferRequest,
    from hostDevice: IOUSBHostDevice
  ) async -> Result<[UInt8], USBTransportError> {
    do {
      let buffer = try hostDevice.ioData(withCapacity: Int(request.length))
      let (status, count) = try await hostDevice.completedDeviceRequest(
        deviceRequest(for: request),
        data: buffer,
        completionTimeout: completionTimeout(milliseconds: windowsDescriptorTimeoutMilliseconds)
      )
      guard status == kIOReturnSuccess else { return .failure(transportError(status)) }
      return .success(unsafe Array(Data(bytes: buffer.bytes, count: min(count, buffer.length))))
    } catch { return .failure(transportError(error)) }
  }
}
