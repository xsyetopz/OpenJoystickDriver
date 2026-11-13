import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct RemappingProfileEditingTests {
  @Test
  func replacingKeepsIdentityAndUnlistedFields() {
    let original = profile()
    let renamed = original.replacing(name: "Renamed")
    #expect(renamed.id == original.id)
    #expect(renamed.name == "Renamed")
    #expect(renamed.device == original.device)
    #expect(renamed.bindings == original.bindings)
    #expect(original.replacing() == original)
  }

  @Test
  func chordsAreAddedAndRemovedByID() throws {
    var edited = profile()
    try edited.addChord(
      sources: [.button(.east), .button(.west)],
      destination: .keyboard(key: .b, modifiers: []),
      mode: .simultaneous,
      windowMs: 375
    )
    let chord = try #require(edited.chords.first)
    #expect(chord.mode == .simultaneous)
    #expect(chord.windowMs == 375)

    try edited.removeChord(chord.id)
    #expect(edited.chords.isEmpty)
    #expect(throws: RemappingProfileEditingError.chordNotFound(chord.id)) {
      try edited.removeChord(chord.id)
    }
  }

  @Test
  func sequencesAreAddedAndRemovedByID() throws {
    var edited = profile()
    try edited.addSequence(
      sources: [.button(.north), .dpad(.up)],
      windowMs: 750,
      destination: .keyboard(key: .c, modifiers: [])
    )
    let sequence = try #require(edited.sequences.first)
    #expect(sequence.sources == [.button(.north), .dpad(.up)])

    try edited.removeSequence(sequence.id)
    #expect(edited.sequences.isEmpty)
    #expect(throws: RemappingProfileEditingError.sequenceNotFound(sequence.id)) {
      try edited.removeSequence(sequence.id)
    }
  }

  @Test
  func layersAreAddedAndRemovedByID() throws {
    var edited = profile()
    try edited.addLayer(name: "Precision", activator: .button(.leftShoulder), activationMode: .hold)
    let layer = try #require(edited.layers.first)
    #expect(layer.name == "Precision")
    #expect(layer.activationMode == .hold)
    #expect(try edited.layer(layer.id) == layer)

    try edited.removeLayer(layer.id)
    #expect(edited.layers.isEmpty)
    #expect(throws: RemappingProfileEditingError.layerNotFound(layer.id)) {
      try edited.removeLayer(layer.id)
    }
    #expect(throws: RemappingProfileEditingError.layerNotFound(layer.id)) {
      try edited.layer(layer.id)
    }
  }

  @Test
  func layerBindingReplacesBindingForSameSource() throws {
    let original = profile()
    var edited = original
    try edited.addLayer(name: "Aim", activator: .button(.east), activationMode: .hold)
    let layerID = try #require(edited.layers.first?.id)
    let first = RemappingBinding(source: .button(.south), destination: .mouseButton(.left))
    let second = RemappingBinding(source: .button(.south), destination: .mouseButton(.right))
    let other = RemappingBinding(source: .button(.north), destination: .mouseButton(.middle))

    try edited.setLayerBinding(first, in: layerID)
    try edited.setLayerBinding(other, in: layerID)
    try edited.setLayerBinding(second, in: layerID)

    #expect(edited.layers[0].bindings == [other, second])
    #expect(edited.bindings == original.bindings)
    #expect(throws: RemappingProfileEditingError.layerNotFound(first.id)) {
      try edited.setLayerBinding(first, in: first.id)
    }
  }

  @Test
  func layerMotionOverrideIsSetKeptAndCleared() throws {
    let binding = RemappingBinding(
      source: .button(.south),
      destination: .keyboard(key: .space, modifiers: [])
    )
    let layer = RemappingLayer(
      name: "Aim",
      activationMode: .hold,
      activator: .button(.east),
      bindings: [binding]
    )
    var edited = profile(layers: [layer])
    let tuning = RemappingMotionTuning(yawSensitivity: 0.5)

    try edited.updateLayer(layer.id, motionTuning: .some(tuning))
    #expect(edited.layers[0].motionTuning == tuning)
    #expect(edited.layers[0].bindings == [binding])

    try edited.updateLayer(layer.id, bindings: [])
    #expect(edited.layers[0].motionTuning == tuning)
    #expect(edited.layers[0].bindings.isEmpty)

    try edited.updateLayer(layer.id, motionTuning: .some(nil))
    #expect(edited.layers[0].motionTuning == nil)
  }

  @Test
  func invalidEditThrowsValidationErrorAndLeavesProfileUnchanged() throws {
    var edited = profile()
    try edited.addLayer(name: "Aim", activator: .button(.east), activationMode: .hold)
    let before = edited

    #expect(throws: RemappingValidationError.layerNameInvalid(index: 1)) {
      try edited.addLayer(name: " ", activator: .button(.west), activationMode: .hold)
    }
    #expect(throws: RemappingValidationError.self) {
      try edited.updateLayer(
        edited.layers[0].id,
        motionTuning: .some(RemappingMotionTuning(yawSensitivity: -1))
      )
    }
    #expect(edited == before)
  }

  private func profile(layers: [RemappingLayer] = []) -> RemappingProfile {
    RemappingProfile(
      name: "Editing",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      bindings: [
        RemappingBinding(
          source: .button(.south),
          destination: .keyboard(key: .space, modifiers: [])
        )
      ],
      layers: layers
    )
  }
}
