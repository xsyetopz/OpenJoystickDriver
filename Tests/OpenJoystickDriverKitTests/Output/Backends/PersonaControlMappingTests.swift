import Testing

@testable import OpenJoystickDriverKit

/// Which controls each virtual persona carries, and the reason each missing one is missing.
struct PersonaControlMappingTests {
  private typealias Dispatcher = VirtualGamepadReportMapping

  private static let steamControllerWired = LogicalControllerID(vendorID: 0x28DE, productID: 0x1102)
  private static let steamDeck = LogicalControllerID(vendorID: 0x28DE, productID: 0x1205)
  private static let steamTriton = LogicalControllerID(vendorID: 0x28DE, productID: 0x1303)

  private static let uncarried: [Control] = [
    .touchpadClick, .microphone, .leftPaddle1, .leftPaddle2, .rightPaddle1, .rightPaddle2,
    .auxiliary1, .auxiliary2, .auxiliary3, .auxiliary4, .auxiliary5, .auxiliary6, .auxiliary7,
    .auxiliary8, .leftStickTouch, .rightStickTouch, .leftTrackpadClick, .leftTrackpadTouch,
    .rightTrackpadTouch, .rightTrackpadClick,
  ]

  @Test
  func theClassicSteamControllerRightPadIsItsRightStick() {
    #expect(Dispatcher.rightPadIsRightStick(Self.steamControllerWired))
    let pad = Dispatcher.virtualControl(.rightTrackpadClick, rightPadIsRightStick: true)
    #expect(Dispatcher.buttonBit(for: pad) == 7)
  }

  @Test
  func aDeckAndATritonKeepTheirRealRightStickClick() {
    for identifier in [Self.steamDeck, Self.steamTriton] {
      #expect(!Dispatcher.rightPadIsRightStick(identifier))
      let pad = Dispatcher.virtualControl(.rightTrackpadClick, rightPadIsRightStick: false)
      #expect(Dispatcher.buttonBit(for: pad) == nil)
      let stick = Dispatcher.virtualControl(.rightStickClick, rightPadIsRightStick: false)
      #expect(Dispatcher.buttonBit(for: stick) == 7)
    }
  }

  @Test
  func reportMappingAppliesTheRightPadRule() {
    let input = ControllerState(pressed: [.rightTrackpadClick])
    func buttons(rightPadIsRightStick: Bool) -> UInt32 {
      var state = VirtualGamepadState()
      Dispatcher.apply(
        input,
        stickTransfer: Dispatcher.StickTransfer(deadzone: 0, rescalesDeadzone: false),
        rightPadIsRightStick: rightPadIsRightStick,
        to: &state
      )
      return state.buttons
    }
    #expect(buttons(rightPadIsRightStick: true) == 1 << 7)
    #expect(buttons(rightPadIsRightStick: false) == 0)
  }

  @Test(arguments: [VirtualHIDProfileID.generic, .sdlCompatible])
  func noPersonaCarriesAnUncarriedControl(_ id: VirtualHIDProfileID) throws {
    let profile = try id.makeProfile()
    let neutral = profile.inputReport(for: .neutral)
    for control in Self.uncarried {
      #expect(Dispatcher.buttonBit(for: control) == nil)
      #expect(profile.inputReport(for: ControllerState(pressed: [control])) == neutral)
    }
  }

  @Test
  func captureIsCarriedByTheGenericPersonaOnly() throws {
    let capture = ControllerState(pressed: [.capture])
    let generic = try VirtualHIDProfileID.generic.makeProfile()
    #expect(generic.inputReport(for: capture) != generic.inputReport(for: .neutral))
    let sdl = try VirtualHIDProfileID.sdlCompatible.makeProfile()
    #expect(sdl.inputReport(for: capture) == sdl.inputReport(for: .neutral))
  }

  /// The rule reads the resolved record: a record or patch that changes the capability changes it.
  @Test
  func theRuleFollowsTheRecordsCapabilities() throws {
    func record(_ identifier: LogicalControllerID) throws -> DeviceRuntimeProfile {
      try #require(DeviceCatalog.current.withLock { $0 }.record(for: identifier.model))
    }
    let classic = try record(Self.steamControllerWired)
    let deck = try record(Self.steamDeck)
    #expect(Dispatcher.rightPadIsRightStick(record: classic))
    #expect(!Dispatcher.rightPadIsRightStick(record: deck))
    #expect(!Dispatcher.rightPadIsRightStick(record: nil))

    // A record that gives the classic controller a real R3 keeps its pad click as its own control.
    #expect(
      !Dispatcher.rightPadIsRightStick(
        record: classic.withCapabilityDelta(absent: [], present: [.rightStickClick])
      )
    )
    // A record that removes the Deck's R3 makes its right pad the right stick.
    #expect(
      Dispatcher.rightPadIsRightStick(
        record: deck.withCapabilityDelta(absent: [.rightStickClick], present: [])
      )
    )
    // A record without the pad click has nothing to move onto R3.
    #expect(
      !Dispatcher.rightPadIsRightStick(
        record: classic.withCapabilityDelta(absent: [.rightTrackpadClick], present: [])
      )
    )
  }

  /// The passthrough reads the catalog record once per update, however many buttons are held, and
  /// maps the held pad click by that one answer.
  @Test(arguments: [true, false])
  func passthroughLooksTheRecordUpOncePerUpdate(padIsRightStick: Bool) throws {
    final class Lookups: @unchecked Sendable { var count = 0 }
    let lookups = Lookups()
    let profile = RemappingProfile(
      name: "Pad passthrough",
      device: RemappingDeviceScope(vendorID: 0x28DE, productID: 0x1102),
      applicationScope: .global,
      outputPolicy: RemappingOutputPolicy(virtualGamepad: .passthrough),
      bindings: []
    )
    var device = RemappingDeviceState(profile: profile, identifier: Self.steamControllerWired)
    device.activeSources = [
      .button(.south), .button(.east), .button(.north), .button(.rightTrackpadClick),
    ]
    let lookup: (LogicalControllerID) -> Bool = { _ in
      lookups.count += 1
      return padIsRightStick
    }
    let actions = device.updatePassthrough(rightPadIsRightStick: lookup)
    #expect(lookups.count == 1)
    let expected: Set<Control> =
      padIsRightStick
      ? [.south, .east, .north, .rightStickClick] : [.south, .east, .north, .rightTrackpadClick]
    #expect(
      actions == [.gamepad(RemappingGamepadState(buttons: expected), Self.steamControllerWired)]
    )
  }
}

extension DeviceRuntimeProfile {
  /// This record with another capability delta; everything else it runs with is unchanged.
  func withCapabilityDelta(
    absent: Set<Control>,
    present: Set<Control>
  ) -> DeviceRuntimeProfile {
    DeviceRuntimeProfile(
      recordID: recordID,
      transportProfile: transportProfile,
      physicalProtocolID: physicalProtocolID,
      physicalProtocolVariant: physicalProtocolVariant,
      parameters: parameters,
      capabilityDelta: ControllerCapabilityDelta(
        absentControls: absent,
        presentControls: present,
        rumbleAbsent: capabilityDelta.rumbleAbsent
      ),
      preferredBackends: preferredBackends,
      gipStartupPackets: gipStartupPackets,
      gipKeepAlivePolicy: gipKeepAlivePolicy,
      assemblyPolicy: assemblyPolicy,
      server: server,
      session: session,
      inputLayouts: inputLayouts,
      hidUsageMap: hidUsageMap,
      tuning: tuning,
      modes: modes
    )
  }
}
