import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverPresentation

struct RuntimeProfileRemarkTests {
  private static func draft(inLayer: Bool) -> (RuntimeProfileDraft, RemappingBinding, UUID) {
    let binding = RemappingBinding(source: .button(.south), destination: .gamepadButton(.north))
    let layer = RemappingLayer(
      name: "Layer",
      activationMode: .hold,
      activator: .button(.west),
      bindings: [binding]
    )
    let profile = RemappingProfile(
      name: "Remarks",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      outputPolicy: RemappingOutputPolicy(virtualGamepad: .mapped),
      bindings: inLayer ? [] : [binding],
      layers: inLayer ? [layer] : []
    )
    return (RuntimeProfileDraft(profile: profile), binding, layer.id)
  }

  private static func remark(of draft: RuntimeProfileDraft, inLayer: Bool) -> String? {
    (inLayer ? draft.profile.layers.first?.bindings.first : draft.profile.bindings.first)?.remark
  }

  @Test(arguments: [false, true])
  func aRemarkIsSetAndCleared(inLayer: Bool) throws {
    let (draft, binding, layerID) = Self.draft(inLayer: inLayer)
    let noted = try draft.settingRemark(
      "Jump",
      for: binding.id,
      layerID: inLayer ? layerID : nil
    )
    #expect(Self.remark(of: noted, inLayer: inLayer) == "Jump")
    let cleared = try noted.settingRemark(nil, for: binding.id, layerID: inLayer ? layerID : nil)
    #expect(Self.remark(of: cleared, inLayer: inLayer) == nil)
  }

  @Test(arguments: [false, true])
  func otherEditsKeepTheRemark(inLayer: Bool) throws {
    let (draft, binding, layerID) = Self.draft(inLayer: inLayer)
    let noted = try draft.settingRemark(
      "Jump",
      for: binding.id,
      layerID: inLayer ? layerID : nil
    )
    let edited: RuntimeProfileDraft
    if inLayer {
      edited = try noted.settingLayerBindingBehaviors(
        behavior: .toggle,
        layerID: layerID,
        bindingID: binding.id,
        turbo: nil,
        longHold: nil,
        multiTap: []
      ).settingLayerBinding(
        layerID: layerID,
        source: binding.source,
        destination: .gamepadButton(.east)
      ).settingAdditionalActions([], for: binding.id, layerID: layerID)
    } else {
      edited = try noted.settingBindingBehaviors(
        behavior: .toggle,
        turbo: nil,
        longHold: nil,
        multiTap: [],
        for: binding.id
      ).settingDestination(.gamepadButton(.east), for: binding.id)
        .settingSource(.button(.north), for: binding.id)
        .settingAxisTuning(nil, for: binding.id)
        .settingAdditionalActions([], for: binding.id)
    }
    #expect(Self.remark(of: edited, inLayer: inLayer) == "Jump")
  }

  @Test
  func aRemarkOfBadFormIsRefused() throws {
    let (draft, binding, _) = Self.draft(inLayer: false)
    #expect(throws: (any Error).self) { try draft.settingRemark(" padded ", for: binding.id) }
  }
}
