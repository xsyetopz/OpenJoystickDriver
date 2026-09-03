import Foundation
import IOKit
import OpenJoystickDriverKit

public struct PassiveUSBDescriptorTuple: Equatable, Sendable, Codable, Hashable {
  public let vendorID: UInt16
  public let productID: UInt16

  public init(vendorID: UInt16, productID: UInt16) {
    self.vendorID = vendorID
    self.productID = productID
  }
}

public enum PassiveUSBVerificationState: String, Equatable, Sendable, Codable {
  case observed
  case unverified
}

public enum PassiveUSBDescriptorProbeError: Error, Equatable, Sendable, LocalizedError {
  case contributorGateRequired
  case tupleNotAuthorized
  case matchingFailed(Int32)
  case zeroMatches
  case multipleMatches

  public var errorDescription: String? {
    switch self {
    case .contributorGateRequired: return "contributor gate required"
    case .tupleNotAuthorized: return "VID/PID tuple is not in the passive descriptor allowlist"
    case .matchingFailed(let code): return "IOKit matching failed with return code \(code)"
    case .zeroMatches: return "passive exact-tuple scan found zero devices"
    case .multipleMatches: return "passive exact-tuple scan found multiple devices"
    }
  }
}

public struct PassiveUSBEndpointFacts: Equatable, Sendable, Codable {
  public let address: UInt8
  public let direction: String
  public let transferType: String
  public let maxPacketSize: UInt16
  public let interval: UInt8
  public let superSpeedCompanion: PassiveUSBSuperSpeedCompanion?

  public init(
    address: UInt8,
    direction: String,
    transferType: String,
    maxPacketSize: UInt16,
    interval: UInt8,
    superSpeedCompanion: PassiveUSBSuperSpeedCompanion? = nil
  ) {
    self.address = address
    self.direction = direction
    self.transferType = transferType
    self.maxPacketSize = maxPacketSize
    self.interval = interval
    self.superSpeedCompanion = superSpeedCompanion
  }
}

public struct PassiveUSBInterfaceFacts: Equatable, Sendable, Codable {
  public let number: UInt8
  public let alternateSetting: UInt8
  public let interfaceClass: UInt8
  public let interfaceSubclass: UInt8
  public let interfaceProtocol: UInt8
  public let declaredEndpointCount: UInt8
  public let endpointState: PassiveUSBVerificationState
  public let endpoints: [PassiveUSBEndpointFacts]

  public init(
    number: UInt8,
    alternateSetting: UInt8,
    interfaceClass: UInt8,
    interfaceSubclass: UInt8,
    interfaceProtocol: UInt8,
    endpointState: PassiveUSBVerificationState,
    declaredEndpointCount: UInt8 = 0,
    endpoints: [PassiveUSBEndpointFacts]
  ) {
    self.number = number
    self.alternateSetting = alternateSetting
    self.interfaceClass = interfaceClass
    self.interfaceSubclass = interfaceSubclass
    self.interfaceProtocol = interfaceProtocol
    self.declaredEndpointCount = declaredEndpointCount
    self.endpointState = endpointState
    self.endpoints = endpoints
  }
}

public struct PassiveUSBRegistryNode: Equatable, Sendable {
  public enum Value: Equatable, Sendable {
    case unsignedInteger(UInt64)
    case string(String)
    case bytes([UInt8])
  }

  public let serviceClass: String
  public let properties: [String: Value]
  public let children: [Self]
  public let registryPath: String

  public init(
    serviceClass: String,
    properties: [String: Value],
    children: [Self] = [],
    registryPath: String = ""
  ) {
    self.serviceClass = serviceClass
    self.properties = properties
    self.children = children
    self.registryPath = registryPath
  }
}

public struct PassiveUSBDescriptorBlobSource: Equatable, Sendable, Codable {
  public let propertyKey: String
  public let serviceClass: String
  public let registryPath: String
  public let byteCount: Int

  public init(propertyKey: String, serviceClass: String, registryPath: String, byteCount: Int) {
    self.propertyKey = propertyKey
    self.serviceClass = serviceClass
    self.registryPath = registryPath
    self.byteCount = byteCount
  }
}

public struct PassiveUSBDescriptorBlobAvailability: Equatable, Sendable, Codable {
  public let state: PassiveUSBVerificationState
  public let reason: String
  public let source: PassiveUSBDescriptorBlobSource?

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

public enum PassiveUSBDescriptorBlobError: Error, Equatable, Sendable {
  case unsafeSize
  case truncated
  case zeroLength
  case descriptorOverrun
  case totalLengthMismatch
  case missingConfiguration
  case duplicateInterfaceOwnership
  case impossibleEndpointOwnership
  case ambiguousDescriptorProperties
  case invalidEndpointAddress
  case invalidTransferAttributes
  case invalidInterval
  case invalidCompanionDescriptor
  case orphanCompanionDescriptor
}

public struct PassiveUSBParsedDescriptor: Equatable, Sendable, Codable {
  public let type: UInt8
  public let bytes: [UInt8]
}

public struct PassiveUSBDescriptorEndpoint: Equatable, Sendable, Codable {
  public let address: UInt8
  public let transferType: String
  public let maxPacketSize: UInt16
  public let interval: UInt8
  public let nominalIntervalMicroseconds: UInt64?
  public let intervalResult: PassiveUSBIntervalResult
  public let superSpeedCompanion: PassiveUSBSuperSpeedCompanion?
  public let superSpeedPlusCompanion: PassiveUSBSuperSpeedPlusCompanion?
}

public enum PassiveUSBIntervalResult: Equatable, Sendable, Codable {
  case unsupportedSpeedOrTransfer
  case ignoredNotServiceInterval
  case validDescriptorNominal(UInt64)
  case invalidRange
}

public struct PassiveUSBSuperSpeedCompanion: Equatable, Sendable, Codable {
  public let maxBurst: UInt8
  public let attributes: UInt8
  public let bytesPerInterval: UInt16
}

public struct PassiveUSBSuperSpeedPlusCompanion: Equatable, Sendable, Codable {
  public let bytesPerInterval: UInt32
}

public struct PassiveUSBSuperSpeedPlusValidationContext: Equatable, Sendable, Codable {
  public let maxIsoBytesPerBiGen1: UInt32
  public let numberOfLanes: UInt32
  public let laneSpeedMantissa: UInt32
  public let laneSpeedMantissaGen1: UInt32

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

public struct PassiveUSBDescriptorInterface: Equatable, Sendable, Codable {
  public let number: UInt8
  public let alternateSetting: UInt8
  public let interfaceClass: UInt8
  public let interfaceSubclass: UInt8
  public let interfaceProtocol: UInt8
  public let declaredEndpointCount: UInt8
  public let endpoints: [PassiveUSBDescriptorEndpoint]
}

public enum PassiveUSBNegotiatedSpeed: String, Equatable, Sendable, Codable {
  case low
  case full
  case high
  case superSpeed
  case superSpeedPlus
}

public struct PassiveUSBConfigurationDescriptor: Equatable, Sendable, Codable {
  public let totalLength: UInt16
  public let declaredInterfaceCount: UInt8
  public let descriptors: [PassiveUSBParsedDescriptor]
  public let interfaces: [PassiveUSBDescriptorInterface]
  public let negotiatedSpeed: PassiveUSBNegotiatedSpeed?
}

public enum PassiveUSBSpeedObservationState: String, Equatable, Sendable, Codable {
  case absent
  case observed
  case ambiguous
}

public struct PassiveUSBSpeedObservation: Equatable, Sendable, Codable {
  public let state: PassiveUSBSpeedObservationState
  public let speed: PassiveUSBNegotiatedSpeed?
  public let sources: [String]
  public let values: [String]
  public let properties: [PassiveUSBSpeedPropertyObservation]
}

public struct PassiveUSBSpeedPropertyObservation: Equatable, Sendable, Codable {
  public let key: String
  public let rawType: String
  public let rawValue: String
  public let decodedSpeed: PassiveUSBNegotiatedSpeed?
}

public struct PassiveUSBObservedUSBFacts: Equatable, Sendable, Codable {
  public let tuple: PassiveUSBDescriptorTuple
  public let name: String?
  public let deviceClass: UInt8?
  public let deviceSubclass: UInt8?
  public let deviceProtocol: UInt8?
  public let configurationCount: UInt8?
  public let activeConfiguration: UInt8?
  public let interfacesState: PassiveUSBVerificationState
  public let interfaces: [PassiveUSBInterfaceFacts]
  public let hidDescriptorState: PassiveUSBVerificationState
  public let hidCollectionsState: PassiveUSBVerificationState
  public let hidUsagesState: PassiveUSBVerificationState
  public let serviceBindingsState: PassiveUSBVerificationState
  public let serviceClasses: [String]
  public let descriptorBlobSource: PassiveUSBDescriptorBlobSource?
  public let descriptorBlobSources: [PassiveUSBDescriptorBlobSource]
  public let descriptorBlobAvailability: PassiveUSBDescriptorBlobAvailability
  public let speedObservation: PassiveUSBSpeedObservation
  public let configurationDescriptor: PassiveUSBConfigurationDescriptor?
  public let descriptorParseError: String?
  public let verification: PassiveUSBVerificationFacts
}

public struct PassiveUSBVerificationFacts: Equatable, Sendable, Codable {
  public let endpointState: PassiveUSBVerificationState
  public let hidDescriptorState: PassiveUSBVerificationState
  public let hidCollectionsState: PassiveUSBVerificationState
  public let hidUsagesState: PassiveUSBVerificationState
  public let mappingState: PassiveUSBVerificationState
  public let inputState: PassiveUSBVerificationState
  public let outputState: PassiveUSBVerificationState
  public let reconnectState: PassiveUSBVerificationState
  public let latencyState: PassiveUSBVerificationState
  public let consumerRecognitionState: PassiveUSBVerificationState
  public let supportState: PassiveUSBVerificationState

  public init(
    endpointState: PassiveUSBVerificationState = .unverified,
    hidDescriptorState: PassiveUSBVerificationState = .unverified,
    hidCollectionsState: PassiveUSBVerificationState = .unverified,
    hidUsagesState: PassiveUSBVerificationState = .unverified,
    mappingState: PassiveUSBVerificationState = .unverified,
    inputState: PassiveUSBVerificationState = .unverified,
    outputState: PassiveUSBVerificationState = .unverified,
    reconnectState: PassiveUSBVerificationState = .unverified,
    latencyState: PassiveUSBVerificationState = .unverified,
    consumerRecognitionState: PassiveUSBVerificationState = .unverified,
    supportState: PassiveUSBVerificationState = .unverified
  ) {
    self.endpointState = endpointState
    self.hidDescriptorState = hidDescriptorState
    self.hidCollectionsState = hidCollectionsState
    self.hidUsagesState = hidUsagesState
    self.mappingState = mappingState
    self.inputState = inputState
    self.outputState = outputState
    self.reconnectState = reconnectState
    self.latencyState = latencyState
    self.consumerRecognitionState = consumerRecognitionState
    self.supportState = supportState
  }
}

public struct PassiveUSBCatalogInference: Equatable, Sendable, Codable {
  public let source: String
  public let record: String
  public let parser: String
  public let endpoints: [String: UInt8]
}

public struct PassiveUSBProtocolClassification: Equatable, Sendable, Codable {
  public let status: String
  public let descriptorPredicates: [String]
  public let wireProtocol: String
}

public enum PassiveUSBParsedDescriptorState: String, Equatable, Sendable, Codable {
  case absent
  case parsed
  case ambiguous
  case malformed
}

public struct PassiveUSBParsedDescriptorFacts: Equatable, Sendable, Codable {
  public let state: PassiveUSBParsedDescriptorState
  public let configuration: PassiveUSBConfigurationDescriptor?
  public let sources: [PassiveUSBDescriptorBlobSource]
  public let error: String?
}

public struct PassiveUSBSpecificationInference: Equatable, Sendable, Codable {
  public let sourceIDs: [String]
  public let claims: [String]
}

public struct PassiveUSBUserReportedPolling: Equatable, Sendable, Codable {
  public let state: PassiveUSBVerificationState
  public let reportsPerSecond: Double?
}

public struct PassiveUSBProbeResult: Equatable, Sendable, Codable {
  public let observedUSBFacts: PassiveUSBObservedUSBFacts
  public let parsedDescriptorFacts: PassiveUSBParsedDescriptorFacts
  public let specificationInference: PassiveUSBSpecificationInference
  public let catalogInference: PassiveUSBCatalogInference
  public let protocolClassification: PassiveUSBProtocolClassification
  public let userReportedPolling: PassiveUSBUserReportedPolling
}

public protocol PassiveUSBRegistrySource: Sendable {
  func matchingServices(className: String, numericProperties: [String: UInt64]) throws
    -> [PassiveUSBRegistryNode]
}

public enum PassiveUSBRegistryFactParser {
  public static func parse(
    root: PassiveUSBRegistryNode,
    tuple: PassiveUSBDescriptorTuple,
    catalogInference: PassiveUSBCatalogInference
  ) -> PassiveUSBProbeResult {
    let blobs = findDescriptorBlobs(root)
    let blob = blobs.first
    let ambiguous = blobs.map(\.bytes).contains { $0 != blob?.bytes }
    let speedObservation = observeSpeed(root)
    let negotiatedSpeed = speedObservation.state == .observed ? speedObservation.speed : nil
    let parsed: Result<PassiveUSBConfigurationDescriptor, PassiveUSBDescriptorBlobError>?
    if ambiguous {
      parsed = .failure(.ambiguousDescriptorProperties)
    } else if let blob {
      do {
        parsed = .success(
          try PassiveUSBConfigurationDescriptorParser.parse(
            blob.bytes,
            negotiatedSpeed: negotiatedSpeed
          )
        )
      } catch let error as PassiveUSBDescriptorBlobError { parsed = .failure(error) } catch {
        parsed = .failure(.truncated)
      }
    } else {
      parsed = nil
    }
    let parsedDescriptor: PassiveUSBConfigurationDescriptor?
    let parseError: PassiveUSBDescriptorBlobError?
    switch parsed {
    case .success(let value):
      parsedDescriptor = value
      parseError = nil
    case .failure(let error):
      parsedDescriptor = nil
      parseError = error
    case nil:
      parsedDescriptor = nil
      parseError = nil
    }
    let deviceClass = uint8(root, "bDeviceClass")
    let deviceSubclass = uint8(root, "bDeviceSubClass")
    let deviceProtocol = uint8(root, "bDeviceProtocol")
    let predicates =
      deviceClass == 0xFF && deviceSubclass == 0xFF && deviceProtocol == 0xFF
      ? ["P-DEV-255-255-255"] : []
    let blobSource =
      ambiguous
      ? nil
      : blob.map {
        PassiveUSBDescriptorBlobSource(
          propertyKey: $0.key,
          serviceClass: $0.node.serviceClass,
          registryPath: $0.node.registryPath,
          byteCount: $0.bytes.count
        )
      }
    let observed = PassiveUSBObservedUSBFacts(
      tuple: tuple,
      name: string(root, "USB Product Name") ?? string(root, "Product Name"),
      deviceClass: deviceClass,
      deviceSubclass: deviceSubclass,
      deviceProtocol: deviceProtocol,
      configurationCount: uint8(root, "bNumConfigurations"),
      activeConfiguration: uint8(root, "kUSBCurrentConfiguration"),
      interfacesState: .unverified,
      interfaces: [],
      hidDescriptorState: .unverified,
      hidCollectionsState: .unverified,
      hidUsagesState: .unverified,
      serviceBindingsState: .unverified,
      serviceClasses: [root.serviceClass],
      descriptorBlobSource: blobSource,
      descriptorBlobSources: blobs.map {
        PassiveUSBDescriptorBlobSource(
          propertyKey: $0.key,
          serviceClass: $0.node.serviceClass,
          registryPath: $0.node.registryPath,
          byteCount: $0.bytes.count
        )
      },
      descriptorBlobAvailability: PassiveUSBDescriptorBlobAvailability(
        state: parsedDescriptor == nil ? .unverified : .observed,
        reason: blobs.isEmpty
          ? "no readable descriptor byte property in exact-tuple registry tree"
          : parseError.map { String(describing: $0) } ?? "parsed",
        source: blobSource
      ),
      speedObservation: speedObservation,
      configurationDescriptor: nil,
      descriptorParseError: nil,
      verification: PassiveUSBVerificationFacts(endpointState: .unverified)
    )
    let parsedState: PassiveUSBParsedDescriptorState =
      ambiguous
      ? .ambiguous : parsedDescriptor != nil ? .parsed : blob == nil ? .absent : .malformed
    return PassiveUSBProbeResult(
      observedUSBFacts: observed,
      parsedDescriptorFacts: PassiveUSBParsedDescriptorFacts(
        state: parsedState,
        configuration: parsedDescriptor,
        sources: blobs.map {
          PassiveUSBDescriptorBlobSource(
            propertyKey: $0.key,
            serviceClass: $0.node.serviceClass,
            registryPath: $0.node.registryPath,
            byteCount: $0.bytes.count
          )
        },
        error: parseError.map { String(describing: $0) }
      ),
      specificationInference: PassiveUSBSpecificationInference(
        sourceIDs: ["USB-2.0-9.6.6", "USB-3.2-9.6.6"],
        claims: ["bInterval is descriptor-nominal only"]
      ),
      catalogInference: catalogInference,
      protocolClassification: PassiveUSBProtocolClassification(
        status: predicates.isEmpty ? "UNVERIFIED" : "device-descriptor vendor-specific",
        descriptorPredicates: predicates,
        wireProtocol: "UNVERIFIED"
      ),
      userReportedPolling: PassiveUSBUserReportedPolling(state: .unverified, reportsPerSecond: nil)
    )
  }

  private struct Blob {
    let key: String
    let bytes: [UInt8]
    let node: PassiveUSBRegistryNode
  }

  private static let descriptorKeys = [
    "Configuration Descriptor", "kUSBConfigurationDescriptor", "USB Configuration Descriptor",
    "DescriptorBytes", "descriptorBytes"
  ]

  private static func findDescriptorBlobs(_ node: PassiveUSBRegistryNode) -> [Blob] {
    var result: [Blob] = []
    for key in descriptorKeys {
      if case .bytes(let bytes) = node.properties[key] {
        result.append(Blob(key: key, bytes: bytes, node: node))
      }
    }
    for child in node.children { result.append(contentsOf: findDescriptorBlobs(child)) }
    return result
  }

  private static func uint8(_ node: PassiveUSBRegistryNode, _ key: String) -> UInt8? {
    uint64(node, key).flatMap(UInt8.init(exactly:))
  }
  private static func uint16(_ node: PassiveUSBRegistryNode, _ key: String) -> UInt16? {
    uint64(node, key).flatMap(UInt16.init(exactly:))
  }
  private static func uint64(_ node: PassiveUSBRegistryNode, _ key: String) -> UInt64? {
    guard case .unsignedInteger(let value) = node.properties[key] else { return nil }
    return value
  }
  private static func string(_ node: PassiveUSBRegistryNode, _ key: String) -> String? {
    guard case .string(let value) = node.properties[key] else { return nil }
    return value
  }
}

public enum PassiveUSBDescriptorProbe {
  public static let authorizedTuples: Set<PassiveUSBDescriptorTuple> = [
    PassiveUSBDescriptorTuple(vendorID: 0x3537, productID: 0x1010)
  ]

  public static func contributorGate(
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> Bool {
    _isDebugAssertConfiguration() && environment["OJD_ENABLE_CONTRIBUTOR_USB_PASSIVE"] == "1"
  }

  #if DEBUG
    public static let buildMode = "DEBUG"
  #else
    public static let buildMode = "RELEASE"
  #endif

  public static func scan(authorizedTuple tuple: PassiveUSBDescriptorTuple) throws
    -> PassiveUSBProbeResult
  {
    guard contributorGate() else { throw PassiveUSBDescriptorProbeError.contributorGateRequired }
    return try scanWithoutGate(authorizedTuple: tuple, source: IOUSBHostPassiveUSBRegistrySource())
  }

  static func scanWithoutGate(
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

  /// Reads descriptor-backed transport facts without claiming an interface or
  /// issuing a USB transfer. This path is intentionally independent of the
  /// contributor gate and does not participate in raw-USB admission.
  static func transportObservation(for device: USBTransportDevice) throws
    -> ControllerTransportObservation?
  {
    let tuple = PassiveUSBDescriptorTuple(vendorID: device.vendorID, productID: device.productID)
    let roots = try IOUSBHostPassiveUSBRegistrySource().matchingServices(
      className: "IOUSBHostDevice",
      numericProperties: ["idVendor": UInt64(tuple.vendorID), "idProduct": UInt64(tuple.productID)]
    )
    guard
      let root = roots.first(where: { node in
        guard case .unsignedInteger(let location) = node.properties["locationID"] else {
          return false
        }
        return UInt32(exactly: location) == device.locationID
      })
    else { return nil }

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
    let interfaces = (result.parsedDescriptorFacts.configuration?.interfaces ?? []).map {
      USBInterfaceTransportFacts(
        interfaceNumber: $0.number,
        alternateSetting: $0.alternateSetting,
        interfaceClass: $0.interfaceClass,
        interfaceSubclass: $0.interfaceSubclass,
        interfaceProtocol: $0.interfaceProtocol,
        configurationValue: result.observedUSBFacts.activeConfiguration,
        endpoints: $0.endpoints.map {
          USBEndpointTransportFacts(
            address: $0.address,
            transferType: endpointTransferType($0.transferType),
            direction: $0.address & 0x80 == 0 ? .out : .in,
            maxPacketSize: $0.maxPacketSize,
            interval: $0.interval
          )
        }
      )
    }
    return ControllerTransportObservation(device: device, interfaces: interfaces)
  }

  private static func endpointTransferType(_ value: String) -> USBEndpointTransferType {
    switch value.lowercased() {
    case "control": return .control
    case "isochronous", "isochronous-adaptive", "isochronous-synchronous": return .isochronous
    case "bulk": return .bulk
    case "interrupt": return .interrupt
    default: return .unknown
    }
  }

  #if DEBUG
    public static func scanUsingContributorSource(
      authorizedTuple tuple: PassiveUSBDescriptorTuple,
      source: any PassiveUSBRegistrySource
    ) throws -> PassiveUSBProbeResult {
      guard contributorGate() else { throw PassiveUSBDescriptorProbeError.contributorGateRequired }
      return try scanWithoutGate(authorizedTuple: tuple, source: source)
    }
  #endif
}
