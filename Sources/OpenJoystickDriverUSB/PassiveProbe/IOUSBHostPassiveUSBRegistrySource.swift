import Foundation
import IOKit

/// Reads USB device nodes from the IORegistry without opening any device.
struct IOUSBHostPassiveUSBRegistrySource: PassiveUSBRegistrySource {
  /// Registry levels read below each matched service; nil reads the whole subtree.
  ///
  /// Runtime observation reads only the device's direct children (its interfaces), so a hub's
  /// downstream devices are never walked.
  var childDepth: Int?

  /// Returns the nodes of the services of `className` whose numeric properties equal
  /// `numericProperties`, with their children to `childDepth` levels.
  func matchingServices(
    className: String,
    numericProperties: [String: UInt64]
  ) throws -> [PassiveUSBRegistryNode] {
    try enumerate(className: className, numericProperties: numericProperties, depth: childDepth)
  }

  /// Returns the nodes of the services of `className` whose numeric properties equal
  /// `numericProperties`, with their children to `depth` levels.
  private func enumerate(
    className: String,
    numericProperties: [String: UInt64],
    depth: Int?
  ) throws -> [PassiveUSBRegistryNode] {
    let matching = unsafe IOServiceMatching(className)
    for (key, rawValue) in numericProperties {
      var value = Int64(bitPattern: rawValue)
      if let number = unsafe CFNumberCreate(kCFAllocatorDefault, .sInt64Type, &value) {
        let cfKey = key as CFString
        unsafe CFDictionarySetValue(
          matching,
          Unmanaged.passUnretained(cfKey).toOpaque(),
          Unmanaged.passUnretained(number).toOpaque()
        )
      }
    }
    var iterator: io_iterator_t = 0
    let result = unsafe IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
    guard result == kIOReturnSuccess else {
      throw PassiveUSBDescriptorProbeError.matchingFailed(result)
    }
    defer { IOObjectRelease(iterator) }
    var nodes: [PassiveUSBRegistryNode] = []
    while let service = next(iterator) {
      defer { IOObjectRelease(service) }
      nodes.append(try node(service, className: className, depth: depth))
    }
    return nodes
  }

  /// Reads `service` into a node, with its children to `depth` levels.
  private func node(
    _ service: io_service_t,
    className: String,
    depth: Int?
  ) throws -> PassiveUSBRegistryNode {
    let numericKeys = [
      "idVendor", "idProduct", "locationID", "bDeviceClass", "bDeviceSubClass", "bDeviceProtocol",
      "bcdDevice", "bNumConfigurations", "kUSBCurrentConfiguration", "bInterfaceNumber",
      "bAlternateSetting", "bInterfaceClass", "bInterfaceSubClass", "bInterfaceProtocol",
      "bEndpointAddress", "wMaxPacketSize", "bInterval", "USBSpeed", "Device Speed", "UsbLinkSpeed",
      "USB Speed",
    ]
    let stringKeys = [
      "USB Product Name", "Product Name", "transferType", "USBSpeed", "Device Speed",
      "UsbLinkSpeed", "USB Speed",
    ]
    let byteKeys = [
      "Configuration Descriptor", "kUSBConfigurationDescriptor", "USB Configuration Descriptor",
      "DescriptorBytes", "descriptorBytes",
    ]
    var properties: [String: PassiveUSBRegistryNode.Value] = [:]
    for key in numericKeys {
      if let value = property(service, key: key), CFGetTypeID(value) == CFNumberGetTypeID() {
        var raw: Int64 = 0
        let number = unsafe unsafeDowncast(value, to: CFNumber.self)
        if unsafe CFNumberGetValue(number, .sInt64Type, &raw) {
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
    if depth.map({ $0 > 0 }) ?? true {
      var iterator: io_iterator_t = 0
      let result = unsafe IORegistryEntryGetChildIterator(service, kIOServicePlane, &iterator)
      guard result == kIOReturnSuccess else {
        throw PassiveUSBDescriptorProbeError.matchingFailed(result)
      }
      defer { IOObjectRelease(iterator) }
      while let child = next(iterator) {
        defer { IOObjectRelease(child) }
        children.append(
          try node(child, className: registryClass(child), depth: depth.map { $0 - 1 })
        )
      }
    }
    return PassiveUSBRegistryNode(
      serviceClass: className,
      properties: properties,
      children: children,
      registryPath: registryPath(service),
      registryEntryID: registryEntryID(service)
    )
  }

  /// Returns the registry entry ID of `service`, or nil when IOKit cannot give one.
  private func registryEntryID(_ service: io_service_t) -> UInt64? {
    var value: UInt64 = 0
    return unsafe IORegistryEntryGetRegistryEntryID(service, &value) == kIOReturnSuccess
      ? value : nil
  }

  /// Returns the registry path of `service` in the service plane, or an empty string when IOKit
  /// cannot give one.
  private func registryPath(_ service: io_service_t) -> String {
    var buffer = [CChar](repeating: 0, count: 4_096)
    guard unsafe IORegistryEntryGetPath(service, kIOServicePlane, &buffer) == kIOReturnSuccess
    else {
      return ""
    }
    let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
    return String(bytes: bytes, encoding: .utf8) ?? ""
  }

  /// Reads the registry property `key` of `service`.
  private func property(_ service: io_service_t, key: String) -> AnyObject? {
    unsafe IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
      .takeRetainedValue()
  }

  /// Returns the unsigned integer property `key` of `node`, or nil when it has none.
  private func uint64(_ node: PassiveUSBRegistryNode, _ key: String) -> UInt64? {
    guard case .unsignedInteger(let value) = node.properties[key] else { return nil }
    return value
  }

  /// Returns the next service of `iterator`, or nil at its end.
  private func next(_ iterator: io_iterator_t) -> io_service_t? {
    let service = IOIteratorNext(iterator)
    return service == 0 ? nil : service
  }

  /// Returns the class name of `service`, `IORegistryEntry` when IOKit cannot give one.
  private func registryClass(_ service: io_service_t) -> String {
    var buffer = [CChar](repeating: 0, count: 128)
    guard unsafe IOObjectGetClass(service, &buffer) == kIOReturnSuccess else {
      return "IORegistryEntry"
    }
    let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
    return String(bytes: bytes, encoding: .utf8) ?? "IORegistryEntry"
  }
}
