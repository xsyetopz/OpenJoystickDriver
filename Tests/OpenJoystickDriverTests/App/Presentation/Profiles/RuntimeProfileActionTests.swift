import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriver

struct RuntimeProfileActionTests {
  @Test func cliCanReplaceAndClearNativeActionCollection() throws {
    let binding = RemappingBinding(source: .button(.south), destination: .gamepadButton(.north))
    let profile = RemappingProfile(
      name: "CLI actions",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      outputPolicy: RemappingOutputPolicy(virtualGamepad: .mapped),
      bindings: [binding]
    )
    let actions = [RemappingAction(
      destination: .keyboard(key: .a, modifiers: []), behavior: .toggle
    )]
    let json = try #require(String(data: JSONEncoder().encode(actions), encoding: .utf8))
    let authored = try MappingProfileEditor.replacingBinding(
      in: profile,
      source: binding.source,
      destination: binding.destination,
      options: MappingOptions(["--actions-json", json])
    )
    #expect(authored.bindings.first?.additionalActions == actions)
    #expect(authored.requiresSystemInputAccess)
    let cleared = try MappingProfileEditor.replacingBinding(
      in: authored,
      source: binding.source,
      destination: binding.destination,
      options: MappingOptions(["--actions-json", "[]"])
    )
    #expect(cleared.bindings.first?.additionalActions.isEmpty == true)
    #expect(!cleared.requiresSystemInputAccess)
    #expect(throws: (any Error).self) {
      try MappingProfileEditor.replacingBinding(
        in: authored,
        source: binding.source,
        destination: binding.destination,
        options: MappingOptions(["--actions-json", "invalid"])
      )
    }
  }

  @Test(arguments: [false, true])
  func destinationEditsPreserveAdditionalActions(inLayer: Bool) throws {
    let binding = RemappingBinding(source: .button(.south), destination: .gamepadButton(.north))
    let layer = RemappingLayer(
      name: "Layer", activationMode: .hold, activator: .button(.west), bindings: [binding]
    )
    let profile = RemappingProfile(
      name: "Actions",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      outputPolicy: RemappingOutputPolicy(virtualGamepad: .mapped),
      bindings: inLayer ? [] : [binding],
      layers: inLayer ? [layer] : []
    )
    let actions = [RemappingAction(
      destination: .keyboard(key: .a, modifiers: []), behavior: .pulse, pulseDurationMs: 375
    )]
    let authored = try RuntimeProfileDraft(profile: profile).settingAdditionalActions(
      actions, for: binding.id, layerID: inLayer ? layer.id : nil
    )
    let edited: RuntimeProfileDraft
    let cliEdited: RemappingProfile
    let options = try MappingOptions([])
    if inLayer {
      edited = try authored.settingLayerBinding(
        layerID: layer.id, source: binding.source, destination: .gamepadButton(.east)
      )
      cliEdited = try MappingProfileEditor.bindingInLayer(
        in: authored.profile,
        layerID: layer.id,
        source: binding.source,
        destination: .gamepadButton(.east),
        options: options
      )
    } else {
      edited = try authored.settingDestination(.gamepadButton(.east), for: binding.id)
      cliEdited = try MappingProfileEditor.replacingBinding(
        in: authored.profile,
        source: binding.source,
        destination: .gamepadButton(.east),
        options: options
      )
    }
    let nativeBinding = inLayer ? edited.profile.layers.first?.bindings.first
      : edited.profile.bindings.first
    let cliBinding = inLayer ? cliEdited.layers.first?.bindings.first : cliEdited.bindings.first
    #expect(nativeBinding?.additionalActions == actions)
    #expect(cliBinding?.additionalActions == actions)
    #expect(edited.profile.requiresSystemInputAccess)
  }
}
