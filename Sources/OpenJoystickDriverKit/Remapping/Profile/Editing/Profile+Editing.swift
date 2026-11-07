import Foundation

/// Profile edits shared by the command-line editor and the profile editor draft.
///
/// Each mutating edit validates the complete result and leaves the profile unchanged when it
/// throws. Missing items throw `RemappingProfileEditingError`; invalid results throw the error
/// from `validate()`.
extension RemappingProfile {
  /// Returns a copy with the given fields replaced.
  ///
  /// A `nil` argument keeps the current value.
  ///
  /// For `physicalColor`, `joyConPair` and `pointerSpeed`, pass `.some(nil)` to clear the value. The copy is not
  /// validated.
  package func replacing(
    name: String? = nil,
    device: RemappingDeviceScope? = nil,
    applicationScope: RemappingApplicationScope? = nil,
    outputPolicy: RemappingOutputPolicy? = nil,
    physicalColor: ControllerColor?? = nil,
    motionTuning: RemappingMotionTuning? = nil,
    gyroOutput: RemappingGyroOutput? = nil,
    joyConPair: RemappingJoyConPairSettings?? = nil,
    pointerSpeed: RemappingPointerSpeed?? = nil,
    stickMappings: [RemappingStickMapping]? = nil,
    triggerMappings: [RemappingTriggerMapping]? = nil,
    touchMappings: [RemappingTouchMapping]? = nil,
    bindings: [RemappingBinding]? = nil,
    chords: [RemappingChord]? = nil,
    sequences: [RemappingSequence]? = nil,
    layers: [RemappingLayer]? = nil,
    macros: [RemappingMacro]? = nil
  ) -> Self {
    Self(
      id: id,
      name: name ?? self.name,
      device: device ?? self.device,
      applicationScope: applicationScope ?? self.applicationScope,
      outputPolicy: outputPolicy ?? self.outputPolicy,
      physicalColor: physicalColor ?? self.physicalColor,
      motionTuning: motionTuning ?? self.motionTuning,
      gyroOutput: gyroOutput ?? self.gyroOutput,
      joyConPair: joyConPair ?? self.joyConPair,
      pointerSpeed: pointerSpeed ?? self.pointerSpeed,
      stickMappings: stickMappings ?? self.stickMappings,
      triggerMappings: triggerMappings ?? self.triggerMappings,
      touchMappings: touchMappings ?? self.touchMappings,
      bindings: bindings ?? self.bindings,
      chords: chords ?? self.chords,
      sequences: sequences ?? self.sequences,
      layers: layers ?? self.layers,
      macros: macros ?? self.macros
    )
  }

  /// Returns a copy without any binding, chord, sequence or layer.
  ///
  /// Stick, trigger, touch and motion settings stay. The copy is not validated.
  package func removingAllBindings() -> Self {
    replacing(bindings: [], chords: [], sequences: [], layers: [])
  }

  /// Returns the layer with an identifier.
  /// - Throws: ``RemappingProfileEditingError/layerNotFound(_:)``.
  package func layer(_ layerID: UUID) throws -> RemappingLayer {
    guard let layer = layers.first(where: { $0.id == layerID }) else {
      throw RemappingProfileEditingError.layerNotFound(layerID)
    }
    return layer
  }

  /// Adds a chord to the profile.
  /// - Throws: the error of ``validate()`` when the result is invalid.
  package mutating func addChord(
    sources: Set<RemappingSource>,
    destination: RemappingDestination,
    mode: RemappingChordMode = .modifier,
    windowMs: Double = 50
  ) throws {
    let chord = RemappingChord(
      sources: sources,
      destination: destination,
      mode: mode,
      windowMs: windowMs
    )
    try applyValidated(replacing(chords: chords + [chord]))
  }

  /// Removes a chord from the profile.
  /// - Throws: ``RemappingProfileEditingError/chordNotFound(_:)``, or the error of ``validate()``.
  package mutating func removeChord(_ chordID: UUID) throws {
    guard chords.contains(where: { $0.id == chordID }) else {
      throw RemappingProfileEditingError.chordNotFound(chordID)
    }
    try applyValidated(replacing(chords: chords.filter { $0.id != chordID }))
  }

  /// Adds a sequence to the profile.
  /// - Throws: the error of ``validate()`` when the result is invalid.
  package mutating func addSequence(
    sources: [RemappingSource],
    windowMs: Double,
    destination: RemappingDestination
  ) throws {
    let sequence = RemappingSequence(sources: sources, windowMs: windowMs, destination: destination)
    try applyValidated(replacing(sequences: sequences + [sequence]))
  }

  /// Removes a sequence from the profile.
  /// - Throws: ``RemappingProfileEditingError/sequenceNotFound(_:)``, or the error of
  ///   ``validate()``.
  package mutating func removeSequence(_ sequenceID: UUID) throws {
    guard sequences.contains(where: { $0.id == sequenceID }) else {
      throw RemappingProfileEditingError.sequenceNotFound(sequenceID)
    }
    try applyValidated(replacing(sequences: sequences.filter { $0.id != sequenceID }))
  }

  /// Adds an empty layer to the profile.
  /// - Throws: the error of ``validate()`` when the result is invalid.
  package mutating func addLayer(
    name: String,
    activator: RemappingSource,
    activationMode: RemappingLayerActivation
  ) throws {
    let layer = RemappingLayer(name: name, activationMode: activationMode, activator: activator)
    try applyValidated(replacing(layers: layers + [layer]))
  }

  /// Removes a layer from the profile.
  /// - Throws: ``RemappingProfileEditingError/layerNotFound(_:)``, or the error of ``validate()``.
  package mutating func removeLayer(_ layerID: UUID) throws {
    guard layers.contains(where: { $0.id == layerID }) else {
      throw RemappingProfileEditingError.layerNotFound(layerID)
    }
    try applyValidated(replacing(layers: layers.filter { $0.id != layerID }))
  }

  /// Replaces a layer's bindings or motion override.
  ///
  /// A `nil` argument keeps the current value; pass `.some(nil)` as `motionTuning` to clear the
  /// override.
  /// - Throws: ``RemappingProfileEditingError/layerNotFound(_:)``, or the error of ``validate()``.
  package mutating func updateLayer(
    _ layerID: UUID,
    bindings: [RemappingBinding]? = nil,
    motionTuning: RemappingMotionTuning?? = nil
  ) throws {
    guard let index = layers.firstIndex(where: { $0.id == layerID }) else {
      throw RemappingProfileEditingError.layerNotFound(layerID)
    }
    var updatedLayers = layers
    let layer = updatedLayers[index]
    updatedLayers[index] = RemappingLayer(
      id: layer.id,
      name: layer.name,
      activationMode: layer.activationMode,
      activator: layer.activator,
      bindings: bindings ?? layer.bindings,
      chords: layer.chords,
      sequences: layer.sequences,
      motionTuning: motionTuning ?? layer.motionTuning
    )
    try applyValidated(replacing(layers: updatedLayers))
  }

  /// Puts `binding` in the layer, replacing any layer binding for the same source.
  /// - Throws: ``RemappingProfileEditingError/layerNotFound(_:)``, or the error of ``validate()``.
  package mutating func setLayerBinding(_ binding: RemappingBinding, in layerID: UUID) throws {
    let bindings = try layer(layerID).bindings.filter { $0.source != binding.source }
    try updateLayer(layerID, bindings: bindings + [binding])
  }

  /// Validates a candidate profile and adopts it only when it is valid.
  private mutating func applyValidated(_ candidate: Self) throws {
    try candidate.validate()
    self = candidate
  }
}
