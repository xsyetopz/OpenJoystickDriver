import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverPresentation

extension RuntimeProfileDraftTests {
  @Test
  func profileEditsPreserveOutputAndIsolationPolicy() throws {
    let policy = RemappingOutputPolicy(virtualGamepad: .passthrough, physicalInput: .exclusive)
    let profile = RemappingProfile(
      name: "Output",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      outputPolicy: policy,
      bindings: []
    )
    var draft = try RuntimeProfileDraft(profile: profile).addingBinding(
      source: .button(.south),
      destination: .keyboard(key: .a, modifiers: [])
    )
    #expect(draft.profile.outputPolicy == policy)
    let binding = try #require(draft.profile.bindings.first)
    draft = try draft.settingDestination(.keyboard(key: .b, modifiers: []), for: binding.id)
    #expect(draft.profile.outputPolicy == policy)
    draft = try draft.settingMetadata(
      name: "Renamed",
      device: profile.device,
      applicationScope: .global
    )
    #expect(draft.profile.outputPolicy == policy)
    draft = try draft.removingBinding(binding.id)
    #expect(draft.profile.outputPolicy == policy)
    try draft.validatedProfile().validate()
  }

  @Test
  func profileDraftRejectsInvalidSourceDuplication() throws {
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

  @Test


  func profileDraftPreservesCompatibleDestinationWhenChangingSource() throws {
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

  @Test
  func destinationOptionsCurateModifiersAndPreserveCustomDestinations() {
    let custom = RemappingDestination.keyboard(
      key: .a,
      modifiers: [.meta, .control, .alt, .shift]
    )
    let options = DestinationOption.options(for: .button(.south))

    #expect(options.first?.destination == .keyboard(key: .space, modifiers: []))
    #expect(options.count < 420)
    #expect(
      options.contains {
        $0.destination == .keyboard(key: .arrowUp, modifiers: [.meta, .shift])
      }
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

  @Test
  func systemDestinationsAreListedForDiscreteSourcesAndLabeledInWords() {
    let discrete = DestinationOption.options(for: .button(.south))
    let axis = DestinationOption.options(for: .axis(.leftStickX))

    #expect(discrete.contains { $0.destination == .systemKey(.volumeUp) })
    #expect(discrete.contains { $0.destination == .systemAction(.missionControl) })
    #expect(!axis.contains { $0.destination == .systemKey(.volumeUp) })
    #expect(RuntimePresentation.destinationLabel(.systemKey(.volumeUp)) == "System key Volume Up")
    #expect(
      RuntimePresentation.destinationLabel(.systemAction(.missionControl))
        == "System action Mission Control"
    )
    #expect(
      RuntimePresentation.destinationLabel(.openApplication(bundleIdentifier: "com.apple.Safari"))
        == "Open com.apple.Safari"
    )
    #expect(
      RuntimePresentation.destinationLabel(.openURL("https://example.com"))
        == "Open URL https://example.com"
    )
    #expect(RuntimePresentation.destinationLabel(.runShortcut("Dim")) == "Run Shortcut Dim")
    #expect(RuntimePresentation.destinationLabel(.typeText("hi")) == "Type hi")
  }

  @Test
  func profileDraftSwitchingToContinuousSourceUsesConventionalDestination() throws {
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

  @Test
  func profileDraftSwitchingToDiscreteSourceUsesConventionalDestination() throws {
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

  @Test
  func profileDraftSettingSourceRejectsDuplicateSource() throws {
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

  @Test
  func sourceOptionsOmitGuideForCaptureButPreserveExistingGuide() {
    let guide = RemappingSource.button(.guide)
    let ordinary = SourceOption.options()
    let preserving = SourceOption.options(including: guide)

    #expect(!ordinary.contains { $0.source == guide })
    #expect(preserving.last?.source == guide)
    #expect(preserving.count == ordinary.count + 1)
    #expect(SourceOption.options(including: .button(.south)).count == ordinary.count)
  }

  @Test
  func identifierInputAcceptsTheSameDecimalAndHexFormsAsTheCLI() {
    #expect(ProfileIdentifierInput.parse("4660") == 0x1234)
    #expect(ProfileIdentifierInput.parse(" 0x1234 ") == 0x1234)
    #expect(ProfileIdentifierInput.parse("0XFFFF") == UInt16.max)
    #expect(ProfileIdentifierInput.parse("65536") == nil)
    #expect(ProfileIdentifierInput.parse("controller") == nil)
  }

  @Test
  func profileDraftSupportsCLIMetadataAndAdvancedBindingParity() throws {
    let original = makeProfile()
    let binding = try #require(original.bindings.first)
    var draft = RuntimeProfileDraft(profile: original)

    draft = try draft.settingMetadata(
      name: "Application Profile",
      device: RemappingDeviceScope(vendorID: 0x045E, productID: 0x02EA),
      applicationScope: .application(appID: "com.example.Game")
    )
    draft = try draft.settingBindingBehaviors(
      turbo: nil,
      longHold: RemappingLongHold(durationMs: 500, destination: .keyboard(key: .b, modifiers: [])),
      multiTap: [
        RemappingMultiTap(count: 2, windowMs: 250, destination: .keyboard(key: .c, modifiers: []))
      ],
      for: binding.id
    )

    #expect(draft.profile.name == "Application Profile")
    #expect(draft.profile.device == RemappingDeviceScope(vendorID: 0x045E, productID: 0x02EA))
    #expect(draft.profile.applicationScope == .application(appID: "com.example.Game"))
    #expect(draft.profile.bindings[0].longHold?.durationMs == 500)
    #expect(draft.profile.bindings[0].multiTap.first?.windowMs == 250)
  }

  @Test
  func removingAllBindingsKeepsTheOtherInputSettings() throws {
    var draft = RuntimeProfileDraft(profile: makeProfile())
    draft = try draft.addingChord(
      sources: [.button(.east), .button(.west)],
      destination: .keyboard(key: .b, modifiers: []),
      mode: .simultaneous,
      windowMs: 375
    )
    draft = try draft.addingLayer(
      name: "Precision",
      activator: .button(.leftShoulder),
      activationMode: .hold
    )
    let sticks = draft.profile.stickMappings

    draft = try draft.removingAllBindings()

    #expect(draft.profile.bindings.isEmpty)
    #expect(draft.profile.chords.isEmpty)
    #expect(draft.profile.sequences.isEmpty)
    #expect(draft.profile.layers.isEmpty)
    #expect(draft.profile.stickMappings == sticks)
  }

  @Test
  func profileDraftSupportsCLIChordSequenceAndLayerParity() throws {
    var draft = RuntimeProfileDraft(profile: makeProfile())
    draft = try draft.addingChord(
      sources: [.button(.east), .button(.west)],
      destination: .keyboard(key: .b, modifiers: []),
      mode: .simultaneous,
      windowMs: 375
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
    #expect(draft.profile.chords[0].mode == .simultaneous)
    #expect(draft.profile.chords[0].windowMs == 375)
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

  @Test
  func dirtyProfileEditorDefersImportUntilDiscardIsConfirmed() {
    let imported = makeProfile(name: "Imported")
    var state = ProfileEditorTransitionState()
    state.setDirty(true)

    #expect(state.request(.importProfile(imported)) == .confirmDiscard)
    #expect(state.pendingAction == .importProfile(imported))
    #expect(state.isDirty)

    #expect(state.discardPendingAction() == .importProfile(imported))
    #expect(!state.isDirty)
    #expect(state.pendingAction == nil)
  }

  @Test
  func canceledProfileEditorTransitionKeepsDirtyDraftAndDropsPendingImport() {
    let imported = makeProfile(name: "Imported")
    var state = ProfileEditorTransitionState()
    state.setDirty(true)

    #expect(state.request(.importProfile(imported)) == .confirmDiscard)
    state.cancelPendingAction()

    #expect(state.isDirty)
    #expect(state.pendingAction == nil)
  }

  @Test
  func inFlightSameProfileImportBlocksEditingAndPreservesAConcurrentDraft() {
    let profile = makeProfile()
    let request = RuntimeMutationRequest(operation: .importProfile(profileID: profile.id))
    var state = ProfileEditorTransitionState()
    state.beginMutation(request)

    #expect(state.isEditingBlocked)
    state.setDirty(true)

    let shouldRefreshEditor = state.finishMutation(request)
    #expect(!shouldRefreshEditor)
    #expect(!state.isEditingBlocked)
    #expect(state.isDirty)
  }

  @Test
  func activeImportBlocksSelectionWithoutQueueingAReplacementAction() {
    let profile = makeProfile()
    let otherProfileID = UUID()
    let request = RuntimeMutationRequest(operation: .importProfile(profileID: profile.id))
    var state = ProfileEditorTransitionState()
    state.beginMutation(request)

    #expect(state.request(.select(otherProfileID)) == .blocked)
    #expect(state.pendingAction == nil)
    #expect(state.isEditingBlocked)
  }

  @Test
  func failedImportReleasesTheEditingBlock() {
    let profile = makeProfile()
    let request = RuntimeMutationRequest(operation: .importProfile(profileID: profile.id))
    var state = ProfileEditorTransitionState()
    state.beginMutation(request)

    _ = state.finishMutation(request, succeeded: false)

    #expect(!state.isEditingBlocked)
  }

  @Test
  func failedImportAfterDiscardConfirmationRestoresDirtyStateForLaterSelection() {
    let imported = makeProfile(name: "Imported")

    let otherProfileID = UUID()
    let request = RuntimeMutationRequest(operation: .importProfile(profileID: imported.id))
    var state = ProfileEditorTransitionState()
    state.setDirty(true)

    #expect(state.request(.importProfile(imported)) == .confirmDiscard)
    #expect(state.discardPendingAction() == .importProfile(imported))

    #expect(!state.isDirty)

    state.beginMutation(request)

    #expect(state.request(.select(otherProfileID)) == .blocked)
    _ = state.finishMutation(request, succeeded: false)

    #expect(state.isDirty)
    #expect(state.request(.select(otherProfileID)) == .confirmDiscard)
    #expect(state.pendingAction == .select(otherProfileID))
  }

}
