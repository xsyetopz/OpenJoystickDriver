import Foundation
import Testing

@testable import OpenJoystickDriverUSB

struct PassiveUSBDescriptorProbeTests {
  @Test func exactTupleAuthorizationAndContributorGate() {
    let tuple = PassiveUSBDescriptorTuple(vendorID: 0x3537, productID: 0x1010)
    #expect(PassiveUSBDescriptorProbe.authorizedTuples.contains(tuple))
    #expect(
      !PassiveUSBDescriptorProbe.authorizedTuples.contains(
        PassiveUSBDescriptorTuple(vendorID: 1, productID: 2)
      )
    )
    #expect(PassiveUSBDescriptorProbe.contributorGate(environment: [:]) == false)
    #expect(
      PassiveUSBDescriptorProbe.contributorGate(environment: [
        "OJD_ENABLE_CONTRIBUTOR_USB_PASSIVE": "1"
      ])
    )
  }
  @Test func constrainedScanRejectsUnauthorizedZeroAndMultipleAndDoesNotAskSource() throws {
    let source = SpySource(matches: [])
    let unauthorized = PassiveUSBDescriptorTuple(vendorID: 1, productID: 2)
    #expect(throws: PassiveUSBDescriptorProbeError.tupleNotAuthorized) {
      try PassiveUSBDescriptorProbe.scanWithoutGate(authorizedTuple: unauthorized, source: source)
    }
    #expect(source.calls.isEmpty)
    let tuple = PassiveUSBDescriptorTuple(vendorID: 0x3537, productID: 0x1010)
    #expect(throws: PassiveUSBDescriptorProbeError.zeroMatches) {
      try PassiveUSBDescriptorProbe.scanWithoutGate(authorizedTuple: tuple, source: source)
    }
    source.matches = [fixtureRoot(), fixtureRoot()]
    #expect(throws: PassiveUSBDescriptorProbeError.multipleMatches) {
      try PassiveUSBDescriptorProbe.scanWithoutGate(authorizedTuple: tuple, source: source)
    }
    #expect(
      source.calls.allSatisfy {
        $0.className == "IOUSBHostDevice"
          && $0.properties == ["idVendor": 0x3537, "idProduct": 0x1010]
      }
    )
  }
  @Test func nestedRegistryParserPreservesOwnershipAndZeroDescriptors() throws {
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
  @Test func layersAndContradictionsAreTypedAndInferenceCannotBecomeObservation() throws {
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
        "specificationInference", "userReportedPolling"
      ]
    )
    #expect(noSensitiveKeys(object))
  }
  @Test func alternateSettingsKeepTheirOwnEndpoints() throws {
    let root = PassiveUSBRegistryNode(
      serviceClass: "IOUSBHostDevice",
      properties: [
        "bDeviceClass": .unsignedInteger(0xFF), "bDeviceSubClass": .unsignedInteger(0xFF),
        "bDeviceProtocol": .unsignedInteger(0xFF), "bNumConfigurations": .unsignedInteger(1),
        "Configuration Descriptor": .bytes([
          9, 2, 0x29, 0, 1, 1, 0, 0x80, 0x32, 9, 4, 0, 0, 1, 0xFF, 0x47, 0xD0, 0, 7, 5, 0x81, 3, 0,
          0, 1, 9, 4, 0, 1, 1, 0xFF, 0x47, 0xD0, 0, 7, 5, 2, 3, 0, 0, 1
        ])
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
  }
  @Test func descriptorParserRejectsMalformedBlobsAndKeepsUnknownDescriptors() throws {
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
      9, 2, 0x15, 0, 1, 1, 0, 0x80, 0x32, 3, 0x99, 0, 9, 4, 0, 0, 0, 0xFF, 0x47, 0xD0, 0
    ])
    #expect(parsed.descriptors.map(\.type) == [2, 0x99, 4])
    #expect(parsed.interfaces.count == 1)
    #expect(parsed.interfaces[0].endpoints.isEmpty)
  }
  @Test func endpointCountsAddressesAttributesAndIntervalsAreStrict() throws {
    func blob(endpointCount: UInt8, endpoint: [UInt8]) -> [UInt8] {
      [
        9, 2, UInt8(18 + endpoint.count), 0, 1, 1, 0, 0x80, 0x32, 9, 4, 0, 0, endpointCount, 0xFF,
        0x47, 0xD0, 0
      ] + endpoint
    }
    #expect(throws: PassiveUSBDescriptorBlobError.totalLengthMismatch) {
      try _ = PassiveUSBConfigurationDescriptorParser.parse(
        blob(endpointCount: 2, endpoint: [7, 5, 1, 3, 0, 0, 1])
      )
    }
    #expect(throws: PassiveUSBDescriptorBlobError.invalidEndpointAddress) {
      try _ = PassiveUSBConfigurationDescriptorParser.parse(
        blob(endpointCount: 1, endpoint: [7, 5, 0, 3, 0, 0, 1])
      )
    }
    #expect(throws: PassiveUSBDescriptorBlobError.invalidEndpointAddress) {
      try _ = PassiveUSBConfigurationDescriptorParser.parse(
        blob(endpointCount: 1, endpoint: [7, 5, 0x71, 3, 0, 0, 1])
      )
    }
    #expect(throws: PassiveUSBDescriptorBlobError.invalidTransferAttributes) {
      try PassiveUSBConfigurationDescriptorParser.parse(
        blob(endpointCount: 1, endpoint: [7, 5, 1, 0xC3, 0, 0, 1])
      )
    }
    #expect(throws: PassiveUSBDescriptorBlobError.invalidInterval) {
      try PassiveUSBConfigurationDescriptorParser.parse(
        blob(endpointCount: 1, endpoint: [7, 5, 1, 3, 0, 0, 0]),
        negotiatedSpeed: .full
      )
    }
    #expect(throws: PassiveUSBDescriptorBlobError.invalidInterval) {
      try PassiveUSBConfigurationDescriptorParser.parse(
        blob(endpointCount: 1, endpoint: [7, 5, 1, 1, 0, 0, 17]),
        negotiatedSpeed: .high
      )
    }
  }
  @Test func intervalBoundariesAreSpeedAndTransferScoped() throws {
    func parse(_ transfer: UInt8, _ interval: UInt8, _ speed: PassiveUSBNegotiatedSpeed) throws
      -> UInt64?
    {
      try PassiveUSBConfigurationDescriptorParser.parse(
        [
          9, 2, 25, 0, 1, 1, 0, 0x80, 0x32, 9, 4, 0, 0, 1, 0xFF, 0x47, 0xD0, 0, 7, 5, 1, transfer,
          0, 0, interval
        ],
        negotiatedSpeed: speed
      ).interfaces[0].endpoints[0].nominalIntervalMicroseconds
    }
    #expect(try parse(3, 1, .full) == 1_000)
    #expect(try parse(3, 255, .full) == 255_000)
    #expect(try parse(3, 1, .high) == 125)
    #expect(try parse(3, 16, .high) == 4_096_000)
    #expect(try parse(1, 1, .full) == 1_000)
    #expect(try parse(1, 16, .full) == 32_768_000)
    #expect(try parse(2, 1, .high) == nil)
    #expect(try parse(0, 1, .high) == nil)
  }
  @Test func endpointUsageAndLowSpeedTransferRulesAreIndependent() throws {
    func blob(attributes: UInt8, interval: UInt8) -> [UInt8] {
      [
        9, 2, 25, 0, 1, 1, 0, 0x80, 0x32, 9, 4, 0, 0, 1, 0xFF, 0x47, 0xD0, 0, 7, 5, 1, attributes,
        64, 0, interval
      ]
    }
    for usage in [UInt8(0x03), UInt8(0x13)] {
      var base = blob(attributes: usage, interval: usage == 0x13 ? 8 : 1)
      base[2] = 31
      let parsed = try PassiveUSBConfigurationDescriptorParser.parse(
        base + [6, 0x30, 0, 0, 64, 0],
        negotiatedSpeed: .superSpeedPlus
      )
      #expect(parsed.interfaces[0].endpoints.count == 1)
    }
    for usage in [UInt8(0x23), UInt8(0x33)] {
      #expect(throws: PassiveUSBDescriptorBlobError.invalidTransferAttributes) {
        try PassiveUSBConfigurationDescriptorParser.parse(
          blob(attributes: usage, interval: 1),
          negotiatedSpeed: .superSpeed
        )
      }
    }
    #expect(throws: PassiveUSBDescriptorBlobError.invalidTransferAttributes) {
      try PassiveUSBConfigurationDescriptorParser.parse(blob(attributes: 0x13, interval: 8))
    }
    #expect(throws: PassiveUSBDescriptorBlobError.invalidTransferAttributes) {
      try PassiveUSBConfigurationDescriptorParser.parse(
        blob(attributes: 2, interval: 1),
        negotiatedSpeed: .low
      )
    }
    #expect(throws: PassiveUSBDescriptorBlobError.invalidTransferAttributes) {
      try PassiveUSBConfigurationDescriptorParser.parse(
        blob(attributes: 1, interval: 1),
        negotiatedSpeed: .low
      )
    }
    #expect(throws: PassiveUSBDescriptorBlobError.invalidInterval) {
      try PassiveUSBConfigurationDescriptorParser.parse(blob(attributes: 1, interval: 17))
    }
  }
  @Test func isochronousUsageValuesAcceptZeroOneTwoAndRejectThree() throws {
    func blob(_ attributes: UInt8) -> [UInt8] {
      [
        9, 2, 25, 0, 1, 1, 0, 0x80, 0x32, 9, 4, 0, 0, 1, 0xFF, 0x47, 0xD0, 0, 7, 5, 1, attributes,
        0, 2, 1
      ]
    }
    for attributes in [UInt8(1), UInt8(0x11), UInt8(0x21)] {
      #expect(throws: Never.self) {
        try _ = PassiveUSBConfigurationDescriptorParser.parse(blob(attributes))
      }
    }
    #expect(throws: PassiveUSBDescriptorBlobError.invalidTransferAttributes) {
      try _ = PassiveUSBConfigurationDescriptorParser.parse(blob(0x31))
    }
  }
  @Test func isochronousSynchronizationValuesAreAllAccepted() throws {
    func blob(_ attributes: UInt8) -> [UInt8] {
      [
        9, 2, 25, 0, 1, 1, 0, 0x80, 0x32, 9, 4, 0, 0, 1, 0xFF, 0x47, 0xD0, 0, 7, 5, 1, attributes,
        0, 2, 1
      ]
    }
    for attributes in [UInt8(1), UInt8(5), UInt8(9), UInt8(13)] {
      #expect(throws: Never.self) {
        try _ = PassiveUSBConfigurationDescriptorParser.parse(blob(attributes))
      }
    }
  }
  @Test func periodicZeroIsInvalidBeforeSpeedIsKnown() {
    let bytes: [UInt8] = [
      9, 2, 25, 0, 1, 1, 0, 0x80, 0x32, 9, 4, 0, 0, 1, 0xFF, 0x47, 0xD0, 0, 7, 5, 1, 3, 0, 0, 0
    ]
    #expect(throws: PassiveUSBDescriptorBlobError.invalidInterval) {
      try _ = PassiveUSBConfigurationDescriptorParser.parse(bytes)
    }
  }
  @Test func superSpeedCompanionsAreOwnedAndValidated() throws {
    let regular: [UInt8] = [
      9, 2, 31, 0, 1, 1, 0, 0x80, 0x32, 9, 4, 0, 0, 1, 0xFF, 0x47, 0xD0, 0, 7, 5, 1, 3, 64, 0, 1, 6,
      0x30, 0, 0, 64, 0
    ]
    let parsed = try PassiveUSBConfigurationDescriptorParser.parse(
      regular,
      negotiatedSpeed: .superSpeed
    )
    #expect(parsed.interfaces[0].endpoints[0].superSpeedCompanion?.maxBurst == 0)
    #expect(parsed.interfaces[0].endpoints[0].superSpeedPlusCompanion == nil)
    #expect(throws: PassiveUSBDescriptorBlobError.orphanCompanionDescriptor) {
      try PassiveUSBConfigurationDescriptorParser.parse(
        [9, 2, 15, 0, 0, 1, 0, 0x80, 0x32, 6, 0x30, 0, 0, 0, 0],
        negotiatedSpeed: .superSpeed
      )
    }
    #expect(throws: PassiveUSBDescriptorBlobError.invalidCompanionDescriptor) {
      var duplicate = regular
      duplicate[2] = 37
      duplicate[28] = 0x20
      try _ = PassiveUSBConfigurationDescriptorParser.parse(
        duplicate + [6, 0x30, 0, 0, 0, 0],
        negotiatedSpeed: .superSpeed
      )
    }
    let ssp: [UInt8] = [
      9, 2, 39, 0, 1, 1, 0, 0x80, 0x32, 9, 4, 0, 0, 1, 0xFF, 0x47, 0xD0, 0, 7, 5, 1, 1, 0, 2, 1, 6,
      0x30, 0, 0x80, 1, 0, 8, 0x31, 0, 0, 0x50, 0xC3, 0, 0
    ]
    let sspParsed = try PassiveUSBConfigurationDescriptorParser.parse(
      ssp,
      negotiatedSpeed: .superSpeedPlus,
      superSpeedPlusContext: PassiveUSBSuperSpeedPlusValidationContext(
        maxIsoBytesPerBiGen1: 60_000,
        numberOfLanes: 1,
        laneSpeedMantissa: 1,
        laneSpeedMantissaGen1: 1
      )
    )
    #expect(
      sspParsed.interfaces[0].endpoints[0].superSpeedPlusCompanion?.bytesPerInterval == 50_000
    )
    #expect(throws: PassiveUSBDescriptorBlobError.invalidCompanionDescriptor) {
      try PassiveUSBConfigurationDescriptorParser.parse(
        ssp,
        negotiatedSpeed: .superSpeed,
        superSpeedPlusContext: PassiveUSBSuperSpeedPlusValidationContext(
          maxIsoBytesPerBiGen1: 60_000,
          numberOfLanes: 1,
          laneSpeedMantissa: 1,
          laneSpeedMantissaGen1: 1
        )
      )
    }
    #expect(throws: PassiveUSBDescriptorBlobError.orphanCompanionDescriptor) {
      let orphan: [UInt8] = [
        9, 2, 33, 0, 1, 1, 0, 0x80, 0x32, 9, 4, 0, 0, 1, 0xFF, 0x47, 0xD0, 0, 7, 5, 1, 1, 0, 0, 1,
        8, 0x31, 0, 0, 0, 0, 0, 0
      ]
      try _ = PassiveUSBConfigurationDescriptorParser.parse(
        orphan,
        negotiatedSpeed: .superSpeedPlus,
        superSpeedPlusContext: PassiveUSBSuperSpeedPlusValidationContext(
          maxIsoBytesPerBiGen1: 60_000,
          numberOfLanes: 1,
          laneSpeedMantissa: 1,
          laneSpeedMantissaGen1: 1
        )
      )
    }
  }
  @Test func superSpeedPacketBurstMatrixIsTransferSpecific() throws {
    func blob(transfer: UInt8, packet: UInt16, burst: UInt8) -> [UInt8] {
      [
        9, 2, 31, 0, 1, 1, 0, 0x80, 0x32, 9, 4, 0, 0, 1, 0xFF, 0x47, 0xD0, 0, 7, 5, 1, transfer,
        UInt8(packet & 0xFF), UInt8(packet >> 8), 1, 6, 0x30, burst, 0, 0, 0
      ]
    }
    for packet in [UInt16(1), UInt16(1_024)] {
      #expect(throws: Never.self) {
        try _ = PassiveUSBConfigurationDescriptorParser.parse(
          blob(transfer: 3, packet: packet, burst: 0),
          negotiatedSpeed: .superSpeed
        )
      }
    }
    #expect(throws: PassiveUSBDescriptorBlobError.invalidCompanionDescriptor) {
      try _ = PassiveUSBConfigurationDescriptorParser.parse(
        blob(transfer: 3, packet: 64, burst: 1),
        negotiatedSpeed: .superSpeed
      )
    }
    #expect(throws: Never.self) {
      try _ = PassiveUSBConfigurationDescriptorParser.parse(
        blob(transfer: 3, packet: 1_024, burst: 1),
        negotiatedSpeed: .superSpeed
      )
    }
    #expect(throws: Never.self) {
      try _ = PassiveUSBConfigurationDescriptorParser.parse(
        blob(transfer: 1, packet: 0, burst: 0),
        negotiatedSpeed: .superSpeed
      )
    }
    #expect(throws: PassiveUSBDescriptorBlobError.invalidCompanionDescriptor) {
      try _ = PassiveUSBConfigurationDescriptorParser.parse(
        blob(transfer: 1, packet: 512, burst: 1),
        negotiatedSpeed: .superSpeed
      )
    }
    #expect(throws: Never.self) {
      try _ = PassiveUSBConfigurationDescriptorParser.parse(
        blob(transfer: 1, packet: 1_024, burst: 1),
        negotiatedSpeed: .superSpeed
      )
    }
  }
  @Test func superSpeedControlAndBulkPacketAndStreamBoundariesAreStrict() throws {
    func blob(transfer: UInt8, packet: UInt16, burst: UInt8, attributes: UInt8, bytes: UInt16 = 0)
      -> [UInt8]
    {
      [
        9, 2, 31, 0, 1, 1, 0, 0x80, 0x32, 9, 4, 0, 0, 1, 0xFF, 0x47, 0xD0, 0, 7, 5, 1, transfer,
        UInt8(packet & 0xFF), UInt8(packet >> 8), 1, 6, 0x30, burst, attributes,
        UInt8(bytes & 0xFF), UInt8(bytes >> 8)
      ]
    }
    #expect(throws: Never.self) {
      try _ = PassiveUSBConfigurationDescriptorParser.parse(
        blob(transfer: 0, packet: 512, burst: 0, attributes: 0),
        negotiatedSpeed: .superSpeed
      )
    }
    #expect(throws: PassiveUSBDescriptorBlobError.invalidCompanionDescriptor) {
      try _ = PassiveUSBConfigurationDescriptorParser.parse(
        blob(transfer: 0, packet: 512, burst: 1, attributes: 0),
        negotiatedSpeed: .superSpeed
      )
    }
    #expect(throws: PassiveUSBDescriptorBlobError.invalidCompanionDescriptor) {
      try _ = PassiveUSBConfigurationDescriptorParser.parse(
        blob(transfer: 0, packet: 64, burst: 0, attributes: 0),
        negotiatedSpeed: .superSpeed
      )
    }
    #expect(throws: Never.self) {
      try _ = PassiveUSBConfigurationDescriptorParser.parse(
        blob(transfer: 2, packet: 1_024, burst: 0, attributes: 0),
        negotiatedSpeed: .superSpeed
      )
    }
    for streams in [UInt8(0), UInt8(16)] {
      #expect(throws: Never.self) {
        try _ = PassiveUSBConfigurationDescriptorParser.parse(
          blob(transfer: 2, packet: 1_024, burst: 0, attributes: streams),
          negotiatedSpeed: .superSpeed
        )
      }
    }
    for attributes in [UInt8(17), UInt8(0x20), UInt8(0x80)] {
      #expect(throws: PassiveUSBDescriptorBlobError.invalidCompanionDescriptor) {
        try _ = PassiveUSBConfigurationDescriptorParser.parse(
          blob(transfer: 2, packet: 1_024, burst: 0, attributes: attributes),
          negotiatedSpeed: .superSpeed
        )
      }
    }
    #expect(throws: PassiveUSBDescriptorBlobError.invalidCompanionDescriptor) {
      try _ = PassiveUSBConfigurationDescriptorParser.parse(
        blob(transfer: 2, packet: 1_024, burst: 0, attributes: 0, bytes: 1),
        negotiatedSpeed: .superSpeed
      )
    }
  }
  @Test func superSpeedInterruptAndIsoPacketAndByteBoundariesAreStrict() throws {
    func blob(
      transfer: UInt8,
      packet: UInt16,
      burst: UInt8,
      attributes: UInt8 = 0,
      bytes: UInt16 = 0
    ) -> [UInt8] {
      [
        9, 2, 31, 0, 1, 1, 0, 0x80, 0x32, 9, 4, 0, 0, 1, 0xFF, 0x47, 0xD0, 0, 7, 5, 1, transfer,
        UInt8(packet & 0xFF), UInt8(packet >> 8), 1, 6, 0x30, burst, attributes,
        UInt8(bytes & 0xFF), UInt8(bytes >> 8)
      ]
    }
    for packet in [UInt16(0), UInt16(1_025)] {
      #expect(throws: PassiveUSBDescriptorBlobError.invalidCompanionDescriptor) {
        try _ = PassiveUSBConfigurationDescriptorParser.parse(
          blob(transfer: 3, packet: packet, burst: 0),
          negotiatedSpeed: .superSpeed
        )
      }
    }
    #expect(throws: PassiveUSBDescriptorBlobError.invalidCompanionDescriptor) {
      try _ = PassiveUSBConfigurationDescriptorParser.parse(
        blob(transfer: 1, packet: 1_025, burst: 0),
        negotiatedSpeed: .superSpeed
      )
    }
    #expect(throws: PassiveUSBDescriptorBlobError.invalidCompanionDescriptor) {
      try _ = PassiveUSBConfigurationDescriptorParser.parse(
        blob(transfer: 1, packet: 1_024, burst: 0, attributes: 0x04),
        negotiatedSpeed: .superSpeed
      )
    }
    #expect(throws: Never.self) {
      try _ = PassiveUSBConfigurationDescriptorParser.parse(
        blob(transfer: 1, packet: 1_024, burst: 1, attributes: 0, bytes: 1),
        negotiatedSpeed: .superSpeed
      )
    }
    #expect(throws: Never.self) {
      try _ = PassiveUSBConfigurationDescriptorParser.parse(
        blob(transfer: 1, packet: 1_024, burst: 0, attributes: 0, bytes: 1_024),
        negotiatedSpeed: .superSpeed
      )
    }
  }
  @Test func sspBoundaryContextAndOrderingCasesAreTyped() throws {
    func fixture(dw: UInt32 = 50_000, marker: UInt8 = 0x80, sspBytes: UInt16 = 1) -> [UInt8] {
      [
        9, 2, 39, 0, 1, 1, 0, 0x80, 0x32, 9, 4, 0, 0, 1, 0xFF, 0x47, 0xD0, 0, 7, 5, 1, 1, 0, 2, 1,
        6, 0x30, 0, marker, UInt8(sspBytes & 0xFF), UInt8(sspBytes >> 8), 8, 0x31, 0, 0,
        UInt8(dw & 0xFF), UInt8((dw >> 8) & 0xFF), UInt8((dw >> 16) & 0xFF), UInt8(dw >> 24)
      ]
    }
    let context = PassiveUSBSuperSpeedPlusValidationContext(
      maxIsoBytesPerBiGen1: 60_000,
      numberOfLanes: 1,
      laneSpeedMantissa: 1,
      laneSpeedMantissaGen1: 1
    )
    #expect(throws: PassiveUSBDescriptorBlobError.invalidCompanionDescriptor) {
      try _ = PassiveUSBConfigurationDescriptorParser.parse(
        fixture(dw: 49_152),
        negotiatedSpeed: .superSpeedPlus,
        superSpeedPlusContext: context
      )
    }
    #expect(throws: PassiveUSBDescriptorBlobError.invalidCompanionDescriptor) {
      try _ = PassiveUSBConfigurationDescriptorParser.parse(
        fixture(dw: 60_000),
        negotiatedSpeed: .superSpeedPlus,
        superSpeedPlusContext: context
      )
    }
    #expect(throws: Never.self) {
      try _ = PassiveUSBConfigurationDescriptorParser.parse(
        fixture(dw: 59_999),
        negotiatedSpeed: .superSpeedPlus,
        superSpeedPlusContext: context
      )
    }
    #expect(throws: PassiveUSBDescriptorBlobError.invalidCompanionDescriptor) {
      try _ = PassiveUSBConfigurationDescriptorParser.parse(
        fixture(),
        negotiatedSpeed: .superSpeed,
        superSpeedPlusContext: context
      )
    }
    #expect(throws: PassiveUSBDescriptorBlobError.invalidCompanionDescriptor) {
      try _ = PassiveUSBConfigurationDescriptorParser.parse(
        fixture(),
        negotiatedSpeed: .superSpeedPlus
      )
    }
    #expect(throws: PassiveUSBDescriptorBlobError.orphanCompanionDescriptor) {
      try _ = PassiveUSBConfigurationDescriptorParser.parse(
        fixture(marker: 0),
        negotiatedSpeed: .superSpeedPlus,
        superSpeedPlusContext: context
      )
    }
    #expect(throws: PassiveUSBDescriptorBlobError.invalidCompanionDescriptor) {
      try _ = PassiveUSBConfigurationDescriptorParser.parse(
        fixture(sspBytes: 2),
        negotiatedSpeed: .superSpeedPlus,
        superSpeedPlusContext: context
      )
    }
    var intervening = fixture()
    intervening.insert(contentsOf: [3, 0x24, 0], at: 31)
    intervening[2] = UInt8(intervening.count)
    #expect(throws: PassiveUSBDescriptorBlobError.invalidCompanionDescriptor) {
      try _ = PassiveUSBConfigurationDescriptorParser.parse(
        intervening,
        negotiatedSpeed: .superSpeedPlus,
        superSpeedPlusContext: context
      )
    }
    var reserved = fixture()
    reserved[30] = 1
    #expect(throws: PassiveUSBDescriptorBlobError.invalidCompanionDescriptor) {
      try _ = PassiveUSBConfigurationDescriptorParser.parse(
        reserved,
        negotiatedSpeed: .superSpeedPlus,
        superSpeedPlusContext: context
      )
    }
  }
  @Test func identicalAliasesParseAndDifferentAliasesAreAmbiguous() throws {
    let bytes: [UInt8] = [9, 2, 9, 0, 0, 1, 0, 0x80, 0x32]
    let root = PassiveUSBRegistryNode(
      serviceClass: "IOUSBHostDevice",
      properties: [
        "Configuration Descriptor": .bytes(bytes), "kUSBConfigurationDescriptor": .bytes(bytes)
      ]
    )
    let same = PassiveUSBRegistryFactParser.parse(
      root: root,
      tuple: PassiveUSBDescriptorTuple(vendorID: 0x3537, productID: 0x1010),
      catalogInference: catalogInference()
    )
    #expect(same.parsedDescriptorFacts.state == .parsed)
    #expect(same.parsedDescriptorFacts.sources.count == 2)
    let different = PassiveUSBRegistryNode(
      serviceClass: "IOUSBHostDevice",
      properties: [
        "Configuration Descriptor": .bytes(bytes),
        "kUSBConfigurationDescriptor": .bytes(bytes + [0])
      ]
    )
    let ambiguous = PassiveUSBRegistryFactParser.parse(
      root: different,
      tuple: PassiveUSBDescriptorTuple(vendorID: 0x3537, productID: 0x1010),
      catalogInference: catalogInference()
    )
    #expect(ambiguous.parsedDescriptorFacts.state == .ambiguous)
    #expect(ambiguous.parsedDescriptorFacts.configuration == nil)
  }
  @Test func boundedBlobAndOwnershipBoundaryCasesAreIndependent() throws {
    #expect(throws: PassiveUSBDescriptorBlobError.unsafeSize) {
      try _ = PassiveUSBConfigurationDescriptorParser.parse([])
    }
    #expect(throws: PassiveUSBDescriptorBlobError.unsafeSize) {
      try _ = PassiveUSBConfigurationDescriptorParser.parse(
        [UInt8](repeating: 0, count: PassiveUSBConfigurationDescriptorParser.maxBlobSize + 1)
      )
    }
    var exactMaximum = [UInt8](repeating: 0x99, count: 65_535)
    exactMaximum[0] = 9
    exactMaximum[1] = 2
    exactMaximum[2] = 0xFF
    exactMaximum[3] = 0xFF
    exactMaximum[4] = 0
    exactMaximum[5] = 1
    exactMaximum[6] = 0
    exactMaximum[7] = 0x80
    exactMaximum[8] = 0x32
    for offset in stride(from: 9, to: 65_535, by: 2) {
      exactMaximum[offset] = 2
      if offset + 1 < exactMaximum.count { exactMaximum[offset + 1] = 0x99 }
    }
    #expect(throws: Never.self) {
      try _ = PassiveUSBConfigurationDescriptorParser.parse(exactMaximum)
    }
    #expect(throws: PassiveUSBDescriptorBlobError.truncated) {
      try _ = PassiveUSBConfigurationDescriptorParser.parse([1])
    }
    let interface: [UInt8] = [9, 4, 0, 0, 0, 0xFF, 0x47, 0xD0, 0]
    let base = [UInt8]([9, 2, 27, 0, 1, 1, 0, 0x80, 0x32])
    #expect(throws: PassiveUSBDescriptorBlobError.duplicateInterfaceOwnership) {
      try _ = PassiveUSBConfigurationDescriptorParser.parse(base + interface + interface)
    }
    #expect(throws: PassiveUSBDescriptorBlobError.impossibleEndpointOwnership) {
      try _ = PassiveUSBConfigurationDescriptorParser.parse([
        9, 2, 23, 0, 1, 1, 0, 0x80, 0x32, 7, 5, 1, 3, 64, 0, 1, 7, 5, 1, 3, 64, 0, 1
      ])
    }
    #expect(throws: PassiveUSBDescriptorBlobError.impossibleEndpointOwnership) {
      try _ = PassiveUSBConfigurationDescriptorParser.parse([
        9, 2, 16, 0, 1, 1, 0, 0x80, 0x32, 7, 5, 1, 3, 64, 0, 1
      ])
    }
  }
  @Test func matchingFailuresRemainTypedAndInterpolated() {
    let source = SpySource(error: .matchingFailed(-536_870_181))
    #expect(throws: PassiveUSBDescriptorProbeError.matchingFailed(-536_870_181)) {
      try PassiveUSBDescriptorProbe.scanWithoutGate(
        authorizedTuple: PassiveUSBDescriptorTuple(vendorID: 0x3537, productID: 0x1010),
        source: source
      )
    }
    #expect(
      PassiveUSBDescriptorProbeError.matchingFailed(-7).errorDescription?.contains("-7") == true
    )
  }
  @Test func speedAliasesAreObservedOrAmbiguousWithoutPromotingUnknownSpeed() {
    let root = fixtureRoot()
    let observed = PassiveUSBRegistryFactParser.parse(
      root: PassiveUSBRegistryNode(
        serviceClass: root.serviceClass,
        properties: root.properties.merging([
          "USBSpeed": .string("high"), "Device Speed": .unsignedInteger(2)
        ]) { _, new in new },
        children: root.children
      ),
      tuple: PassiveUSBDescriptorTuple(vendorID: 0x3537, productID: 0x1010),
      catalogInference: catalogInference()
    )
    #expect(observed.observedUSBFacts.speedObservation.state == .observed)
    #expect(observed.observedUSBFacts.speedObservation.speed == .high)
    let ambiguous = PassiveUSBRegistryFactParser.parse(
      root: PassiveUSBRegistryNode(
        serviceClass: root.serviceClass,
        properties: root.properties.merging([
          "USBSpeed": .string("high"), "Device Speed": .string("full")
        ]) { _, new in new },
        children: root.children
      ),
      tuple: PassiveUSBDescriptorTuple(vendorID: 0x3537, productID: 0x1010),
      catalogInference: catalogInference()
    )
    #expect(ambiguous.observedUSBFacts.speedObservation.state == .ambiguous)
    #expect(ambiguous.parsedDescriptorFacts.state == .parsed)
  }
  private func fixtureRoot(children: [PassiveUSBRegistryNode]? = nil) -> PassiveUSBRegistryNode {
    let interface = interface(number: 0, alternate: 0, endpoint: 0)
    return PassiveUSBRegistryNode(
      serviceClass: "IOUSBHostDevice",
      properties: [
        "USB Product Name": .string("GameSir-G7 SE Controller for Xbox"),
        "bDeviceClass": .unsignedInteger(0xFF), "bDeviceSubClass": .unsignedInteger(0xFF),
        "bDeviceProtocol": .unsignedInteger(0xFF), "bNumConfigurations": .unsignedInteger(1),
        "kUSBCurrentConfiguration": .unsignedInteger(0),
        "Configuration Descriptor": .bytes([
          9, 2, 0x19, 0, 1, 1, 0, 0x80, 0x32, 9, 4, 0, 0, 1, 0xFF, 0x47, 0xD0, 0, 7, 5, 1, 3, 0, 0,
          1
        ])
      ],
      children: children ?? [interface]
    )
  }
  private func interface(number: UInt8, alternate: UInt8, endpoint: UInt8) -> PassiveUSBRegistryNode
  {
    let endpoint = PassiveUSBRegistryNode(
      serviceClass: "IOUSBHostPipe",
      properties: [
        "bEndpointAddress": .unsignedInteger(UInt64(endpoint)),
        "wMaxPacketSize": .unsignedInteger(0), "bInterval": .unsignedInteger(0),
        "transferType": .string("interrupt")
      ]
    )
    return PassiveUSBRegistryNode(
      serviceClass: "IOUSBHostInterface",
      properties: [
        "bInterfaceNumber": .unsignedInteger(UInt64(number)),
        "bAlternateSetting": .unsignedInteger(UInt64(alternate)),
        "bInterfaceClass": .unsignedInteger(0xFF), "bInterfaceSubClass": .unsignedInteger(0x47),
        "bInterfaceProtocol": .unsignedInteger(0xD0)
      ],
      children: [endpoint]
    )
  }
  private func catalogInference() -> PassiveUSBCatalogInference {
    PassiveUSBCatalogInference(
      source: "OpenJoystickDriver catalog",
      record: "3537:1010",
      parser: "catalog-backed; not observed from descriptors",
      endpoints: ["input": 0x81]
    )
  }
  private func noSensitiveKeys(_ value: Any) -> Bool {
    if let dictionary = value as? [String: Any] {
      return dictionary.allSatisfy { key, child in
        !["serviceID", "locationID", "serialNumber", "uuid", "registryEntryID"].contains(key)
          && noSensitiveKeys(child)
      }
    }
    if let array = value as? [Any] { return array.allSatisfy(noSensitiveKeys) }
    return true
  }
}
private final class SpySource: PassiveUSBRegistrySource, @unchecked Sendable {
  struct Call: Equatable {
    let className: String
    let properties: [String: UInt64]
  }
  var matches: [PassiveUSBRegistryNode]
  var error: PassiveUSBDescriptorProbeError?
  var calls: [Call] = []
  init(matches: [PassiveUSBRegistryNode] = [], error: PassiveUSBDescriptorProbeError? = nil) {
    self.matches = matches
    self.error = error
  }
  func matchingServices(className: String, numericProperties: [String: UInt64]) throws
    -> [PassiveUSBRegistryNode]
  {
    calls.append(Call(className: className, properties: numericProperties))
    if let error { throw error }
    return matches
  }
}
