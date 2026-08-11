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
