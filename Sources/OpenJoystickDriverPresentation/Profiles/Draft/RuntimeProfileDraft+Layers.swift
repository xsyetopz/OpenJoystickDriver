import Foundation
import OpenJoystickDriverKit

extension RuntimeProfileDraft {

  /// Returns the draft with a chord added.
  ///
  /// - Throws: ``RuntimeProfileDraftError`` when the chord breaks a profile rule.
  func addingChord(
    sources: Set<RemappingSource>,
    destination: RemappingDestination,
    mode: RemappingChordMode = .modifier,
    windowMs: Double = 50
  ) throws -> Self {
    try editing {
      try $0.addChord(sources: sources, destination: destination, mode: mode, windowMs: windowMs)
    }
  }

  /// Returns the draft without the chord.
  ///
  /// - Throws: ``RuntimeProfileDraftError/chordNotFound(_:)`` when the profile has no such chord.
  func removingChord(_ chordID: UUID) throws -> Self { try editing { try $0.removeChord(chordID) } }

  /// Returns the draft with a sequence added.
  ///
  /// - Throws: ``RuntimeProfileDraftError`` when the sequence breaks a profile rule.
  func addingSequence(
    sources: [RemappingSource],
    windowMs: Double,
    destination: RemappingDestination
  ) throws -> Self {
    try editing {
      try $0.addSequence(sources: sources, windowMs: windowMs, destination: destination)
    }
  }

  /// Returns the draft without the sequence.
  ///
  /// - Throws: ``RuntimeProfileDraftError/sequenceNotFound(_:)`` when the profile has no such
  ///   sequence.
  func removingSequence(_ sequenceID: UUID) throws -> Self {
    try editing { try $0.removeSequence(sequenceID) }
  }

  /// Returns the draft with a layer added.
  ///
  /// - Throws: ``RuntimeProfileDraftError`` when the layer breaks a profile rule.
  func addingLayer(
    name: String,
    activator: RemappingSource,
    activationMode: RemappingLayerActivation
  ) throws -> Self {
    try editing {
      try $0.addLayer(name: name, activator: activator, activationMode: activationMode)
    }
  }

  /// Returns the draft without the layer.
  ///
  /// - Throws: ``RuntimeProfileDraftError/layerNotFound(_:)`` when the profile has no such layer.
  func removingLayer(_ layerID: UUID) throws -> Self { try editing { try $0.removeLayer(layerID) } }

  /// Returns the draft with the assignment of `source` in the layer set to `destination`.
  ///
  /// Behavior, pulse duration and additional actions of an existing assignment stay.
  ///
  /// - Throws: ``RuntimeProfileDraftError`` when the layer is missing or the assignment breaks a
  ///   profile rule.
  func settingLayerBinding(
    layerID: UUID,
    source: RemappingSource,
    destination: RemappingDestination,
    axisTuning: RemappingAxisTuning? = nil,
    turbo: RemappingTurbo? = nil,
    longHold: RemappingLongHold? = nil,
    multiTap: [RemappingMultiTap] = []
  ) throws -> Self {
    try editing { profile in
      let existing = try profile.layer(layerID).bindings.first { $0.source == source }
      let binding = RemappingBinding(
        id: existing?.id ?? UUID(),
        source: source,
        destination: destination,
        behavior: existing?.behavior ?? .hold,
        pulseDurationMs: existing?.pulseDurationMs ?? RemappingBinding.defaultPulseDurationMs,
        axisTuning: axisTuning ?? Self.defaultTuning(for: source),
        turbo: turbo,
        longHold: longHold,
        multiTap: multiTap,
        additionalActions: existing?.additionalActions ?? []
      )
      try profile.setLayerBinding(binding, in: layerID)
    }
  }

  /// Returns the draft with the axis tuning of a layer assignment set.
  ///
  /// - Throws: ``RuntimeProfileDraftError`` when the layer or assignment is missing.
  func settingLayerBindingAxisTuning(
    layerID: UUID,
    bindingID: UUID,
    axisTuning: RemappingAxisTuning
  ) throws -> Self {
    try replacingLayerBinding(layerID: layerID, bindingID: bindingID) { binding in
      RemappingBinding(
        id: binding.id,
        source: binding.source,
        destination: binding.destination,
        behavior: binding.behavior,
        pulseDurationMs: binding.pulseDurationMs,
        axisTuning: axisTuning,
        turbo: binding.turbo,
        longHold: binding.longHold,
        multiTap: binding.multiTap,
        additionalActions: binding.additionalActions
      )
    }
  }

  /// Returns the draft with the behaviors of a layer assignment set.
  ///
  /// The pulse duration applies only to the pulse behavior.
  ///
  /// - Throws: ``RuntimeProfileDraftError`` when the layer or assignment is missing.
  func settingLayerBindingBehaviors(
    behavior: RemappingBindingBehavior? = nil,
    pulseDurationMs: Double? = nil,
    layerID: UUID,
    bindingID: UUID,
    turbo: RemappingTurbo?,
    longHold: RemappingLongHold?,
    multiTap: [RemappingMultiTap]
  ) throws -> Self {
    try replacingLayerBinding(layerID: layerID, bindingID: bindingID) { binding in
      RemappingBinding(
        id: binding.id,
        source: binding.source,
        destination: binding.destination,
        behavior: behavior ?? binding.behavior,
        pulseDurationMs: (behavior ?? binding.behavior) == .pulse
          ? pulseDurationMs ?? binding.pulseDurationMs : RemappingBinding.defaultPulseDurationMs,
        axisTuning: binding.axisTuning,
        turbo: turbo,
        longHold: longHold,
        multiTap: multiTap,
        additionalActions: binding.additionalActions
      )
    }
  }

  /// Returns the draft without the layer assignment.
  ///
  /// - Throws: ``RuntimeProfileDraftError`` when the layer or assignment is missing.
  func removingLayerBinding(layerID: UUID, bindingID: UUID) throws -> Self {
    try editing { profile in
      let bindings = try profile.layer(layerID).bindings
      guard bindings.contains(where: { $0.id == bindingID }) else {
        throw RuntimeProfileDraftError.bindingNotFound(bindingID)
      }
      try profile.updateLayer(layerID, bindings: bindings.filter { $0.id != bindingID })
    }
  }

  /// Returns the draft with the layer assignment replaced by `transform`.
  ///
  /// - Throws: ``RuntimeProfileDraftError`` when the layer or assignment is missing.
  func replacingLayerBinding(
    layerID: UUID,
    bindingID: UUID,
    transform: (RemappingBinding) -> RemappingBinding
  ) throws -> Self {
    try editing { profile in
      var bindings = try profile.layer(layerID).bindings
      guard let bindingIndex = bindings.firstIndex(where: { $0.id == bindingID }) else {
        throw RuntimeProfileDraftError.bindingNotFound(bindingID)
      }
      bindings[bindingIndex] = transform(bindings[bindingIndex])
      try profile.updateLayer(layerID, bindings: bindings)
    }
  }

  /// Returns the draft with the assignment replaced by the result of `makeBinding`.
  ///
  /// - Throws: ``RuntimeProfileDraftError`` when the assignment is missing or the result breaks a
  ///   profile rule.
  func replacingBinding(
    _ bindingID: UUID,
    _ makeBinding: (RemappingBinding) -> RemappingBinding
  ) throws -> Self {
    guard let index = profile.bindings.firstIndex(where: { $0.id == bindingID }) else {
      throw RuntimeProfileDraftError.bindingNotFound(bindingID)
    }
    var bindings = profile.bindings
    bindings[index] = makeBinding(bindings[index])
    return Self(profile: try Self.validate(profile.replacing(bindings: bindings)))
  }

  /// Applies `edit` to a copy of the profile and returns the draft of the copy.
  ///
  /// The errors of the shared editing map to ``RuntimeProfileDraftError``.
  ///
  /// - Throws: ``RuntimeProfileDraftError`` when the edit fails.
  func editing(_ edit: (inout RemappingProfile) throws -> Void) throws -> Self {
    var candidate = profile
    do { try edit(&candidate) } catch let error as RuntimeProfileDraftError {
      throw error
    } catch RemappingProfileEditingError.chordNotFound(let id) {
      throw RuntimeProfileDraftError.chordNotFound(id)
    } catch RemappingProfileEditingError.layerNotFound(let id) {
      throw RuntimeProfileDraftError.layerNotFound(id)
    } catch RemappingProfileEditingError.sequenceNotFound(let id) {
      throw RuntimeProfileDraftError.sequenceNotFound(id)
    } catch let error as RemappingValidationError {
      throw RuntimeProfileDraftError.validation(error)
    } catch { throw RuntimeProfileDraftError.validation(.encodingFailed) }
    return Self(profile: candidate)
  }

  /// Returns the axis tuning a source starts with: the default for an axis, nil for any other.
  static func defaultTuning(for source: RemappingSource) -> RemappingAxisTuning? {
    switch source {
    case .axis, .axisDirection: .default
    case .button, .dpad, .triggerStage, .motionLean, .touchContact, .touchGrid, .touchSwipe,
      .stickRegion, .triggerBand, .touchArea:
      nil
    }
  }
  /// Returns `profile` after validating it.
  ///
  /// - Throws: ``RuntimeProfileDraftError/validation(_:)`` when it breaks a profile rule.
  static func validate(_ profile: RemappingProfile) throws -> RemappingProfile {
    do {
      try profile.validate()
      return profile
    } catch let error as RemappingValidationError {
      throw RuntimeProfileDraftError.validation(error)
    } catch { throw RuntimeProfileDraftError.validation(.encodingFailed) }
  }
}
