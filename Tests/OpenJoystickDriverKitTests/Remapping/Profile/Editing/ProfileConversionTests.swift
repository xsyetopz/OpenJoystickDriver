import Foundation
import Testing

@testable import OpenJoystickDriverKit

@Suite
struct ProfileConversionTests {
  private static let source = RemappingDeviceScope(vendorID: 0x045E, productID: 0x028E)
  private static let target = RemappingDeviceScope(vendorID: 0x054C, productID: 0x09CC)

  private static func capabilities(
    _ controls: Set<Control>,
    touchContactCount: UInt8 = 0,
    motion: Bool = false
  ) -> ControllerProfileCapabilities {
    ControllerProfileCapabilities(
      physicalInput: ControllerCapabilities(
        controls: controls,
        touchContactCount: touchContactCount,
        motion: motion
      ),
      physicalOutput: .none
    )
  }

  private static func binding(_ source: RemappingSource) -> RemappingBinding {
    RemappingBinding(source: source, destination: .keyboard(key: .space, modifiers: []))
  }

  private static func convert(
    _ profile: RemappingProfile,
    controls: Set<Control>,
    touchContactCount: UInt8 = 0,
    motion: Bool = false
  ) -> RemappingProfileConversion {
    RemappingProfileConversion(
      converting: profile,
      to: target,
      name: "Converted",
      capabilities: capabilities(
        controls,
        touchContactCount: touchContactCount,
        motion: motion
      )
    )
  }

  @Test
  func keepsEachBindingWhoseSourceControlTargetHasAndListsRest() throws {
    let kept = Self.binding(.button(.south))
    let dpad = Self.binding(.dpad(.up))
    let lost = Self.binding(.button(.leftPaddle1))
    let profile = RemappingProfile(
      name: "Pad",
      device: Self.source,
      applicationScope: .global,
      bindings: [kept, lost, dpad]
    )

    let result = Self.convert(profile, controls: [.south, .dpadUp])

    #expect(result.profile.bindings == [kept, dpad])
    #expect(result.leftOut == [.init(section: .binding, sources: [.button(.leftPaddle1)])])
    try result.profile.validate()
  }

  @Test
  func resultNewProfileForTargetModel() {
    let profile = RemappingProfile(
      name: "Pad",
      device: RemappingDeviceScope(vendorID: 0x045E, productID: 0x028E, unit: "U-0123456789abcdef"),
      applicationScope: .application(appIDs: ["com.example.game"]),
      bindings: [Self.binding(.button(.south))]
    )

    let result = Self.convert(profile, controls: [.south])

    #expect(result.profile.device == Self.target)
    #expect(result.profile.device.unit == nil)
    #expect(result.profile.name == "Converted")
    #expect(result.profile.id != profile.id)
    #expect(result.profile.applicationScope == profile.applicationScope)
    #expect(result.leftOut.isEmpty)
  }

  @Test
  func originalStaysUnchanged() {
    let profile = RemappingProfile(
      name: "Pad",
      device: Self.source,
      applicationScope: .global,
      bindings: [Self.binding(.button(.south)), Self.binding(.button(.leftPaddle1))]
    )
    let before = profile

    _ = Self.convert(profile, controls: [.south])

    #expect(profile == before)
  }

  @Test
  func chordKeepsOnlyWhenTargetHasEverySource() {
    let whole = RemappingChord(
      sources: [.button(.south), .button(.east)],
      destination: .keyboard(key: .space, modifiers: [])
    )
    let broken = RemappingChord(
      sources: [.button(.south), .button(.leftPaddle1)],
      destination: .keyboard(key: .space, modifiers: [])
    )
    let sequence = RemappingSequence(
      sources: [.button(.south), .button(.leftPaddle1)],
      windowMs: 500,
      destination: .keyboard(key: .space, modifiers: [])
    )
    let profile = RemappingProfile(
      name: "Pad",
      device: Self.source,
      applicationScope: .global,
      bindings: [],
      chords: [whole, broken],
      sequences: [sequence]
    )

    let result = Self.convert(profile, controls: [.south, .east])

    #expect(result.profile.chords == [whole])
    #expect(result.profile.sequences.isEmpty)
    #expect(
      result.leftOut == [
        .init(section: .chord, sources: [.button(.leftPaddle1)]),
        .init(section: .sequence, sources: [.button(.leftPaddle1)]),
      ]
    )
  }

  @Test
  func layerGoesWhenItsActivatorOrAnyContentMissing() {
    let kept = RemappingLayer(
      name: "Shift",
      activationMode: .hold,
      activator: .button(.leftShoulder),
      bindings: [Self.binding(.button(.south))]
    )
    let noActivator = RemappingLayer(
      name: "Paddle",
      activationMode: .hold,
      activator: .button(.leftPaddle1),
      bindings: [Self.binding(.button(.south))]
    )
    let noContent = RemappingLayer(
      name: "Other",
      activationMode: .hold,
      activator: .button(.leftShoulder),
      bindings: [Self.binding(.button(.rightPaddle1))]
    )
    let profile = RemappingProfile(
      name: "Pad",
      device: Self.source,
      applicationScope: .global,
      bindings: [],
      layers: [kept, noActivator, noContent]
    )

    let result = Self.convert(profile, controls: [.south, .leftShoulder])

    #expect(result.profile.layers == [kept])
    #expect(
      result.leftOut == [
        .init(section: .layer, sources: [.button(.leftPaddle1)]),
        .init(section: .layer, sources: [.button(.rightPaddle1)]),
      ]
    )
  }

  @Test
  func analogSourcesNeedTheirAxesAndTouchAndMotionNeedTheirSensors() {
    let bindings = [
      Self.binding(.axis(.leftStickX)),
      Self.binding(.triggerStage(.left, .soft)),
      Self.binding(.motionLean(.left)),
      Self.binding(.touchContact(.primary)),
    ]
    let profile = RemappingProfile(
      name: "Pad",
      device: Self.source,
      applicationScope: .global,
      bindings: bindings
    )

    let bare = Self.convert(profile, controls: [])
    let full = Self.convert(
      profile,
      controls: [.leftStickX, .leftTrigger],
      touchContactCount: 2,
      motion: true
    )

    #expect(bare.profile.bindings.isEmpty)
    #expect(bare.leftOut.count == 4)
    #expect(full.profile.bindings == bindings)
    #expect(full.leftOut.isEmpty)
  }

  @Test
  func settingsNeedAbsentPartLeftOutAndRestStays() {
    let stick = RemappingStickMapping(source: .right, mode: .aim)
    let profile = RemappingProfile(
      name: "Pad",
      device: Self.source,
      applicationScope: .global,
      physicalColor: ControllerColor(red: 1, green: 0, blue: 0),
      gyroOutput: RemappingGyroOutput(mode: .mouse),
      stickMappings: [stick],
      bindings: []
    )

    let result = Self.convert(profile, controls: [.south])

    #expect(result.profile.stickMappings.isEmpty)
    #expect(result.profile.gyroOutput == .default)
    #expect(result.profile.physicalColor == profile.physicalColor)
    #expect(
      result.leftOut.map(\.section) == [.stickMapping, .gyroOutput]
    )
  }
}
