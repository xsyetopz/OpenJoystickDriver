import Foundation
import IOKit
import OpenJoystickDriverKit

/// A vendor and product ID pair that a passive probe reads.
public struct PassiveUSBDescriptorTuple: Equatable, Sendable, Codable, Hashable {
  /// The USB vendor ID.
  public let vendorID: UInt16
  /// The USB product ID.
  public let productID: UInt16

  /// Creates the pair.
  public init(vendorID: UInt16, productID: UInt16) {
    self.vendorID = vendorID
    self.productID = productID
  }
}

/// Whether the registry shows a fact.
public enum PassiveUSBVerificationState: String, Equatable, Sendable, Codable {
  /// The registry shows the fact.
  case observed
  /// The registry does not show the fact.
  case unverified
}

/// The reasons a passive probe stops before it reads a device.
public enum PassiveUSBDescriptorProbeError: Error, Equatable, Sendable, LocalizedError {
  /// The vendor and product ID pair is not one of the authorized pairs.
  case tupleNotAuthorized
  /// The IORegistry matching call failed with the IOKit return code.
  case matchingFailed(Int32)
  /// No service matches the pair.
  case zeroMatches
  /// More than one service matches the pair.
  case multipleMatches

  /// The localized description of the failure.
  public var errorDescription: String? {
    switch self {
    case .tupleNotAuthorized: return "VID/PID tuple is not in the passive descriptor allowlist"
    case .matchingFailed(let code): return "IOKit matching failed with return code \(code)"
    case .zeroMatches: return "passive exact-tuple scan found zero devices"
    case .multipleMatches: return "passive exact-tuple scan found multiple devices"
    }
  }
}

/// A node of the IORegistry with its properties and children.
public struct PassiveUSBRegistryNode: Equatable, Sendable {
  /// A property value of a registry node.
  public enum Value: Equatable, Sendable {
    /// An unsigned integer value.
    case unsignedInteger(UInt64)
    /// A string value.
    case string(String)
    /// A byte-array value.
    case bytes([UInt8])
  }

  /// The class of the registry service.
  public let serviceClass: String
  /// The properties of the node by key.
  public let properties: [String: Value]
  /// The child nodes.
  public let children: [Self]
  /// The registry path of the node.
  public let registryPath: String
  /// The registry entry ID of the node, when IOKit gave one.
  let registryEntryID: UInt64?

  /// Creates a node.
  public init(
    serviceClass: String,
    properties: [String: Value],
    children: [Self] = [],
    registryPath: String = ""
  ) {
    self.init(
      serviceClass: serviceClass,
      properties: properties,
      children: children,
      registryPath: registryPath,
      registryEntryID: nil
    )
  }

  /// Creates a node with a registry entry ID.
  init(
    serviceClass: String,
    properties: [String: Value],
    children: [Self] = [],
    registryPath: String = "",
    registryEntryID: UInt64?
  ) {
    self.serviceClass = serviceClass
    self.properties = properties
    self.children = children
    self.registryPath = registryPath
    self.registryEntryID = registryEntryID
  }
}

/// The registry property that holds a descriptor blob.
public struct PassiveUSBDescriptorBlobSource: Equatable, Sendable, Codable {
  /// The registry property key.
  public let propertyKey: String
  /// The class of the service that holds the property.
  public let serviceClass: String
  /// The registry path of the service.
  public let registryPath: String
  /// The size of the blob in bytes.
  public let byteCount: Int

  /// Creates the source.
  public init(propertyKey: String, serviceClass: String, registryPath: String, byteCount: Int) {
    self.propertyKey = propertyKey
    self.serviceClass = serviceClass
    self.registryPath = registryPath
    self.byteCount = byteCount
  }
}

/// Whether a descriptor blob is available.
public struct PassiveUSBDescriptorBlobAvailability: Equatable, Sendable, Codable {
  /// Whether the blob can be read.
  public let state: PassiveUSBVerificationState
  /// Why the blob is or is not available.
  public let reason: String
  /// Where the blob comes from, when it is available.
  public let source: PassiveUSBDescriptorBlobSource?

  /// Creates the availability.
  public init(
    state: PassiveUSBVerificationState,
    reason: String,
    source: PassiveUSBDescriptorBlobSource? = nil
  ) {
    self.state = state
    self.reason = reason
    self.source = source
  }
}

/// The reasons the parser rejects a configuration descriptor blob.
public enum PassiveUSBDescriptorBlobError: Error, Equatable, Sendable {
  /// The blob is empty or larger than the parser accepts.
  case unsafeSize
  /// A descriptor ends before its fixed fields do.
  case truncated
  /// A descriptor declares a length of zero.
  case zeroLength
  /// A descriptor runs past the end of the blob.
  case descriptorOverrun
  /// The total length or the interface count differs from the descriptors the blob holds.
  case totalLengthMismatch
  /// The blob does not start with one configuration descriptor.
  case missingConfiguration
  /// Two interface descriptors share an interface number and alternate setting.
  case duplicateInterfaceOwnership
  /// An endpoint descriptor has no interface to belong to, or repeats an address of its interface.
  case impossibleEndpointOwnership
  /// The registry holds several descriptor properties that disagree.
  case ambiguousDescriptorProperties
  /// An endpoint address uses reserved bits or has no endpoint number.
  case invalidEndpointAddress
  /// The transfer attributes of an endpoint are not valid for its type or speed.
  case invalidTransferAttributes
  /// The interval of an endpoint is outside the range of its type or speed.
  case invalidInterval
  /// A SuperSpeed companion descriptor is not valid for its endpoint or speed.
  case invalidCompanionDescriptor
  /// A companion descriptor has no endpoint to belong to.
  case orphanCompanionDescriptor
}

/// A descriptor that the parser read.
public struct PassiveUSBParsedDescriptor: Equatable, Sendable, Codable {
  /// The descriptor type.
  public let type: UInt8
  /// The bytes of the descriptor, including its length and type.
  public let bytes: [UInt8]
}

/// An endpoint of an interface.
public struct PassiveUSBDescriptorEndpoint: Equatable, Sendable, Codable {
  /// The endpoint address, with the direction in the top bit.
  public let address: UInt8
  /// The transfer type name.
  public let transferType: String
  /// The maximum packet size in bytes.
  public let maxPacketSize: UInt16
  /// The interval field of the descriptor.
  public let interval: UInt8
  /// The nominal interval in microseconds; nil when the speed or transfer type has none.
  public let nominalIntervalMicroseconds: UInt64?
  /// Whether the interval is valid for the speed and transfer type.
  public let intervalResult: PassiveUSBIntervalResult
  /// The SuperSpeed companion of the endpoint, when it has one.
  public let superSpeedCompanion: PassiveUSBSuperSpeedCompanion?
  /// The SuperSpeedPlus companion of the endpoint, when it has one.
  public let superSpeedPlusCompanion: PassiveUSBSuperSpeedPlusCompanion?
}

/// Whether the interval field of an endpoint is valid.
public enum PassiveUSBIntervalResult: Equatable, Sendable, Codable {
  /// The speed or transfer type has no service interval.
  case unsupportedSpeedOrTransfer
  /// The transfer type is not interrupt or isochronous, so the interval is not a service interval.
  case ignoredNotServiceInterval
  /// The interval is valid, with its nominal value in microseconds.
  case validDescriptorNominal(UInt64)
  /// The interval is outside the range of its type and speed.
  case invalidRange
}

/// The SuperSpeed endpoint companion descriptor.
public struct PassiveUSBSuperSpeedCompanion: Equatable, Sendable, Codable {
  /// The maximum number of packets in a burst, minus one.
  public let maxBurst: UInt8
  /// The attributes byte.
  public let attributes: UInt8
  /// The bytes the endpoint moves per service interval.
  public let bytesPerInterval: UInt16
}

/// The SuperSpeedPlus isochronous endpoint companion descriptor.
public struct PassiveUSBSuperSpeedPlusCompanion: Equatable, Sendable, Codable {
  /// The bytes the endpoint moves per service interval.
  public let bytesPerInterval: UInt32
}

/// The link facts that bound the bytes of a SuperSpeedPlus isochronous interval.
public struct PassiveUSBSuperSpeedPlusValidationContext: Equatable, Sendable, Codable {
  /// The maximum isochronous bytes per bus interval at Gen1.
  public let maxIsoBytesPerBiGen1: UInt32
  /// The number of lanes of the link.
  public let numberOfLanes: UInt32
  /// The lane speed mantissa.
  public let laneSpeedMantissa: UInt32
  /// The lane speed mantissa at Gen1.
  public let laneSpeedMantissaGen1: UInt32

  /// Creates the context.
  public init(
    maxIsoBytesPerBiGen1: UInt32,
    numberOfLanes: UInt32,
    laneSpeedMantissa: UInt32,
    laneSpeedMantissaGen1: UInt32
  ) {
    self.maxIsoBytesPerBiGen1 = maxIsoBytesPerBiGen1
    self.numberOfLanes = numberOfLanes
    self.laneSpeedMantissa = laneSpeedMantissa
    self.laneSpeedMantissaGen1 = laneSpeedMantissaGen1
  }

  /// The most bytes one interval can carry, or nil when the link facts do not give a bound.
  public var maximumBytesPerInterval: UInt32? {
    guard numberOfLanes > 0, laneSpeedMantissaGen1 > 0 else { return nil }
    let product = UInt64(maxIsoBytesPerBiGen1).multipliedReportingOverflow(
      by: UInt64(numberOfLanes)
    )
    guard !product.overflow else { return nil }
    let scaled = product.partialValue.multipliedReportingOverflow(by: UInt64(laneSpeedMantissa))
    guard !scaled.overflow else { return nil }
    let value = scaled.partialValue / UInt64(laneSpeedMantissaGen1)
    return value <= UInt64(UInt32.max) ? UInt32(value) : nil
  }
}

/// An interface descriptor with its endpoints.
public struct PassiveUSBDescriptorInterface: Equatable, Sendable, Codable {
  /// The interface number.
  public let number: UInt8
  /// The alternate setting.
  public let alternateSetting: UInt8
  /// The interface class.
  public let interfaceClass: UInt8
  /// The interface subclass.
  public let interfaceSubclass: UInt8
  /// The interface protocol.
  public let interfaceProtocol: UInt8
  /// The number of endpoints that the descriptor declares.
  public let declaredEndpointCount: UInt8
  /// The endpoints that follow the descriptor.
  public let endpoints: [PassiveUSBDescriptorEndpoint]
}

/// The speed that the link negotiated.
public enum PassiveUSBNegotiatedSpeed: String, Equatable, Sendable, Codable {
  /// Low speed.
  case low
  /// Full speed.
  case full
  /// High speed.
  case high
  /// SuperSpeed.
  case superSpeed
  /// SuperSpeedPlus.
  case superSpeedPlus
}

/// A parsed configuration descriptor.
public struct PassiveUSBConfigurationDescriptor: Equatable, Sendable, Codable {
  /// The total length that the descriptor declares.
  public let totalLength: UInt16
  /// The number of interfaces that the descriptor declares.
  public let declaredInterfaceCount: UInt8
  /// Every descriptor of the blob, in order.
  public let descriptors: [PassiveUSBParsedDescriptor]
  /// The interfaces and their alternate settings.
  public let interfaces: [PassiveUSBDescriptorInterface]
  /// The speed used to validate the descriptors; nil when it is unknown.
  public let negotiatedSpeed: PassiveUSBNegotiatedSpeed?
}

/// Whether the registry shows a speed.
public enum PassiveUSBSpeedObservationState: String, Equatable, Sendable, Codable {
  /// No speed property is present.
  case absent
  /// The registry shows one speed.
  case observed
  /// The registry shows speeds that disagree.
  case ambiguous
}

/// The speed that the registry shows.
public struct PassiveUSBSpeedObservation: Equatable, Sendable, Codable {
  /// Whether the registry shows a speed.
  public let state: PassiveUSBSpeedObservationState
  /// The speed, when exactly one is shown.
  public let speed: PassiveUSBNegotiatedSpeed?
  /// The nodes that hold a speed property.
  public let sources: [String]
  /// The raw speed values.
  public let values: [String]
  /// Every speed property that the registry holds.
  public let properties: [PassiveUSBSpeedPropertyObservation]
}

/// One speed property of a registry node.
public struct PassiveUSBSpeedPropertyObservation: Equatable, Sendable, Codable {
  /// The property key.
  public let key: String
  /// The type of the raw value.
  public let rawType: String
  /// The raw value as text.
  public let rawValue: String
  /// The speed the value decodes to, when it decodes.
  public let decodedSpeed: PassiveUSBNegotiatedSpeed?
}
