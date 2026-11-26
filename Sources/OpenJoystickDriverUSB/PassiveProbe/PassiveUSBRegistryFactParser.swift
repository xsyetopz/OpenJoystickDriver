import Foundation

/// A source of registry nodes.
public protocol PassiveUSBRegistrySource: Sendable {
  /// Returns the nodes of the services of `className` whose numeric properties equal
  /// `numericProperties`.
  func matchingServices(
    className: String,
    numericProperties: [String: UInt64]
  ) throws -> [PassiveUSBRegistryNode]
}

/// Turns a registry node into a probe result.
public enum PassiveUSBRegistryFactParser {
  /// Parses `root` into a probe result for `tuple` with the given catalog inference.
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
    let (parsedDescriptor, parseError) = parseBlob(
      blob,
      ambiguous: ambiguous,
      negotiatedSpeed: negotiatedSpeed
    )
    let sources = blobs.map(\.source)
    let deviceClass = uint8(root, "bDeviceClass")
    let deviceSubclass = uint8(root, "bDeviceSubClass")
    let deviceProtocol = uint8(root, "bDeviceProtocol")
    let predicates =
      deviceClass == 0xFF && deviceSubclass == 0xFF && deviceProtocol == 0xFF
      ? ["P-DEV-255-255-255"] : []
    let blobSource = ambiguous ? nil : blob?.source
    let observed = PassiveUSBObservedUSBFacts(
      tuple: tuple,
      name: string(root, "USB Product Name") ?? string(root, "Product Name"),
      deviceRelease: uint16(root, "bcdDevice"),
      deviceClass: deviceClass,
      deviceSubclass: deviceSubclass,
      deviceProtocol: deviceProtocol,
      configurationCount: uint8(root, "bNumConfigurations"),
      activeConfiguration: uint8(root, "kUSBCurrentConfiguration"),
      interfacesState: .unverified,
      hidDescriptorState: .unverified,
      hidCollectionsState: .unverified,
      hidUsagesState: .unverified,
      serviceBindingsState: .unverified,
      serviceClasses: [root.serviceClass],
      descriptorBlobSource: blobSource,
      descriptorBlobSources: sources,
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
        sources: sources,
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

  /// A descriptor blob with the property and node it came from.
  private struct Blob {
    /// The registry property key.
    let key: String
    /// The bytes of the blob.
    let bytes: [UInt8]
    /// The node that holds the property.
    let node: PassiveUSBRegistryNode

    /// The registry location of the blob as the probe result reports it.
    var source: PassiveUSBDescriptorBlobSource {
      PassiveUSBDescriptorBlobSource(
        propertyKey: key,
        serviceClass: node.serviceClass,
        registryPath: node.registryPath,
        byteCount: bytes.count
      )
    }
  }

  /// Parses `blob`, or reports why the registry tree yields no single configuration descriptor.
  ///
  /// Both values are nil when the tree holds no blob.
  private static func parseBlob(
    _ blob: Blob?,
    ambiguous: Bool,
    negotiatedSpeed: PassiveUSBNegotiatedSpeed?
  ) -> (PassiveUSBConfigurationDescriptor?, PassiveUSBDescriptorBlobError?) {
    if ambiguous { return (nil, .ambiguousDescriptorProperties) }
    guard let blob else { return (nil, nil) }
    do {
      return (
        try PassiveUSBConfigurationDescriptorParser.parse(
          blob.bytes,
          negotiatedSpeed: negotiatedSpeed
        ),
        nil
      )
    } catch let error as PassiveUSBDescriptorBlobError {
      return (nil, error)
    } catch {
      return (nil, .truncated)
    }
  }

  /// The registry property keys that can hold a configuration descriptor blob.
  static let descriptorKeys = [
    "Configuration Descriptor", "kUSBConfigurationDescriptor", "USB Configuration Descriptor",
    "DescriptorBytes", "descriptorBytes",
  ]

  /// Returns the descriptor blobs that `node` holds.
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

  /// Returns the unsigned integer property `key` of `node` as an 8-bit value, or nil when it does
  /// not fit.
  private static func uint8(_ node: PassiveUSBRegistryNode, _ key: String) -> UInt8? {
    uint64(node, key).flatMap(UInt8.init(exactly:))
  }
  /// Returns the unsigned integer property `key` of `node` as a 16-bit value, or nil when it does
  /// not fit.
  private static func uint16(_ node: PassiveUSBRegistryNode, _ key: String) -> UInt16? {
    uint64(node, key).flatMap(UInt16.init(exactly:))
  }
  /// Returns the unsigned integer property `key` of `node`, or nil when it has none.
  private static func uint64(_ node: PassiveUSBRegistryNode, _ key: String) -> UInt64? {
    guard case .unsignedInteger(let value) = node.properties[key] else { return nil }
    return value
  }
  /// Returns the string property `key` of `node`, or nil when it has none.
  private static func string(_ node: PassiveUSBRegistryNode, _ key: String) -> String? {
    guard case .string(let value) = node.properties[key] else { return nil }
    return value
  }
}
