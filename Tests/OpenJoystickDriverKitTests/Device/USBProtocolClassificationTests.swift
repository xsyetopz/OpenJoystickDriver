import Testing

@testable import OpenJoystickDriverKit

struct USBProtocolClassificationTests {
  @Test func xusbCandidateRequiresTheAuthoritativeInterfaceAndPair() {
    let result = USBProtocolClassifier.classify(
      observation(
        interfaceClass: 0xFF,
        subclass: 0x5D,
        protocol: 0x01,
        endpoints: [endpoint(0x91, .in), endpoint(0x07, .out)]
      )
    )

    #expect(result.selected == .xusb)
    #expect(result.disposition == .advisory)
    #expect(result.matchedPredicates.contains(.xusbInterfaceIdentity))
    #expect(result.matchedPredicates.contains(.completeInterruptPair))
  }

  @Test func endpointAddressesDoNotAffectXUSBClassification() {
    let first = USBProtocolClassifier.classify(
      observation(
        interfaceClass: 0xFF,
        subclass: 0x5D,
        protocol: 0x01,
        endpoints: [endpoint(0x81, .in), endpoint(0x01, .out)]
      )
    )
    let second = USBProtocolClassifier.classify(
      observation(
        interfaceClass: 0xFF,
        subclass: 0x5D,
        protocol: 0x01,
        endpoints: [endpoint(0xE7, .in), endpoint(0x2A, .out)]
      )
    )

    #expect(first.selected == second.selected)
    #expect(first.matchedPredicates == second.matchedPredicates)
  }

  @Test func gipCandidateIsAdvisoryAndNeverAnAdmissionDecision() {
    let result = USBProtocolClassifier.classify(
      observation(
        interfaceClass: 0xFF,
        subclass: 0x47,
        protocol: 0xD0,
        endpoints: [endpoint(0x81, .in), endpoint(0x02, .out)]
      )
    )

    #expect(result.selected == .gip)
    #expect(result.disposition == .advisory)
  }

  @Test func simultaneousXUSBAndGIPSignaturesAreAnExplicitAmbiguousConflict() {
    let result = USBProtocolClassifier.classify(
      ControllerTransportObservation(
        vendorID: 1,
        productID: 2,
        interfaces: [
          USBInterfaceTransportFacts(
            interfaceNumber: 0,
            interfaceClass: 0xFF,
            interfaceSubclass: 0x5D,
            interfaceProtocol: 0x01,
            endpoints: [endpoint(0x81, .in), endpoint(0x01, .out)]
          ),
          USBInterfaceTransportFacts(
            interfaceNumber: 0,
            interfaceClass: 0xFF,
            interfaceSubclass: 0x47,
            interfaceProtocol: 0xD0,
            endpoints: [endpoint(0x82, .in), endpoint(0x02, .out)]
          )
        ]
      )
    )

    #expect(result.selected == nil)
    #expect(result.disposition == .ambiguous)
    #expect(result.conflictingCandidates == [.xusb, .gip])
  }

  @Test func arbitraryVendorInterfaceIsRejected() {
    let result = USBProtocolClassifier.classify(
      observation(
        interfaceClass: 0xFF,
        subclass: 0x12,
        protocol: 0x34,
        endpoints: [endpoint(0x81, .in), endpoint(0x01, .out)]
      )
    )

    #expect(result.selected == nil)
    #expect(result.disposition == .unsupported)
  }

  @Test func genericHIDRequiresActualLayoutEvidence() {
    let noLayout = USBProtocolClassifier.classify(observation(interfaceClass: 0x03))
    let layout = USBProtocolClassifier.classify(
      observation(
        interfaceClass: 0x03,
        hidLayout: HIDLayoutSummary(hasGamePadOrJoystickCollection: true, hasUsableElements: true)
      )
    )

    #expect(noLayout.selected == nil)
    #expect(layout.selected == .genericHID)
  }

  @Test func conflictDoesNotSwitchKnownRecordVariant() {
    let result = KnownRecordProtocolReconciler.reconcile(
      observation: observation(
        interfaceClass: 0xFF,
        subclass: 0x5D,
        protocol: 0x01,
        endpoints: [endpoint(0x81, .in), endpoint(0x01, .out)]
      ),
      profile: profile(variant: .xboxOne)
    )

    #expect(result.knownVariant == .xboxOne)
    #expect(result.hasConflict)
  }

  @Test func originalXboxVariantDoesNotClaimXUSBWithoutAnAuthoritativeMapping() {
    let result = KnownRecordProtocolReconciler.reconcile(
      observation: observation(
        interfaceClass: 0xFF,
        subclass: 0x5D,
        protocol: 0x01,
        endpoints: [endpoint(0x81, .in), endpoint(0x01, .out)]
      ),
      profile: profile(variant: .xboxOriginal)
    )

    #expect(result.knownVariant == .xboxOriginal)
    #expect(!result.hasConflict)
    #expect(result.matchingPredicates.isEmpty)
  }

  @Test func exactCatalogAdmissionSetRemainsCatalogOwned() {
    let registry = ParserRegistry()
    let known = DeviceIdentifier(vendorID: 0x045E, productID: 0x028E)
    let unknown = DeviceIdentifier(vendorID: 0xFFFF, productID: 0x0001)

    #expect(registry.rawUSBProfileIdentifiers().contains(known))
    #expect(!registry.rawUSBProfileIdentifiers().contains(unknown))
  }

  private func observation(
    interfaceNumber: UInt8 = 0,
    alternateSetting: UInt8 = 0,
    interfaceClass: UInt8,
    subclass: UInt8? = nil,
    protocol: UInt8? = nil,
    endpoints: [USBEndpointTransportFacts] = [],
    hidLayout: HIDLayoutSummary? = nil
  ) -> ControllerTransportObservation {
    ControllerTransportObservation(
      vendorID: 1,
      productID: 2,
      interfaces: [
        USBInterfaceTransportFacts(
          interfaceNumber: interfaceNumber,
          alternateSetting: alternateSetting,
          interfaceClass: interfaceClass,
          interfaceSubclass: subclass,
          interfaceProtocol: `protocol`,
          endpoints: endpoints
        )
      ],
      hidLayout: hidLayout
    )
  }

  private func endpoint(_ address: UInt8, _ direction: USBEndpointDirection)
    -> USBEndpointTransportFacts
  {
    USBEndpointTransportFacts(
      address: address,
      transferType: .interrupt,
      direction: direction,
      maxPacketSize: 64,
      interval: 1
    )
  }

  private func profile(variant: ControllerProtocolVariant) -> DeviceRuntimeProfile {
    DeviceRuntimeProfile(
      parserName: "test",
      virtualProfile: .default,
      transportProfile: .gipDefault,
      protocolVariant: variant,
      quirks: [],
      mappingOptions: [],
      preferredBackends: [.userSpaceHID],
      gipStartupPackets: [],
      gipKeepAlivePolicy: .disabled
    )
  }
}
