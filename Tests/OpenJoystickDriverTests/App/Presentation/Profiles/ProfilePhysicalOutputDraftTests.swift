import Testing

@testable import OpenJoystickDriver
import OpenJoystickDriverKit

struct ProfilePhysicalOutputDraftTests {
  @Test func destinationCatalogIncludesEveryPhysicalOutputKind() {
    let outputs = DestinationOption.physical.compactMap { option -> RemappingPhysicalOutput? in
      guard case .physical(let output) = option.destination else { return nil }
      return output
    }

    #expect(outputs.contains { if case .rumble = $0 { return true }; return false })
    #expect(outputs.contains { if case .playerIndicator = $0 { return true }; return false })
    #expect(outputs.contains { if case .color = $0 { return true }; return false })
    #expect(outputs.contains { if case .brightness = $0 { return true }; return false })
    #expect(outputs.contains { if case .adaptiveTrigger = $0 { return true }; return false })
  }

  @Test func importedPhysicalValueRemainsEditableOutsidePresetCatalog() throws {
    let custom = RemappingDestination.physical(
      .adaptiveTrigger(
        .left,
        PhysicalAdaptiveTriggerEffect(
          kind: .resistance,
          startPosition: 0.23,
          strength: 0.61
        )
      )
    )
    #expect(
      DestinationOption.options(for: .button(.south), including: custom).contains {
        $0.destination == custom
      }
    )

    let profile = RemappingProfile(
      name: "Physical",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      bindings: [
        RemappingBinding(source: .button(.south), destination: .physical(.brightness(0.5)))
      ]
    )
    let changed = try RuntimeProfileDraft(profile: profile).settingDestination(
      custom,
      for: profile.bindings[0].id
    )
    #expect(changed.profile.bindings[0].destination == custom)
  }
}
