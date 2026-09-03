import Foundation
import IOKit

struct IOUSBHostPassiveUSBRegistrySource: PassiveUSBRegistrySource {
  func matchingServices(className: String, numericProperties: [String: UInt64]) throws
    -> [PassiveUSBRegistryNode]
  {
    try enumerate(className: className, numericProperties: numericProperties, includeChildren: true)
  }

  private func enumerate(
    className: String,
    numericProperties: [String: UInt64],
    includeChildren: Bool = false
  ) throws -> [PassiveUSBRegistryNode] {
    let matching = IOServiceMatching(className)
    numericProperties.forEach { key, value in
      var value = Int64(bitPattern: value)
      if let number = CFNumberCreate(kCFAllocatorDefault, .sInt64Type, &value) {
        let cfKey = key as CFString
        CFDictionarySetValue(
          matching,
          Unmanaged.passUnretained(cfKey).toOpaque(),
          Unmanaged.passUnretained(number).toOpaque()
        )
      }
    }
    var iterator: io_iterator_t = 0
    let result = IOServiceGetMatchingServices(kIOMasterPortDefault, matching, &iterator)
    guard result == kIOReturnSuccess else {
      throw PassiveUSBDescriptorProbeError.matchingFailed(result)
    }
    defer { IOObjectRelease(iterator) }
    var nodes: [PassiveUSBRegistryNode] = []
    while let service = next(iterator) {
      defer { IOObjectRelease(service) }
      nodes.append(try node(service, className: className, includeChildren: includeChildren))
    }
    return nodes
  }

  private func node(_ service: io_service_t, className: String, includeChildren: Bool) throws
    -> PassiveUSBRegistryNode
  {
    let numericKeys = [
      "idVendor", "idProduct", "locationID", "bDeviceClass", "bDeviceSubClass", "bDeviceProtocol",
      "bNumConfigurations", "kUSBCurrentConfiguration", "bInterfaceNumber", "bAlternateSetting",
      "bInterfaceClass", "bInterfaceSubClass", "bInterfaceProtocol", "bEndpointAddress",
      "wMaxPacketSize", "bInterval", "USBSpeed", "Device Speed", "UsbLinkSpeed", "USB Speed"
    ]
    let stringKeys = [
      "USB Product Name", "Product Name", "transferType", "USBSpeed", "Device Speed",
      "UsbLinkSpeed", "USB Speed"
    ]
    let byteKeys = [
      "Configuration Descriptor", "kUSBConfigurationDescriptor", "USB Configuration Descriptor",
      "DescriptorBytes", "descriptorBytes"
    ]
    var properties: [String: PassiveUSBRegistryNode.Value] = [:]
    for key in numericKeys {
      if let value = property(service, key: key), CFGetTypeID(value) == CFNumberGetTypeID() {
        var raw: Int64 = 0
        let number = unsafeDowncast(value, to: CFNumber.self)
        if CFNumberGetValue(number, .sInt64Type, &raw) {
          properties[key] = .unsignedInteger(UInt64(bitPattern: raw))
        }
      }
    }
    for key in stringKeys {
      if let value = property(service, key: key) as? String { properties[key] = .string(value) }
    }
    for key in byteKeys {
      if let value = property(service, key: key) as? Data { properties[key] = .bytes(Array(value)) }
    }
    var children: [PassiveUSBRegistryNode] = []
    if includeChildren {
      var iterator: io_iterator_t = 0
      let result = IORegistryEntryGetChildIterator(service, kIOServicePlane, &iterator)
      guard result == kIOReturnSuccess else {
        throw PassiveUSBDescriptorProbeError.matchingFailed(result)
      }
      defer { IOObjectRelease(iterator) }
      while let child = next(iterator) {
        defer { IOObjectRelease(child) }
        children.append(try node(child, className: registryClass(child), includeChildren: true))
      }
    }
    return PassiveUSBRegistryNode(
      serviceClass: className,
      properties: properties,
      children: children,
      registryPath: registryPath(service)
    )
  }

  private func registryPath(_ service: io_service_t) -> String {
    var buffer = [CChar](repeating: 0, count: 4_096)
    guard IORegistryEntryGetPath(service, kIOServicePlane, &buffer) == kIOReturnSuccess else {
      return ""
    }
    let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
    return String(bytes: bytes, encoding: .utf8) ?? ""
  }

  private func property(_ service: io_service_t, key: String) -> AnyObject? {
    IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
      .takeRetainedValue()
  }

  private func uint64(_ node: PassiveUSBRegistryNode, _ key: String) -> UInt64? {
    guard case .unsignedInteger(let value) = node.properties[key] else { return nil }
    return value
  }

  private func next(_ iterator: io_iterator_t) -> io_service_t? {
    let service = IOIteratorNext(iterator)
    return service == 0 ? nil : service
  }

  private func registryClass(_ service: io_service_t) -> String {
    var buffer = [CChar](repeating: 0, count: 128)
    guard IOObjectGetClass(service, &buffer) == kIOReturnSuccess else { return "IORegistryEntry" }
    let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
    return String(bytes: bytes, encoding: .utf8) ?? "IORegistryEntry"
  }
}
