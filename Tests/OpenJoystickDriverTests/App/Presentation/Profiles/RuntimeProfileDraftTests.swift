import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriver

@Suite(.serialized) struct RuntimeProfileDraftTests {
  @Test func profileDraftRejectsInvalidSourceDuplication() throws {
    let profile = makeProfile()
    let draft = RuntimeProfileDraft(profile: profile)

    do {
      _ = try draft.addingBinding(
        source: .button(.south),
        destination: .keyboard(key: .b, modifiers: [])
      )
      Issue.record("Expected duplicate source validation to fail")
    } catch let error as RuntimeProfileDraftError {
      guard case .validation(.duplicateSource) = error else {
        Issue.record("Unexpected draft error: \(error)")
        return
      }
    }
  }

  @Test func profileDraftPreservesCompatibleDestinationWhenChangingSource() throws {
    let binding = RemappingBinding(
      source: .button(.south),
      destination: .keyboard(key: .b, modifiers: [])
    )
    let profile = RemappingProfile(
      name: "Test Profile",
      device: RemappingDeviceScope(vendorID: 0x1234, productID: 0x5678),
      applicationScope: .global,
      bindings: [binding]
    )

    let edited = try RuntimeProfileDraft(profile: profile).settingSource(
      .button(.east),
      for: binding.id
    )
    #expect(edited.profile.bindings[0].source == .button(.east))
    #expect(edited.profile.bindings[0].destination == binding.destination)
  }

  @Test func destinationOptionsCurateModifiersAndPreserveCustomDestinations() {
    let custom = RemappingDestination.keyboard(
      key: .a,
      modifiers: [.command, .control, .option, .shift]
    )
    let options = DestinationOption.options(for: .button(.south))

    #expect(options.first?.destination == .keyboard(key: .space, modifiers: []))
    #expect(options.count < 400)
    #expect(
      options.contains { $0.destination == .keyboard(key: .arrowUp, modifiers: [.command, .shift]) }
    )
    #expect(!options.contains { $0.destination == custom })

    let preserving = DestinationOption.options(for: .button(.south), including: custom)
    #expect(preserving.last?.destination == custom)
    #expect(preserving.count == options.count + 1)
    #expect(
      !DestinationOption.options(for: .button(.south), including: .mouseMovement(.x)).contains {
        $0.destination == .mouseMovement(.x)
      }
    )
  }

  @Test func profileDraftSwitchingToContinuousSourceUsesConventionalDestination() throws {
    let binding = RemappingBinding(
      source: .button(.south),
      destination: .keyboard(key: .b, modifiers: [])
    )
    let profile = RemappingProfile(
      name: "Test Profile",
      device: RemappingDeviceScope(vendorID: 0x1234, productID: 0x5678),
      applicationScope: .global,
      bindings: [binding]
    )

    let edited = try RuntimeProfileDraft(profile: profile).settingSource(
      .axis(.leftStickX),
      for: binding.id
    )
    #expect(edited.profile.bindings[0].destination == .mouseMovement(.x))
    #expect(edited.profile.bindings[0].axisTuning == .default)
  }

  @Test func profileDraftSwitchingToDiscreteSourceUsesConventionalDestination() throws {
    let binding = RemappingBinding(
      source: .axis(.leftStickX),
      destination: .mouseMovement(.y),
      axisTuning: .default
    )
    let profile = RemappingProfile(
      name: "Test Profile",
      device: RemappingDeviceScope(vendorID: 0x1234, productID: 0x5678),
      applicationScope: .global,
      bindings: [binding]
    )

    let edited = try RuntimeProfileDraft(profile: profile).settingSource(
      .dpad(.left),
      for: binding.id
    )
    #expect(edited.profile.bindings[0].destination == .keyboard(key: .space, modifiers: []))
    #expect(edited.profile.bindings[0].axisTuning == nil)
  }

  @Test func profileDraftSettingSourceRejectsDuplicateSource() throws {
    let first = RemappingBinding(
      source: .button(.south),
      destination: .keyboard(key: .a, modifiers: [])
    )
    let second = RemappingBinding(
      source: .button(.east),
      destination: .keyboard(key: .b, modifiers: [])
    )
    let profile = RemappingProfile(
      name: "Test Profile",
      device: RemappingDeviceScope(vendorID: 0x1234, productID: 0x5678),
      applicationScope: .global,
      bindings: [first, second]
    )
    let draft = RuntimeProfileDraft(profile: profile)

    do {
      _ = try draft.settingSource(.button(.south), for: second.id)
      Issue.record("Expected duplicate source validation to fail")
    } catch let error as RuntimeProfileDraftError {
      guard case .validation(.duplicateSource(let source)) = error else {
        Issue.record("Unexpected draft error: \(error)")
        return
      }
      #expect(source == .button(.south))
    }
  }

  @Test func sourceOptionsOmitGuideForCaptureButPreserveExistingGuide() {
    let guide = RemappingSource.button(.guide)
    let ordinary = SourceOption.options()
    let preserving = SourceOption.options(including: guide)

    #expect(!ordinary.contains { $0.source == guide })
    #expect(preserving.last?.source == guide)
    #expect(preserving.count == ordinary.count + 1)
    #expect(SourceOption.options(including: .button(.south)).count == ordinary.count)
  }

  @Test func identifierInputAcceptsTheSameDecimalAndHexFormsAsTheCLI() {
    #expect(ProfileIdentifierInput.parse("4660") == 0x1234)
    #expect(ProfileIdentifierInput.parse(" 0x1234 ") == 0x1234)
    #expect(ProfileIdentifierInput.parse("0XFFFF") == UInt16.max)
    #expect(ProfileIdentifierInput.parse("65536") == nil)
    #expect(ProfileIdentifierInput.parse("controller") == nil)
  }

  @Test func profileDraftSupportsCLIMetadataAndAdvancedBindingParity() throws {
    let original = makeProfile()
    let binding = try #require(original.bindings.first)
    var draft = RuntimeProfileDraft(profile: original)

    draft = try draft.settingMetadata(
      name: "Application Profile",
      device: RemappingDeviceScope(vendorID: 0x045E, productID: 0x02EA),
      applicationScope: .application(bundleIdentifier: "com.example.Game")
    )
    draft = try draft.settingBindingBehaviors(
      turbo: nil,
      longHold: RemappingLongHold(durationMs: 500, destination: .keyboard(key: .b, modifiers: [])),
      doubleTap: RemappingDoubleTap(windowMs: 250, destination: .keyboard(key: .c, modifiers: [])),
      for: binding.id
    )

    #expect(draft.profile.name == "Application Profile")
    #expect(draft.profile.device == RemappingDeviceScope(vendorID: 0x045E, productID: 0x02EA))
    #expect(draft.profile.applicationScope == .application(bundleIdentifier: "com.example.Game"))
    #expect(draft.profile.bindings[0].longHold?.durationMs == 500)
    #expect(draft.profile.bindings[0].doubleTap?.windowMs == 250)
  }

  @Test func profileDraftSupportsCLIChordSequenceAndLayerParity() throws {
    var draft = RuntimeProfileDraft(profile: makeProfile())
    draft = try draft.addingChord(
      sources: [.button(.east), .button(.west)],
      destination: .keyboard(key: .b, modifiers: [])
    )
    draft = try draft.addingSequence(
      sources: [.button(.north), .dpad(.up)],
      windowMs: 750,
      destination: .keyboard(key: .c, modifiers: [])
    )
    draft = try draft.addingLayer(
      name: "Precision",
      activator: .button(.leftShoulder),
      activationMode: .hold
    )
    let layer = try #require(draft.profile.layers.first)
    draft = try draft.settingLayerBinding(
      layerID: layer.id,
      source: .axis(.leftStickX),
      destination: .mouseMovement(.x)
    )
    let layerBinding = try #require(draft.profile.layers.first?.bindings.first)
    let tuning = RemappingAxisTuning(deadzone: 0.2, gain: 1.5)
    draft = try draft.settingLayerBindingAxisTuning(
      layerID: layer.id,
      bindingID: layerBinding.id,
      axisTuning: tuning
    )

    #expect(draft.profile.chords.count == 1)
    #expect(draft.profile.sequences.count == 1)
    #expect(draft.profile.layers.count == 1)
    #expect(draft.profile.layers[0].bindings[0].axisTuning == tuning)

    draft = try draft.removingChord(draft.profile.chords[0].id)
    draft = try draft.removingSequence(draft.profile.sequences[0].id)
    draft = try draft.removingLayerBinding(layerID: layer.id, bindingID: layerBinding.id)
    draft = try draft.removingLayer(layer.id)
    #expect(draft.profile.chords.isEmpty)
    #expect(draft.profile.sequences.isEmpty)
    #expect(draft.profile.layers.isEmpty)
  }

  private func makeProfile(id: UUID = UUID(), name: String = "Test Profile") -> RemappingProfile {
    RemappingProfile(
      id: id,
      name: name,
      device: RemappingDeviceScope(vendorID: 0x1234, productID: 0x5678),
      applicationScope: .global,
      bindings: [
        RemappingBinding(source: .button(.south), destination: .keyboard(key: .a, modifiers: []))
      ]
    )
  }
}
