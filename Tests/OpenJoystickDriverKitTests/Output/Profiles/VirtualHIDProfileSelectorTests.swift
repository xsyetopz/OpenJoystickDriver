import Testing

@testable import OpenJoystickDriverKit

struct VirtualHIDProfileSelectorTests {
  private typealias Selector = VirtualHIDProfileSelector

  @Test
  func fullXboxLayoutSelectsSDLCompatible() throws {
    let selection = try Selector.select(controls: Control.xboxLayout, override: nil)
    #expect(selection == .init(profileID: .sdlCompatible, source: .automatic))
  }

  @Test
  func everyDeclaredControlTogetherStillSelectsXboxProfile() throws {
    let selection = try Selector.select(controls: Set(Control.allCases), override: nil)
    #expect(selection == .init(profileID: .sdlCompatible, source: .automatic))
  }

  @Test
  func extendedAndSystemControlsDoNotForceProfile() throws {
    let controls = Control.xboxLayout.union([
      .guide, .capture, .capture, .touchpadClick, .microphone, .leftPaddle1, .rightPaddle2,
      .auxiliary8, .leftTrackpadClick, .rightTrackpadTouch,
    ])
    #expect(try Selector.select(controls: controls, override: nil).profileID == .sdlCompatible)
  }

  @Test
  func digitalOnlyTriggersFitTriggerSlots() throws {
    let controls = Control.xboxLayout.subtracting([.leftTrigger, .rightTrigger]).union([
      .leftTrigger, .rightTrigger,
    ])
    #expect(try Selector.select(controls: controls, override: nil).profileID == .sdlCompatible)
  }

  @Test
  func subsetOfXboxLayoutSelectsXboxProfile() throws {
    let controls = Control.dpad.union([.south, .east, .back, .start])
    #expect(try Selector.select(controls: controls, override: nil).profileID == .sdlCompatible)
  }

  @Test(arguments: VirtualHIDProfileID.allCases)
  func advancedOverrideWins(profile: VirtualHIDProfileID) throws {
    let selection = try Selector.select(controls: Control.xboxLayout, override: profile)
    #expect(selection == .init(profileID: profile, source: .override))
  }

  /// A new `Control` must be classified here on purpose: primary controls decide the profile.
  @Test
  func everyControlOutsideXboxLayoutAndTriggerButtonsIsNonPrimary() {
    let nonPrimary: Set<Control> = [
      .guide, .capture, .capture, .touchpadClick, .microphone, .leftPaddle1, .leftPaddle2,
      .rightPaddle1, .rightPaddle2, .auxiliary1, .auxiliary2, .auxiliary3, .auxiliary4, .auxiliary5,
      .auxiliary6, .auxiliary7, .auxiliary8, .leftStickTouch, .rightStickTouch, .leftTrackpadClick,
      .rightTrackpadClick, .leftTrackpadTouch, .rightTrackpadTouch, .pointerX, .pointerY,
      .pointerTracking, .leftGripTouch, .rightGripTouch,
    ]
    #expect(Set(Control.allCases).subtracting(Selector.primaryControls) == nonPrimary)
  }

  /// Both profiles carry every primary control today, so automatic selection always takes
  /// `SDLCompatible`, an override is always satisfiable, and `virtual-profile-unavailable` cannot
  /// occur with the real profiles.
  ///
  /// The synthetic-slot tests below cover those branches.
  @Test(arguments: VirtualHIDProfileID.allCases)
  func everyProfileRepresentsEveryPrimaryControl(profile: VirtualHIDProfileID) {
    #expect(Selector.represents(Selector.primaryControls, in: profile.representableControls))
  }

  @Test
  func representationChecksEachControlAgainstProfileSlots() {
    #expect(Selector.represents([.leftTrigger], in: [.leftTrigger]))
    #expect(!Selector.represents([.leftTrigger], in: [.rightTrigger]))
    #expect(!Selector.represents([.south], in: [.east]))
  }

  @Test
  func automaticSelectionFallsToGenericWhenSDLCompatibleCannotCarryControls() throws {
    let slots: [VirtualHIDProfileID: Set<Control>] = [
      .sdlCompatible: [.south], .generic: [.south, .east],
    ]
    let selection = try Selector.select(controls: [.south, .east], override: nil) {
      slots[$0, default: []]
    }
    #expect(selection == .init(profileID: .generic, source: .automatic))
  }

  @Test
  func automaticSelectionFailsWhenNeitherPersonaCarriesControls() {
    let slots: [VirtualHIDProfileID: Set<Control>] = [
      .sdlCompatible: [.south], .generic: [.south],
    ]
    #expect(throws: ProtocolBindingReason.virtualProfileUnavailable) {
      try Selector.select(controls: [.south, .east], override: nil) {
        slots[$0, default: []]
      }
    }
  }

  @Test
  func genericOverrideKeepsGenericForControllerSDLCompatibleFits() throws {
    let selection = try Selector.select(controls: Control.xboxLayout, override: .generic)
    #expect(selection == .init(profileID: .generic, source: .override))
  }

  @Test
  func unsatisfiableGenericOverrideFallsBackToSDLCompatible() throws {
    let slots: [VirtualHIDProfileID: Set<Control>] = [
      .sdlCompatible: [.south, .east], .generic: [.south],
    ]
    let selection = try Selector.select(controls: [.south, .east], override: .generic) {
      slots[$0, default: []]
    }
    #expect(
      selection == .init(profileID: .sdlCompatible, source: .automaticAfterRejecting(.generic))
    )
  }

  @Test
  func unsatisfiableOverrideFallsBackToAutomaticSelection() throws {
    let slots: [VirtualHIDProfileID: Set<Control>] = [
      .generic: [.south, .east], .sdlCompatible: [.south],
    ]
    let selection = try Selector.select(
      controls: [.south, .east],
      override: .sdlCompatible
    ) { slots[$0, default: []] }
    #expect(
      selection == .init(profileID: .generic, source: .automaticAfterRejecting(.sdlCompatible))
    )
  }

  @Test
  func controlsNoProfileCarriesFailWithVirtualProfileUnavailable() {
    #expect(throws: ProtocolBindingReason.virtualProfileUnavailable) {
      try Selector.select(controls: [.south], override: nil) { _ in [] }
    }
  }
}
