import Testing

@testable import OpenJoystickDriverKit

struct DeviceTransportProfileTests {
  @Test func testGamesirG7SETransportProfile() {
    let registry = ParserRegistry()
    let identifier = DeviceIdentifier(vendorID: 13623, productID: 4112)

    let profile = registry.transportProfile(for: identifier)

    #expect(profile.inputEndpoint == 0x82)
    #expect(profile.outputEndpoint == 0x02)
    #expect(!profile.needsSetConfiguration)
    #expect(profile.postHandshakeSettleNanoseconds == 0)
  }
  @Test func testGamesirG7SERuntimeProfile() {
    let registry = ParserRegistry()
    let identifier = DeviceIdentifier(vendorID: 13623, productID: 4112)

    let profile = registry.runtimeProfile(for: identifier)

    #expect(profile.parserName == "GIP")
    #expect(profile.protocolVariant == .xboxOne)
    #expect(profile.mappingFlags == ["shareButton"])
    #expect(profile.mappingOptions.contains(.shareButton))
  }
  @Test func testRuntimeProfileCarriesHardwareVerificationProvenance() {
    let registry = ParserRegistry()
    let verified = registry.runtimeProfile(for: DeviceIdentifier(vendorID: 13623, productID: 4112))
    let sourceBacked = registry.runtimeProfile(
      for: DeviceIdentifier(vendorID: 1356, productID: 3302)
    )
    let unknown = registry.runtimeProfile(for: DeviceIdentifier(vendorID: 65535, productID: 65535))

    #expect(verified.hardwareVerified)
    #expect(!sourceBacked.hardwareVerified)
    #expect(!unknown.hardwareVerified)
  }

  @Test func testRazerWolverineV3TournamentEditionProfile() {
    let registry = ParserRegistry()
    let identifier = DeviceIdentifier(vendorID: 5_426, productID: 2_627)

    let runtime = registry.runtimeProfile(for: identifier)
    let transport = registry.transportProfile(for: identifier)

    #expect(runtime.parserName == "GIP")
    #expect(runtime.protocolVariant == .xboxOne)
    #expect(runtime.mappingFlags == ["shareButton", "paddles"])
    #expect(!runtime.hardwareVerified)
    #expect(transport.inputEndpoint == 0x82)
    #expect(transport.outputEndpoint == 0x02)
    #expect(!transport.needsSetConfiguration)
  }

  @Test func testRazerWolverineV2ProfileUsesCapturedEndpointsOnly() {
    let registry = ParserRegistry()
    let identifier = DeviceIdentifier(vendorID: 5_426, productID: 2_601)

    let runtime = registry.runtimeProfile(for: identifier)
    let transport = registry.transportProfile(for: identifier)

    #expect(runtime.parserName == "GIP")
    #expect(runtime.protocolVariant == .xboxOne)
    #expect(runtime.mappingFlags.isEmpty)
    #expect(!runtime.hardwareVerified)
    #expect(runtime.gipStartupPackets == GIPStartupPacket.defaultSequence)
    #expect(transport.inputEndpoint == 0x81)
    #expect(transport.outputEndpoint == 0x01)
    #expect(transport.hasEndpointOverride)
    #expect(!transport.needsSetConfiguration)
    #expect(transport.postHandshakeSettleNanoseconds == 0)
  }

  @Test func testMicrosoftXboxOneController1537UsesImportedDefaults() {
    let registry = ParserRegistry()
    let identifier = DeviceIdentifier(vendorID: 1_118, productID: 721)

    let runtime = registry.runtimeProfile(for: identifier)
    let transport = registry.transportProfile(for: identifier)

    #expect(runtime.parserName == "GIP")
    #expect(runtime.protocolVariant == .xboxOne)
    #expect(runtime.mappingFlags.isEmpty)
    #expect(!runtime.hardwareVerified)
    #expect(runtime.gipStartupPackets == GIPStartupPacket.defaultSequence)
    #expect(!runtime.gipStartupPackets.contains(.xboxOneSInit))
    #expect(transport.inputEndpoint == 0x82)
    #expect(transport.outputEndpoint == 0x02)
    #expect(!transport.hasEndpointOverride)
  }

  @Test func testVader5STransportProfile() {
    let registry = ParserRegistry()
    let identifier = DeviceIdentifier(vendorID: 14295, productID: 10241)

    let profile = registry.transportProfile(for: identifier)

    #expect(profile.inputEndpoint == 0x81)
    #expect(profile.outputEndpoint == 0x01)
    #expect(profile.needsSetConfiguration)
    #expect(profile.postHandshakeSettleNanoseconds == 200_000_000)
  }

  @Test func testDS3ExperimentalProfile() {
    let registry = ParserRegistry()
    let identifier = DeviceIdentifier(vendorID: 1356, productID: 616)
    let profile = registry.runtimeProfile(for: identifier)

    #expect(registry.parserName(for: identifier) == "DS3")
    #expect(profile.protocolVariant == .dualShock3)
    #expect(profile.mappingFlags == ["experimental", "needsHardwareTest"])
    #expect(registry.transportProfile(for: identifier).inputEndpoint == 0x82)
    #expect(registry.transportProfile(for: identifier).outputEndpoint == 0x02)
  }

  @Test func testDualSenseExperimentalProfiles() {
    let registry = ParserRegistry()
    let identifiers = [
      DeviceIdentifier(vendorID: 1356, productID: 3302),
      DeviceIdentifier(vendorID: 1356, productID: 3570),
    ]

    for identifier in identifiers {
      let profile = registry.runtimeProfile(for: identifier)
      #expect(registry.parserName(for: identifier) == "DualSense")
      #expect(profile.protocolVariant == .dualSense)
      #expect(
        profile.mappingFlags == ["touchpad", "microphoneMute", "experimental", "needsHardwareTest"]
      )
      #expect(registry.transportProfile(for: identifier).inputEndpoint == 0x82)
      #expect(registry.transportProfile(for: identifier).outputEndpoint == 0x02)
    }
  }

  @Test func testSteamControllerExperimentalProfiles() {
    let registry = ParserRegistry()
    let identifiers = [
      DeviceIdentifier(vendorID: 10462, productID: 4354),
      DeviceIdentifier(vendorID: 10462, productID: 4418),
    ]

    let wired = registry.runtimeProfile(for: identifiers[0])
    #expect(registry.parserName(for: identifiers[0]) == "SteamController")
    #expect(wired.protocolVariant == .steamController)
    #expect(wired.mappingFlags == ["lizardMode", "trackpads", "experimental", "needsHardwareTest"])

    let wireless = registry.runtimeProfile(for: identifiers[1])
    #expect(registry.parserName(for: identifiers[1]) == "SteamController")
    #expect(wireless.protocolVariant == .steamController)
    #expect(
      wireless.mappingFlags == [
        "lizardMode", "trackpads", "wirelessReceiver", "experimental", "needsHardwareTest",
      ]
    )

    for identifier in identifiers {
      #expect(registry.transportProfile(for: identifier).inputEndpoint == 0x82)
      #expect(registry.transportProfile(for: identifier).outputEndpoint == 0x02)
    }
  }

  @Test func testSwitchProExperimentalProfile() {
    let registry = ParserRegistry()
    let identifier = DeviceIdentifier(vendorID: 1406, productID: 8201)
    let profile = registry.runtimeProfile(for: identifier)

    #expect(registry.parserName(for: identifier) == "SwitchPro")
    #expect(profile.protocolVariant == .switchPro)
    #expect(profile.mappingFlags == ["usbHandshake", "experimental", "needsHardwareTest"])
    #expect(registry.transportProfile(for: identifier).inputEndpoint == 0x82)
    #expect(registry.transportProfile(for: identifier).outputEndpoint == 0x02)
  }

  @Test func testXbox360WirelessReceiverProfiles() {
    let registry = ParserRegistry()
    let identifiers = [
      DeviceIdentifier(vendorID: 1_118, productID: 657),
      DeviceIdentifier(vendorID: 1_118, productID: 681),
      DeviceIdentifier(vendorID: 1_118, productID: 1_817),
    ]

    for identifier in identifiers {
      let runtime = registry.runtimeProfile(for: identifier)
      let transport = registry.transportProfile(for: identifier)
      let parser = registry.parser(for: identifier)

      #expect(runtime.parserName == "Xbox360")
      #expect(runtime.protocolVariant == .xbox360Wireless)
      #expect(runtime.mappingFlags == ["dpadToButtons"])
      #expect(!runtime.hardwareVerified)
      #expect(transport.inputEndpoint == 0x81)
      #expect(transport.outputEndpoint == 0x01)
      #expect(
        (parser as? any ControllerInputConnectionLifecycle)?.requiresInputConnectionBeforeOutput
          == true
      )
    }
  }

  @Test func testXpadXbox360ProfileBatch() {
    let registry = ParserRegistry()
    let identifiers = [
      DeviceIdentifier(vendorID: 1133, productID: 49693),
      DeviceIdentifier(vendorID: 1133, productID: 49694),
      DeviceIdentifier(vendorID: 1133, productID: 49695),
      DeviceIdentifier(vendorID: 1133, productID: 49730),
      DeviceIdentifier(vendorID: 1848, productID: 18198),
      DeviceIdentifier(vendorID: 1848, productID: 18214),
      DeviceIdentifier(vendorID: 3695, productID: 275),
      DeviceIdentifier(vendorID: 3695, productID: 287),
      DeviceIdentifier(vendorID: 3695, productID: 307),
    ]

    for identifier in identifiers {
      #expect(registry.parserName(for: identifier) == "Xbox360")
      #expect(registry.runtimeProfile(for: identifier).protocolVariant == .xbox360)
      #expect(registry.transportProfile(for: identifier).inputEndpoint == 0x81)
      #expect(registry.transportProfile(for: identifier).outputEndpoint == 0x01)
    }
  }
  @Test func testXpadXboxOneProfileBatch() {
    let registry = ParserRegistry()
    let defaultSequence = GIPStartupPacket.defaultSequence
    let cases: [(DeviceIdentifier, [GIPStartupPacket], [String])] = [
      (
        DeviceIdentifier(vendorID: 1118, productID: 746),
        [.powerOn, .xboxOneSInit, .ledOn, .authDone], []
      ),
      (
        DeviceIdentifier(vendorID: 1118, productID: 2816),
        [.powerOn, .xboxOneSInit, .extraInput, .ledOn, .authDone], ["paddles"]
      ),
      (
        DeviceIdentifier(vendorID: 3853, productID: 103), [.horiAck, .powerOn, .ledOn, .authDone],
        []
      ),
      (DeviceIdentifier(vendorID: 3695, productID: 676), defaultSequence, []),
      (DeviceIdentifier(vendorID: 3695, productID: 678), defaultSequence, []),
      (DeviceIdentifier(vendorID: 3695, productID: 683), defaultSequence, []),
      (
        DeviceIdentifier(vendorID: 9414, productID: 21530),
        [.powerOn, .ledOn, .authDone, .rumbleBegin, .rumbleEnd], []
      ),
      (
        DeviceIdentifier(vendorID: 9414, productID: 21546),
        [.powerOn, .ledOn, .authDone, .rumbleBegin, .rumbleEnd], []
      ),
      (
        DeviceIdentifier(vendorID: 9414, productID: 21562),
        [.powerOn, .ledOn, .authDone, .rumbleBegin, .rumbleEnd], []
      ),
    ]

    for (identifier, startupPackets, mappingFlags) in cases {
      let profile = registry.runtimeProfile(for: identifier)
      #expect(registry.parserName(for: identifier) == "GIP")
      #expect(profile.protocolVariant == .xboxOne)
      #expect(profile.gipStartupPackets == startupPackets)
      #expect(profile.mappingFlags == mappingFlags)
      #expect(registry.transportProfile(for: identifier).inputEndpoint == 0x82)
      #expect(registry.transportProfile(for: identifier).outputEndpoint == 0x02)
    }
  }
}
