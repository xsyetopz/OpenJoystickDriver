import Foundation
import IOKit
import OpenJoystickDriverKit

/// Reads the descriptor facts of a connected device from the registry without opening it.
public enum PassiveUSBDescriptorProbe {
  /// The vendor and product ID pairs that the probe may read.
  public static let authorizedTuples: Set<PassiveUSBDescriptorTuple> = [
    PassiveUSBDescriptorTuple(vendorID: 0x3537, productID: 0x1010)
  ]

  /// Reads the registry facts of the one connected device of an authorized tuple.
  ///
  /// The read claims no interface and issues no USB transfer, as the passive read of USB detection
  /// does.
  public static func scan(
    authorizedTuple tuple: PassiveUSBDescriptorTuple
  ) throws -> PassiveUSBProbeResult {
    try scan(authorizedTuple: tuple, source: IOUSBHostPassiveUSBRegistrySource())
  }

  /// Reads the facts of `tuple` from `source`.
  ///
  /// - Throws: ``PassiveUSBDescriptorProbeError`` when the pair is not authorized or the registry
  ///   holds no single match.
  static func scan(
    authorizedTuple tuple: PassiveUSBDescriptorTuple,
    source: any PassiveUSBRegistrySource
  ) throws -> PassiveUSBProbeResult {
    guard authorizedTuples.contains(tuple) else {
      throw PassiveUSBDescriptorProbeError.tupleNotAuthorized
    }
    let matches = try source.matchingServices(
      className: "IOUSBHostDevice",
      numericProperties: ["idVendor": UInt64(tuple.vendorID), "idProduct": UInt64(tuple.productID)]
    )
    switch matches.count {
    case 0: throw PassiveUSBDescriptorProbeError.zeroMatches
    case 1: break
    default: throw PassiveUSBDescriptorProbeError.multipleMatches
    }
    let catalog = PassiveUSBCatalogInference(
      source: "OpenJoystickDriver catalog",
      record: "3537:1010",
      parser: "catalog-backed; not observed from descriptors",
      endpoints: [:]
    )
    return PassiveUSBRegistryFactParser.parse(
      root: matches[0],
      tuple: tuple,
      catalogInference: catalog
    )
  }

  /// Reads descriptor-backed transport facts without claiming an interface or issuing a USB
  /// transfer.
  ///
  /// It takes any device, not only an authorized tuple, and does not participate in raw-USB
  /// admission.
  ///
  /// `configurationDescriptor` is the device's own descriptor of its current configuration, read by
  /// the transport; it replaces any registry descriptor bytes, so its endpoints become observable.
  static func physicalDeviceObservation(
    for device: USBTransportDevice,
    configurationDescriptor: [UInt8]? = nil
  ) throws -> PhysicalDevice? {
    try physicalDeviceObservation(
      for: device,
      source: IOUSBHostPassiveUSBRegistrySource(childDepth: 1),
      configurationDescriptor: configurationDescriptor
    )
  }

  /// Builds the physical device observation for `device` from the registry, using
  /// `configurationDescriptor` for its interfaces when it is given.
  static func physicalDeviceObservation(
    for device: USBTransportDevice,
    source: any PassiveUSBRegistrySource,
    configurationDescriptor: [UInt8]? = nil
  ) throws -> PhysicalDevice? {
    let tuple = PassiveUSBDescriptorTuple(vendorID: device.vendorID, productID: device.productID)
    let roots = try source.matchingServices(
      className: "IOUSBHostDevice",
      numericProperties: ["idVendor": UInt64(tuple.vendorID), "idProduct": UInt64(tuple.productID)]
    )
    let exactServiceRoots = roots.filter { root in
      guard root.registryEntryID == Optional(device.serviceID),
        let vendorID = unsignedInteger(root, "idVendor").flatMap(UInt16.init(exactly:)),
        let productID = unsignedInteger(root, "idProduct").flatMap(UInt16.init(exactly:)),
        let locationID = unsignedInteger(root, "locationID").flatMap(UInt32.init(exactly:))
      else { return false }
      return vendorID == device.vendorID && productID == device.productID
        && locationID == device.locationID
    }
    guard exactServiceRoots.count == 1, var root = exactServiceRoots.first else { return nil }
    if let configurationDescriptor {
      var properties = root.properties
      for key in PassiveUSBRegistryFactParser.descriptorKeys { properties.removeValue(forKey: key) }
      properties["Configuration Descriptor"] = .bytes(configurationDescriptor)
      root = PassiveUSBRegistryNode(
        serviceClass: root.serviceClass,
        properties: properties,
        children: root.children,
        registryPath: root.registryPath,
        registryEntryID: root.registryEntryID
      )
    }

    let result = PassiveUSBRegistryFactParser.parse(
      root: root,
      tuple: tuple,
      catalogInference: PassiveUSBCatalogInference(
        source: "descriptor observation",
        record: "not resolved",
        parser: "not selected",
        endpoints: [:]
      )
    )
    return physicalDevice(
      from: result,
      for: device,
      registryChildren: root.children,
      configurationDescriptor: configurationDescriptor
    )
  }

  /// Returns the unsigned integer property `key` of `node`, or nil when it has none.
  private static func unsignedInteger(_ node: PassiveUSBRegistryNode, _ key: String) -> UInt64? {
    guard case .unsignedInteger(let value) = node.properties[key] else { return nil }
    return value
  }

  /// Interfaces come from the parsed configuration descriptor.
  ///
  /// When the strict parser rejects a transport-read descriptor, a structural walk keeps every
  /// interface it can decode, so a malformed alternate setting OJD never claims does not discard
  /// the rest. Without descriptor bytes, the device's own `IOUSBHostInterface` children supply
  /// number, alternate setting and class triple, with endpoints left absent; children of a hub's
  /// downstream devices are never read.
  static func physicalDevice(
    from result: PassiveUSBProbeResult,
    for device: USBTransportDevice,
    registryChildren: [PassiveUSBRegistryNode] = [],
    configurationDescriptor: [UInt8]? = nil
  ) -> PhysicalDevice {
    let descriptorInterfaces = result.parsedDescriptorFacts.configuration.map { configuration in
      configuration.interfaces.map { interface in
        PhysicalInterfaceSignature(
          interfaceNumber: interface.number,
          alternateSetting: interface.alternateSetting,
          interfaceClass: interface.interfaceClass,
          interfaceSubclass: interface.interfaceSubclass,
          interfaceProtocol: interface.interfaceProtocol,
          configurationValue: result.observedUSBFacts.activeConfiguration,
          hostTransport: .usb,
          physicalTransport: nil,
          accessBackend: device.route == .usbExtension ? .usbExtension : nil,
          usbRoute: device.route,
          endpoints: interface.endpoints.map { endpoint in
            PhysicalEndpointSignature(
              address: endpoint.address,
              direction: endpoint.address & 0x80 == 0 ? .out : .in,
              transferType: endpointTransferType(endpoint.transferType),
              maxPacketSize: endpoint.maxPacketSize,
              interval: endpoint.interval
            )
          }
        )
      }
    }

    let interfaces =
      descriptorInterfaces ?? configurationDescriptor.flatMap {
        structuralInterfaces(
          $0,
          configurationValue: result.observedUSBFacts.activeConfiguration,
          route: device.route
        )
      }
      ?? registryInterfaces(
        registryChildren,
        configurationValue: result.observedUSBFacts.activeConfiguration,
        route: device.route
      )
    return PhysicalDevice(
      serviceAddress: device.serviceAddress,
      vendorID: device.vendorID,
      productID: device.productID,
      deviceRelease: result.observedUSBFacts.deviceRelease,
      deviceClass: result.observedUSBFacts.deviceClass,
      deviceSubclass: result.observedUSBFacts.deviceSubclass,
      deviceProtocol: result.observedUSBFacts.deviceProtocol,
      configurationValue: result.observedUSBFacts.activeConfiguration,
      productName: device.productName ?? result.observedUSBFacts.name,
      physicalLocationIdentifier: device.locationID,
      stableParentDeviceIdentifier: nil,
      interfaces: interfaces
    )
  }

  /// Returns the interface signatures of the interface nodes among `children`, or nil when there
  /// are none.
  private static func registryInterfaces(
    _ children: [PassiveUSBRegistryNode],
    configurationValue: UInt8?,
    route: USBTransportRoute
  ) -> [PhysicalInterfaceSignature]? {
    let interfaces = children.filter { $0.serviceClass == "IOUSBHostInterface" }.compactMap {
      child -> PhysicalInterfaceSignature? in
      guard let number = uint8(child, "bInterfaceNumber") else { return nil }
      return PhysicalInterfaceSignature(
        interfaceNumber: number,
        alternateSetting: uint8(child, "bAlternateSetting"),
        interfaceClass: uint8(child, "bInterfaceClass"),
        interfaceSubclass: uint8(child, "bInterfaceSubClass"),
        interfaceProtocol: uint8(child, "bInterfaceProtocol"),
        configurationValue: configurationValue,
        hostTransport: .usb,
        accessBackend: route == .usbExtension ? .usbExtension : nil,
        usbRoute: route
      )
    }
    return interfaces.isEmpty ? nil : interfaces
  }

  /// Returns the property `key` of `node` as an 8-bit value, or nil when it does not fit.
  private static func uint8(_ node: PassiveUSBRegistryNode, _ key: String) -> UInt8? {
    unsignedInteger(node, key).flatMap(UInt8.init(exactly:))
  }

  /// Returns the endpoint transfer type that the registry name `value` names.
  private static func endpointTransferType(_ value: String) -> USBEndpointTransferType {
    switch value.lowercased() {
    case "control": return .control
    case "isochronous", "isochronous-adaptive", "isochronous-synchronous": return .isochronous
    case "bulk": return .bulk
    case "interrupt": return .interrupt
    default: return .unknown
    }
  }
}
