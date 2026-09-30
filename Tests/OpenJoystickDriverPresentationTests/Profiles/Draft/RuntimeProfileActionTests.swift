import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverPresentation

struct RuntimeProfileActionTests {
  @Test(arguments: [false, true])
  func destinationEditsPreserveAdditionalActions(inLayer: Bool) throws {
    let binding = RemappingBinding(source: .button(.south), destination: .gamepadButton(.north))
    let layer = RemappingLayer(
      name: "Layer",
      activationMode: .hold,
      activator: .button(.west),
      bindings: [binding]
    )
    let profile = RemappingProfile(
      name: "Actions",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      outputPolicy: RemappingOutputPolicy(virtualGamepad: .mapped),
      bindings: inLayer ? [] : [binding],
      layers: inLayer ? [layer] : []
    )
    let actions = [
      RemappingAction(
        destination: .keyboard(key: .a, modifiers: []),
        behavior: .pulse,
        pulseDurationMs: 375
      )
    ]
    let authored = try RuntimeProfileDraft(profile: profile).settingAdditionalActions(
      actions,
      for: binding.id,
      layerID: inLayer ? layer.id : nil
    )
    let edited: RuntimeProfileDraft
    if inLayer {
      edited = try authored.settingLayerBinding(
        layerID: layer.id,
        source: binding.source,
        destination: .gamepadButton(.east)
      )
    } else {
      edited = try authored.settingDestination(.gamepadButton(.east), for: binding.id)
    }
    let nativeBinding =
      inLayer ? edited.profile.layers.first?.bindings.first : edited.profile.bindings.first
    #expect(nativeBinding?.additionalActions == actions)
    #expect(edited.profile.requiresSystemInputAccess)
  }
}
