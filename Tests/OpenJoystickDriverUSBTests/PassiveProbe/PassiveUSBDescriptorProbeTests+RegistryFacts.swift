import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverUSB

extension PassiveUSBDescriptorProbeTests {
  @Test
  func exactTupleAuthorization() {
    let tuple = PassiveUSBDescriptorTuple(vendorID: 0x3537, productID: 0x1010)
    #expect(PassiveUSBDescriptorProbe.authorizedTuples.contains(tuple))
    #expect(
      !PassiveUSBDescriptorProbe.authorizedTuples.contains(
        PassiveUSBDescriptorTuple(vendorID: 1, productID: 2)
      )
    )
  }

  @Test
  func constrainedScanRejectsUnauthorizedZeroAndMultipleAndDoesNotAskSource() throws {
    let source = SpySource(matches: [])
    let unauthorized = PassiveUSBDescriptorTuple(vendorID: 1, productID: 2)
    #expect(throws: PassiveUSBDescriptorProbeError.tupleNotAuthorized) {
      try PassiveUSBDescriptorProbe.scan(authorizedTuple: unauthorized, source: source)
    }
    #expect(source.calls.isEmpty)
    let tuple = PassiveUSBDescriptorTuple(vendorID: 0x3537, productID: 0x1010)
    #expect(throws: PassiveUSBDescriptorProbeError.zeroMatches) {
      try PassiveUSBDescriptorProbe.scan(authorizedTuple: tuple, source: source)
    }
    source.matches = [fixtureRoot(), fixtureRoot()]
    #expect(throws: PassiveUSBDescriptorProbeError.multipleMatches) {
      try PassiveUSBDescriptorProbe.scan(authorizedTuple: tuple, source: source)
    }
    #expect(
      source.calls.allSatisfy {
        $0.className == "IOUSBHostDevice"
          && $0.properties == ["idVendor": 0x3537, "idProduct": 0x1010]
      }
    )
  }

  @Test
  func nestedRegistryParserPreservesOwnershipAndZeroDescriptors() throws {
    let tuple = PassiveUSBDescriptorTuple(vendorID: 0x3537, productID: 0x1010)
    let result = PassiveUSBRegistryFactParser.parse(
      root: fixtureRoot(),
      tuple: tuple,
      catalogInference: catalogInference()
    )
    let interface = try #require(result.parsedDescriptorFacts.configuration?.interfaces.first)
    let endpoint = try #require(interface.endpoints.first)
    #expect(interface.number == 0 && interface.alternateSetting == 0)
    #expect(endpoint.address == 1 && endpoint.maxPacketSize == 0 && endpoint.interval == 1)
    #expect(endpoint.address & 0x80 == 0)
    #expect(result.observedUSBFacts.interfacesState == .unverified)
    #expect(result.parsedDescriptorFacts.state == .parsed)
  }

  @Test
  func observedUSBDeviceReleasePreservesBcdDeviceAndUnavailableValues() {
    let tuple = PassiveUSBDescriptorTuple(vendorID: 0x3537, productID: 0x1010)
    let root = fixtureRoot()
    let releaseRoot = PassiveUSBRegistryNode(
      serviceClass: root.serviceClass,
      properties: root.properties.merging(["bcdDevice": .unsignedInteger(0x0210)]) { _, new in new
      },
      children: root.children,
      registryPath: root.registryPath
    )
    let result = PassiveUSBRegistryFactParser.parse(
      root: releaseRoot,
      tuple: tuple,
      catalogInference: catalogInference()
    )
    #expect(result.observedUSBFacts.deviceRelease == 0x0210)

    let device = USBTransportDevice(
      route: .rawUSB,
      serviceID: 12,
      vendorID: tuple.vendorID,
      productID: tuple.productID,
      locationID: 42
    )
    #expect(
      PassiveUSBDescriptorProbe.physicalDevice(from: result, for: device).deviceRelease == 0x0210
    )

    let missing = PassiveUSBRegistryFactParser.parse(
      root: root,
      tuple: tuple,
      catalogInference: catalogInference()
    )
    #expect(missing.observedUSBFacts.deviceRelease == nil)

    let outOfRangeRoot = PassiveUSBRegistryNode(
      serviceClass: root.serviceClass,
      properties: root.properties.merging(["bcdDevice": .unsignedInteger(0x1_0000)]) { _, new in new
      },
      children: root.children,
      registryPath: root.registryPath
    )
    let outOfRange = PassiveUSBRegistryFactParser.parse(
      root: outOfRangeRoot,
      tuple: tuple,
      catalogInference: catalogInference()
    )
    #expect(outOfRange.observedUSBFacts.deviceRelease == nil)
    #expect(
      PassiveUSBDescriptorProbe.physicalDevice(from: outOfRange, for: device).deviceRelease == nil
    )
  }

  @Test
  func layersAndContradictionsAreTypedAndInferenceCannotBecomeObservation() throws {
    let tuple = PassiveUSBDescriptorTuple(vendorID: 0x3537, productID: 0x1010)
    let result = PassiveUSBRegistryFactParser.parse(
      root: fixtureRoot(),
      tuple: tuple,
      catalogInference: catalogInference()
    )
    #expect(result.catalogInference.parser == "catalog-backed; not observed from descriptors")
    #expect(result.catalogInference.endpoints["input"] == 0x81)
    #expect(result.parsedDescriptorFacts.configuration?.interfaces.first?.endpoints.count == 1)
    #expect(result.protocolClassification.status == "device-descriptor vendor-specific")
    var contradictory = fixtureRoot()
    contradictory = PassiveUSBRegistryNode(
      serviceClass: contradictory.serviceClass,
      properties: contradictory.properties.merging(["bDeviceProtocol": .unsignedInteger(0)]) {
        _,
        rhs in rhs
      },
      children: contradictory.children
    )
    let contradiction = PassiveUSBRegistryFactParser.parse(
      root: contradictory,
      tuple: tuple,
      catalogInference: catalogInference()
    )
    #expect(contradiction.protocolClassification.status == "UNVERIFIED")
    #expect(contradiction.protocolClassification.wireProtocol == "UNVERIFIED")
    let verification = result.observedUSBFacts.verification
    #expect(verification.endpointState == .unverified)
    #expect(verification.hidDescriptorState == .unverified)
    #expect(verification.hidCollectionsState == .unverified)
    #expect(verification.hidUsagesState == .unverified)
    #expect(verification.mappingState == .unverified)
    #expect(verification.inputState == .unverified)
    #expect(verification.outputState == .unverified)
    #expect(verification.reconnectState == .unverified)
    #expect(verification.latencyState == .unverified)
    #expect(verification.consumerRecognitionState == .unverified)
    #expect(verification.supportState == .unverified)
    let data = try JSONEncoder().encode(result)
    let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(
      object.keys.sorted() == [
        "catalogInference", "observedUSBFacts", "parsedDescriptorFacts", "protocolClassification",
        "specificationInference", "userReportedPolling",
      ]
    )
    #expect(noSensitiveKeys(object))
  }

  @Test
  func alternateSettingsKeepTheirOwnEndpoints() throws {
    let root = PassiveUSBRegistryNode(
      serviceClass: "IOUSBHostDevice",
      properties: [
        "bDeviceClass": .unsignedInteger(0xFF), "bDeviceSubClass": .unsignedInteger(0xFF),
        "bDeviceProtocol": .unsignedInteger(0xFF), "bNumConfigurations": .unsignedInteger(1),
        "Configuration Descriptor": .bytes([
          9, 2, 0x29, 0, 1, 1, 0, 0x80, 0x32, 9, 4, 0, 0, 1, 0xFF, 0x47, 0xD0, 0, 7, 5, 0x81, 3, 0,
          0, 1, 9, 4, 0, 1, 1, 0xFF, 0x47, 0xD0, 0, 7, 5, 2, 3, 0, 0, 1,
        ]),
      ],
      children: []
    )
    let result = PassiveUSBRegistryFactParser.parse(
      root: root,
      tuple: PassiveUSBDescriptorTuple(vendorID: 0x3537, productID: 0x1010),
      catalogInference: catalogInference()
    )
    let interfaces = try #require(result.parsedDescriptorFacts.configuration?.interfaces)
    #expect(interfaces.map(\.alternateSetting) == [0, 1])
    #expect(interfaces.map { $0.endpoints.map(\.address) } == [[0x81], [0x02]])

    let device = USBTransportDevice(
      route: .rawUSB,
      serviceID: 12,
      vendorID: 0x3537,
      productID: 0x1010,
      locationID: 42
    )
    let physicalDevice = PassiveUSBDescriptorProbe.physicalDevice(from: result, for: device)
    let signatures = try #require(physicalDevice.interfaces)
    #expect(signatures.map(\.interfaceNumber) == [0, 0])
    #expect(signatures.map(\.alternateSetting) == [0, 1])
    #expect(signatures.compactMap { $0.endpoints?.first?.address } == [0x81, 0x02])
    #expect(signatures.allSatisfy { $0.hostTransport == .usb && $0.usbRoute == .rawUSB })
    #expect(signatures.allSatisfy { $0.physicalTransport == nil && $0.accessBackend == nil })
    #expect(physicalDevice.serviceAddress == device.serviceAddress)
    #expect(physicalDevice.physicalLocationIdentifier == 42)
    #expect(physicalDevice.stableParentDeviceIdentifier == nil)
    #expect(physicalDevice.deviceRelease == nil)
    #expect(physicalDevice.deviceClass == 0xFF)
    #expect(physicalDevice.configurationValue == nil)

    let unavailableDescriptorResult = PassiveUSBProbeResult(
      observedUSBFacts: result.observedUSBFacts,
      parsedDescriptorFacts: PassiveUSBParsedDescriptorFacts(
        state: .absent,
        configuration: nil,
        sources: [],
        error: nil
      ),
      specificationInference: result.specificationInference,
      catalogInference: result.catalogInference,
      protocolClassification: result.protocolClassification,
      userReportedPolling: result.userReportedPolling
    )
    #expect(
      PassiveUSBDescriptorProbe.physicalDevice(from: unavailableDescriptorResult, for: device)
        .interfaces == nil
    )
  }

  @Test
  func descriptorParserRejectsMalformedBlobsAndKeepsUnknownDescriptors() throws {
    #expect(throws: PassiveUSBDescriptorBlobError.missingConfiguration) {
      try PassiveUSBConfigurationDescriptorParser.parse([9, 4, 0, 0, 0, 0, 0, 0, 0])
    }
    #expect(throws: PassiveUSBDescriptorBlobError.zeroLength) {
      try PassiveUSBConfigurationDescriptorParser.parse([0, 2])
    }
    #expect(throws: PassiveUSBDescriptorBlobError.descriptorOverrun) {
      try PassiveUSBConfigurationDescriptorParser.parse([9, 2, 9, 0])
    }
    #expect(throws: PassiveUSBDescriptorBlobError.totalLengthMismatch) {
      try PassiveUSBConfigurationDescriptorParser.parse([9, 2, 10, 0, 0, 1, 0, 0, 0])
    }
    let parsed = try PassiveUSBConfigurationDescriptorParser.parse([
      9, 2, 0x15, 0, 1, 1, 0, 0x80, 0x32, 3, 0x99, 0, 9, 4, 0, 0, 0, 0xFF, 0x47, 0xD0, 0,
    ])
    #expect(parsed.descriptors.map(\.type) == [2, 0x99, 4])
    #expect(parsed.interfaces.count == 1)
    #expect(parsed.interfaces[0].endpoints.isEmpty)
  }
}
