import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverPresentation

struct ControllerDetailFactsTests {
  private func device(
    power: ControllerConnectionState.Power? = nil,
    wiiRemote: WiiRemoteStatus? = nil,
    ownership: ControllerOwnershipObservation = .unknown,
    override: VirtualHIDProfileID? = nil,
    publication: ApplicationServicePublicationStatus? = nil,
    output: PhysicalControllerOutputCapabilities = .none,
    motion: Bool = false,
    binding: ProtocolBindingID = ProtocolBindingID(.hidDescriptor)
  ) -> ApplicationServiceDeviceDescription {
    var device = ApplicationServiceDeviceDescription(
      name: "Test Pad",
      vendorID: 0x1234,
      productID: 0x5678,
      protocolBinding: binding,
      connection: "USB",
      discoverySource: .rawUSB,
      physicalOwnership: ownership,
      serialNumber: nil,
      bindingResult: .hidDescriptorFixture,
      physicalOutputCapabilities: output,
      recordServer: .system,
      recordAccessRoute: .system,
      capabilities: ControllerCapabilities(controls: [], motion: motion),
      connectionState: (power ?? (wiiRemote == nil ? nil : .unknown)).map {
        ControllerConnectionState(
          transport: nil,
          backend: .hid,
          isConnected: true,
          power: $0,
          wiiRemote: wiiRemote
        )
      },
      sessionToken: .fixture("facts-device")
    )
    device.virtualHIDProfile = override.map {
      ApplicationServiceVirtualHIDProfileStatus(
        profile: $0,
        source: .override,
        override: $0,
        unavailable: false
      )
    }
    device.publication = publication
    return device
  }

  private static func value(
    _ kind: ControllerFact.Kind,
    in facts: [ControllerFact]
  ) -> OJDValue? {
    facts.first { $0.kind == kind }?.value
  }

  @Test
  func unknownBatteryChargingAndCableAreHidden() {
    let kinds = ControllerDetailFacts.general(for: device(power: .unknown)).map(\.kind)
    #expect(
      kinds == [.publication, .serving, .serialNumber, .inputHealth]
    )
    #expect(ControllerDetailFacts.general(for: device()).map(\.kind) == kinds)
  }

  @Test
  func appSelectedProfileFactShownByItsName() {
    var selected = device()
    selected.profileInForce = ApplicationServiceProfileInForce(
      name: "Racing",
      appID: "com.example.Racer"
    )
    var everywhere = device()
    everywhere.profileInForce = ApplicationServiceProfileInForce(name: "Everywhere", appID: nil)

    let facts = ControllerDetailFacts.general(for: selected) { _ in "Racer" }

    #expect(Self.value(.profileSelectedBy, in: facts) == .text("Racer"))
    #expect(facts.first?.kind == .profileSelectedBy)
    #expect(Self.value(.profileSelectedBy, in: ControllerDetailFacts.general(for: device())) == nil)
    #expect(
      Self.value(.profileSelectedBy, in: ControllerDetailFacts.general(for: everywhere)) == nil
    )
  }

  @Test
  func aWiiRemoteListsItsModeExtensionAndMotionPlus() {
    let status = WiiRemoteStatus(
      reportMode: 0x35,
      extensionKind: .motionPlusClassic,
      unknownExtensionID: nil,
      motionPlusActive: true,
      isGyroRestReady: false
    )
    let facts = ControllerDetailFacts.general(for: device(wiiRemote: status))
    #expect(
      facts.map(\.kind).suffix(3) == [.wiiReportMode, .wiiExtension, .wiiMotionPlus]
    )
    #expect(Self.value(.wiiReportMode, in: facts) == .text("0x35"))
    #expect(Self.value(.wiiExtension, in: facts) == .text(status.extensionText()))
    #expect(
      !ControllerDetailFacts.general(for: device()).map(\.kind).contains(.wiiReportMode)
    )
  }

  @Test
  func reportedPowerFactsAreListed() {
    let power = ControllerConnectionState.Power(
      charging: .charging,
      battery: BatteryLevel(percentage: 80...80),
      wiredPower: true
    )
    let facts = ControllerDetailFacts.general(for: device(power: power))
    #expect(facts.map(\.kind).suffix(2) == [.battery, .chargingState])
    #expect(Self.value(.battery, in: facts) == .text("80%"))
  }

  @Test
  func cableShowsOnlyWhileChargingStateUnknown() {
    let cabled = ControllerConnectionState.Power(
      charging: .unknown,
      battery: BatteryLevel(percentage: 80...80),
      wiredPower: true
    )
    let kinds = ControllerDetailFacts.general(for: device(power: cabled)).map(\.kind)
    #expect(kinds.contains(.cableState))
    #expect(!kinds.contains(.chargingState))
  }

  @Test
  func publicationOmitsWaitForInputInputRowSays() {
    let waiting = ApplicationServicePublicationStatus.notPublished(.noInputYet)
    #expect(
      ControllerDetailFacts.publicationText(waiting, omittingNoInputYet: true)
        == OJDLocalized.string("ui.controllers.publication.notPublished")
    )
  }

  @Test
  func capabilitiesTheControllerLacksAreHidden() {
    let none = ControllerDetailFacts.general(for: device()).map(\.kind)
    #expect(!none.contains(.rumble) && !none.contains(.lighting) && !none.contains(.motion))
    #expect(!none.contains(.adaptiveTriggers) && !none.contains(.touchContacts))

    let facts = ControllerDetailFacts.general(
      for: device(
        output: PhysicalControllerOutputCapabilities(
          rumbleMotors: [.lowFrequency, .highFrequency],
          lightingFeatures: [.programmableColor],
          adaptiveTriggers: [.left]
        ),
        motion: true
      )
    )
    #expect(Self.value(.rumble, in: facts) == .text("Left main, Right main"))
    #expect(Self.value(.lighting, in: facts) == .text("Color"))
    #expect(Self.value(.adaptiveTriggers, in: facts) == .text("Left trigger"))
    #expect(Self.value(.motion, in: facts) == .text("Available"))
  }

  @Test
  func parserFactSpellsBindingAsOJDDoes() {
    let binding = ProtocolBindingID(.xboxXUSB, variant: .receiver)
    let facts = ControllerDetailFacts.advanced(for: device(binding: binding), record: nil)
    #expect(
      Self.value(.parser, in: facts)
        == .text(ControllerDetailFacts.withIdentifier(binding.displayName, "xbox-xusb:receiver"))
    )
  }

  @Test
  func advancedRowsSayWordsAndKeepRawIdentifierBesideThem() throws {
    #expect(ControllerDetailFacts.controlText(.dpadUp) == "D-pad up (DpadUp)")
    #expect(ControllerDetailFacts.controlText(.leftStickX) == "Left stick horizontal (LeftStickX)")
    #expect(
      ControllerDetailFacts.controlText(.pointerTracking) == "Pointer tracking (PointerTracking)"
    )
    let facts = ControllerDetailFacts.advanced(for: device(), record: nil)
    let mapping = try #require(device().bindingResult.inputMapping)
    #expect(
      Self.value(.inputMapping, in: facts)
        == .text(
          ControllerDetailFacts.withIdentifier(
            mapping.rowText(localize: OJDLocalized.string),
            mapping.source.rawValue
          )
        )
    )
    #expect(ControllerDetailFacts.matchTierText(.exactGUID) == "exact GUID")
  }

  @Test
  func everyControlHasWordsAndItsRawNameOnlyBesideThem() {
    for control in Control.allCases {
      let words = ControllerDetailFacts.controlName(control)
      #expect(!words.isEmpty && !words.contains("ui."), "\(control.rawValue)")
      // A word that is the raw name itself (`Start`) shows once; otherwise the raw name follows.
      #expect(
        ControllerDetailFacts.controlText(control)
          == (words == control.rawValue ? words : "\(words) (\(control.rawValue))"),
        "\(control.rawValue)"
      )
    }
  }

  @Test
  func everyParserHasWordsAndItsOJDSpellingOnlyBesideThem() {
    for family in PhysicalProtocolID.allCases {
      let bindings =
        family.variants.isEmpty
        ? [ProtocolBindingID(family)]
        : family.variants.map { ProtocolBindingID(family, variant: $0) }
      for binding in bindings {
        let facts = ControllerDetailFacts.advanced(for: device(binding: binding), record: nil)
        let name = binding.commandLineName
        #expect(!binding.displayName.isEmpty && binding.displayName != name, "\(name)")
        #expect(
          Self.value(.parser, in: facts)
            == .text(ControllerDetailFacts.withIdentifier(binding.displayName, name)),
          "\(name)"
        )
      }
    }
  }

  @Test
  func everyInputMappingSourceHasWordsAndItsRawNameOnlyBesideThem() throws {
    let sources: [InputMapping.Source] = [
      .record, .sdlGameControllerDB, .standardHIDUsageMap, .none,
    ]
    for source in sources {
      let json = """
        {"source":"\(source.rawValue)","unmapped":[]\
        \(source == .sdlGameControllerDB ? ",\"match\":\"ExactGUID\"" : "")}
        """
      let mapping = try JSONDecoder().decode(InputMapping.self, from: Data(json.utf8))
      let text = ControllerDetailFacts.inputMappingText(mapping)
      #expect(text.hasSuffix(" (\(source.rawValue))"), "\(source.rawValue)")
      #expect(text != " (\(source.rawValue))", "\(source.rawValue)")
    }
    for tier in SDLMatchTier.allCases {
      let words = ControllerDetailFacts.matchTierText(tier)
      #expect(!words.isEmpty && words != tier.rawValue && !words.contains("ui."))
    }
  }

  @Test
  func recordSourceWordsNotIdentifier() {
    #expect(ControllerDetailFacts.recordText(nil) == "none (no record matches)")
  }

  @Test
  func missingSerialNumberShowsNone() {
    let facts = ControllerDetailFacts.general(for: device())
    #expect(Self.value(.serialNumber, in: facts) == OJDValue.none)
  }

  @Test
  func theSelectedProfileShowsWhetherOrNotItIsPublished() {
    let published = ApplicationServicePublicationStatus.published(target: .sdlCompatible)
    let notPublished = ApplicationServicePublicationStatus.notPublished(
      .noInputYet,
      target: .sdlCompatible
    )
    let failed = ApplicationServicePublicationStatus.failed("send failed", target: .sdlCompatible)
    let reason = OJDLocalized.string("ui.controllers.publication.reason.noInputYet")
    let failure = OJDLocalized.formatted("ui.controllers.publication.failedSend", "send failed")
    let withReason = { (state: String, detail: String) in
      OJDLocalized.formatted("ui.controllers.publication.withReason", state, detail)
    }
    for (publication, text) in [
      (published, OJDLocalized.string("ui.controllers.publication.published")),
      (
        notPublished,
        withReason(OJDLocalized.string("ui.controllers.publication.notPublished"), reason)
      ),
      (failed, withReason(OJDLocalized.string("ui.controllers.publication.failed"), failure)),
    ] {
      let facts = ControllerDetailFacts.general(
        for: device(override: .sdlCompatible, publication: publication)
      )
      #expect(Self.value(.publication, in: facts) == .text(text))
    }
    let unreported = ControllerDetailFacts.general(for: device(override: .sdlCompatible))
    #expect(Self.value(.publication, in: unreported) == OJDValue.none)
  }

  @Test
  func theProfileIsPublishedOnlyInThePicker() {
    let facts = ControllerDetailFacts.general(for: device(override: .sdlCompatible))
    #expect(!facts.map(\.label).contains(OJDLocalized.string("cli.controller.show.labelPersona")))
  }

  @Test
  func theAutomaticChoiceNamesTheProfileTheServiceSelected() {
    var pad = device()
    pad.virtualHIDProfile = ApplicationServiceVirtualHIDProfileStatus(
      profile: .generic,
      source: .automatic,
      override: nil,
      unavailable: false
    )
    #expect(
      ControllerDetailFacts.automaticProfileLabel(pad)
        == "Automatic (\(VirtualHIDProfileID.generic.identity.productName))"
    )
  }

  @Test
  func theAutomaticChoiceIsPlainWithAnOverrideOrWithoutASelection() {
    #expect(ControllerDetailFacts.automaticProfileLabel(device(override: .generic)) == "Automatic")
    #expect(
      ControllerDetailFacts.automaticProfileLabel(device(ownership: .systemGamepad)) == "Automatic"
    )
  }

  @Test
  func identifiersEndpointsAndOwnershipAreAdvanced() {
    let facts = ControllerDetailFacts.advanced(for: device(), record: nil)
    #expect(Self.value(.usbIdentifier, in: facts) == .text("1234:5678"))
    #expect(Self.value(.inputEndpoint, in: facts) == OJDValue.none)
    #expect(Self.value(.unitID, in: facts) == OJDValue.none)
    #expect(
      Self.value(.parser, in: facts)
        == .text(
          ControllerDetailFacts.withIdentifier(
            ProtocolBindingID(.hidDescriptor).displayName,
            "hid-descriptor"
          )
        )
    )
    #expect(facts.first { $0.kind == .parser }?.label == OJDLocalized.string("term.parser"))
    #expect(
      Self.value(.ownership, in: facts)
        == .text(
          OJDLocalized.formatted(
            "ui.controllers.ownership.value",
            OJDLocalized.string("ui.controllers.discovery.rawUSB"),
            OJDLocalized.string("ui.controllers.physicalOwnership.unknown"),
            OJDLocalized.string("ui.controllers.hidInputOwnership.unknown")
          )
        )
    )
    #expect(
      Self.value(.duplicateExposureRisk, in: facts)
        == .text(OJDLocalized.string("ui.controllers.physicalOwnership.unknown"))
    )
    #expect(Self.value(.record, in: facts) == .text("none (no record matches)"))
  }

  @Test
  func advancedFactsThatDoNotApplyAreHidden() {
    let kinds = ControllerDetailFacts.advanced(for: device(), record: nil).map(\.kind)
    #expect(!kinds.contains(.startupStatus))
    #expect(!kinds.contains(.inputRecoveries))
    #expect(!kinds.contains(.publicationAttempted))
  }

  @Test
  func inputHealthNamesTheStateAndItsFailure() {
    let facts = ControllerDetailFacts.general(for: device())
    #expect(
      Self.value(.inputHealth, in: facts)
        == .text(OJDLocalized.string("ui.controllers.inputHealth.healthy"))
    )
  }

  @Test
  func aControllerWaitingForItsGuidePressSaysToPressIt() {
    let waiting = ApplicationServiceDeviceDescription.fixture(
      id: "pad-1",
      inputHealth: ControllerInputHealth(state: .stale, failureReason: .guideNotPressed)
    )
    let value = Self.value(.inputHealth, in: ControllerDetailFacts.general(for: waiting))
    #expect(value == .text("Stale (Press the PS or home button)"))
  }

  @Test
  func everyStateTheDetailNamesHasEnglishText() {
    var keys: [String] = []
    keys += ControllerOwnershipObservation.allCases.map(ControllerDetailLabels.physicalOwnershipKey)
    keys += [
      HIDInputOwnership.unknown, .exclusive, .shared, .accessDenied, .ownedByAnotherClient,
      .acquisitionFailed,
    ]
    .map(ControllerDetailLabels.hidInputOwnershipKey)
    keys += [DeviceDiscoverySource.hid, .rawUSB].map(ControllerDetailLabels.discoveryKey)
    keys += ControllerInputHealthFailureReason.allCases
      .map(ControllerDetailLabels.inputHealthReasonKey)
    keys += [
      "ui.controllers.publication.withReason",
      "ui.controllers.inputHealth.withReason",
    ]
    for key in keys { #expect(OJDLocalized.string(key) != key, "\(key)") }
    for reason in ApplicationServicePublicationStatus.NotPublishedReason.allCases {
      let key = ControllerDetailLabels.notPublishedReasonKey(reason)
      #expect(OJDLocalized.string(key) != key, "\(key)")
    }
  }

  @Test
  func closingAWirelessLinkAsksForConfirmationNamingTheController() {
    let confirmation = WirelessDisconnectConfirmation(controllerName: "Pad A")
    #expect(confirmation.title != "ui.controllers.disconnectWirelessConfirmTitle")
    #expect(confirmation.message.contains("Pad A"))
    #expect(confirmation.confirmTitle != "ui.controllers.disconnectWirelessConfirm")
    #expect(!confirmation.confirmTitle.isEmpty)
  }

  @Test
  func aWirelessDisconnectRequestKeepsTheControllerItWasMadeFor() {
    let target = device()
    let request = WirelessDisconnectRequest(device: target)
    #expect(request.device.sessionToken == target.sessionToken)
    #expect(request.id == target.sessionToken.rawValue)
    #expect(request.confirmation == WirelessDisconnectConfirmation(controllerName: target.name))
  }

  @Test
  func everyWirelessDisconnectFailureHasLocalizedText() {
    for failure in [
      WirelessControllerDisconnectFailure.notFound, .notBluetooth, .bluetoothLEUnsupported,
      .missingAddress, .disconnectFailed, .timedOut,
    ] {
      let text = ControllerDetailLabels.wirelessDisconnectFailureText(failure)
      #expect(!text.contains("ui.controllers.disconnectWireless"))
      #expect(!text.contains(failure.rawValue))
    }
  }

  @Test
  func theDuplicateExposureRiskIsNamedForEveryCase() {
    #expect(
      ControllerDetailFacts.duplicateExposureText(.none) == OJDLocalized.string("status.none")
    )
    for risk in [DuplicateExposureRisk.systemHIDVisible, .upstreamVirtualDevice, .unknownOwnership]
    {
      #expect(!ControllerDetailFacts.duplicateExposureText(risk).contains("ui.controllers."))
    }
  }
}

extension ControllerDetailFactsTests {
  @Test
  func tuningRowsListOnlyValuesALayerSets() throws {
    let model = ControllerModelID(vendorID: 0x045E, productID: 0x02FD)
    let record = try #require(ControllerRecordSet.bundled.records[model])
    let rows = ControllerTuningRows.rows(for: record, activeProfile: nil)
    let set = record.tuningValues.filter { $0.key != .stickDeadzone && $0.value != nil }
    #expect(rows.map(\.name) == set.map(\.key.rawValue))
    for (row, entry) in zip(rows, set) {
      #expect(row.layer == CommandLineName.kebab(entry.layer.rawValue))
      #expect(row.text == "\(row.value) (\(row.layer))")
    }
  }

  @Test
  func theServerSourceNamesTheLayerAsTheLibraryDoes() throws {
    let model = ControllerModelID(vendorID: 0x045E, productID: 0x02FD)
    let record = try #require(ControllerRecordSet.bundled.records[model])
    let layer = record.fieldLayers["server"] ?? .driver
    #expect(ControllerDetailFacts.serverSourceText(record) == layer.libraryTitle)
    #expect(!ControllerDetailFacts.serverSourceText(record).contains("ui."))
  }

  @Test
  func publicationAndInputHealthShowLocalizedWords() {
    #expect(
      ControllerDetailFacts.publicationText(ApplicationServicePublicationStatus.published())
        == OJDLocalized.string("ui.controllers.publication.published")
    )
    #expect(
      ControllerDetailFacts.publicationText(
        ApplicationServicePublicationStatus.notPublished(.noInputYet)
      )
        == OJDLocalized.formatted(
          "ui.controllers.publication.withReason",
          OJDLocalized.string("ui.controllers.publication.notPublished"),
          OJDLocalized.string("ui.controllers.publication.reason.noInputYet")
        )
    )
    #expect(
      ControllerDetailFacts.inputHealthText(device())
        == OJDLocalized.string("ui.controllers.inputHealth.healthy")
    )
  }
}
