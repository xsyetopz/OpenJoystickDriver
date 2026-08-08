import Foundation

public enum RemappingValidationError: Error, Equatable, LocalizedError, Sendable {
  case unsupportedSchemaVersion(Int)
  case invalidProfileName
  case tooManyBindings(Int)
  case duplicateBindingID(UUID)
  case duplicateSource(RemappingSource)
  case invalidBundleIdentifier(String)
  case axisTuningRequired(index: Int)
  case axisTuningNotApplicable(index: Int)
  case incompatibleSourceAndDestination(index: Int)
  case nonFiniteTuning(index: Int, field: String)
  case tuningOutOfRange(index: Int, field: String)
  case turboNotSupported(index: Int)
  case nonFiniteTurbo(index: Int, field: String)
  case turboOutOfRange(index: Int, field: String)
  case longHoldNotSupported(index: Int)
  case nonFiniteLongHold(index: Int, field: String)
  case longHoldOutOfRange(index: Int, field: String)
  case doubleTapNotSupported(index: Int)
  case nonFiniteDoubleTap(index: Int, field: String)
  case doubleTapOutOfRange(index: Int, field: String)
  case turboAndActivationConflict(index: Int)
  case chordTooFewSources(index: Int)
  case chordContinuousSource(index: Int)
  case chordContinuousDestination(index: Int)
  case duplicateChordSources(index: Int)
  case sequenceTooFewSources(index: Int)
  case sequenceContinuousSource(index: Int)
  case sequenceContinuousDestination(index: Int)
  case sequenceWindowOutOfRange(index: Int)
  case duplicateSequenceSources(index: Int)
  case layerNameInvalid(index: Int)
  case layerActivatorNotDiscrete(index: Int)
  case duplicateLayerActivator(index: Int)
  case layerActivatorAlsoBound(index: Int)
  case encodingFailed
  case encodedSizeExceeded(Int)

  public var errorDescription: String? {
    switch self {
    case .unsupportedSchemaVersion(let version):
      "Unsupported remapping profile schema version: \(version)."
    case .invalidProfileName: "Profile names must contain 1 through 80 printable characters."
    case .tooManyBindings(let count): "A remapping profile cannot contain \(count) bindings."
    case .duplicateBindingID(let id): "The binding identifier \(id.uuidString) is duplicated."
    case .duplicateSource: "Each controller source can appear in only one binding."
    case .invalidBundleIdentifier(let identifier):
      "The target application bundle identifier is invalid: \(identifier)."
    case .axisTuningRequired(let index): "Binding \(index) requires axis tuning."
    case .axisTuningNotApplicable(let index): "Binding \(index) cannot have axis tuning."
    case .incompatibleSourceAndDestination(let index):
      "Binding \(index) combines incompatible source and destination types."
    case .nonFiniteTuning(let index, let field): "Binding \(index) has a non-finite \(field)."
    case .tuningOutOfRange(let index, let field): "Binding \(index) has an out-of-range \(field)."
    case .turboNotSupported(let index): "Binding \(index) uses turbo with a continuous destination."
    case .nonFiniteTurbo(let index, let field): "Binding \(index) has a non-finite turbo \(field)."
    case .turboOutOfRange(let index, let field):
      "Binding \(index) has an out-of-range turbo \(field)."
    case .longHoldNotSupported(let index):
      "Binding \(index) uses long-hold with a continuous source or destination."
    case .nonFiniteLongHold(let index, let field):
      "Binding \(index) has a non-finite long-hold \(field)."
    case .longHoldOutOfRange(let index, let field):
      "Binding \(index) has an out-of-range long-hold \(field)."
    case .doubleTapNotSupported(let index):
      "Binding \(index) uses double-tap with a continuous source or destination."
    case .nonFiniteDoubleTap(let index, let field):
      "Binding \(index) has a non-finite double-tap \(field)."
    case .doubleTapOutOfRange(let index, let field):
      "Binding \(index) has an out-of-range double-tap \(field)."
    case .turboAndActivationConflict(let index):
      "Binding \(index) cannot combine turbo with long-hold or double-tap."
    case .chordTooFewSources(let index): "Chord \(index) must have at least two sources."
    case .chordContinuousSource(let index): "Chord \(index) uses a continuous (axis) source."
    case .chordContinuousDestination(let index): "Chord \(index) uses a continuous destination."
    case .duplicateChordSources(let index): "Chord \(index) duplicates another chord's source set."
    case .sequenceTooFewSources(let index): "Sequence \(index) must have at least two sources."
    case .sequenceContinuousSource(let index): "Sequence \(index) uses a continuous (axis) source."
    case .sequenceContinuousDestination(let index):
      "Sequence \(index) uses a continuous destination."
    case .sequenceWindowOutOfRange(let index): "Sequence \(index) has an out-of-range window."
    case .duplicateSequenceSources(let index):
      "Sequence \(index) duplicates another sequence's source ordering."
    case .layerNameInvalid(let index): "Layer \(index) has an invalid name."
    case .layerActivatorNotDiscrete(let index):
      "Layer \(index) has a non-discrete (axis) activator."
    case .duplicateLayerActivator(let index): "Layer \(index) duplicates another layer's activator."
    case .layerActivatorAlsoBound(let index):
      "Layer \(index) activator is also bound as a regular source."
    case .encodingFailed: "The remapping profile could not be encoded."
    case .encodedSizeExceeded(let size):
      "The encoded remapping profile is too large (\(size) bytes)."
    }
  }
}

extension RemappingProfile {
  /// Validates the complete persistence and dispatch contract for this profile.
  public func validate() throws {
    guard Self.supportedSchemaVersions.contains(schemaVersion) else {
      throw RemappingValidationError.unsupportedSchemaVersion(schemaVersion)
    }
    try validateName()
    try validateApplicationScope()
    guard bindings.count <= Self.maximumBindingCount else {
      throw RemappingValidationError.tooManyBindings(bindings.count)
    }

    var bindingIDs: Set<UUID> = []
    var sources: Set<RemappingSource> = []
    for (index, binding) in bindings.enumerated() {
      guard bindingIDs.insert(binding.id).inserted else {
        throw RemappingValidationError.duplicateBindingID(binding.id)
      }
      guard sources.insert(binding.source).inserted else {
        throw RemappingValidationError.duplicateSource(binding.source)
      }
      try validate(binding, at: index)
    }

    try validateChords()
    try validateSequences()
    try validateLayers()

    let encodedSize: Int
    do { encodedSize = try JSONEncoder().encode(self).count } catch {
      throw RemappingValidationError.encodingFailed
    }
    guard encodedSize <= Self.maximumEncodedBytes else {
      throw RemappingValidationError.encodedSizeExceeded(encodedSize)
    }
  }

  private func validateChords() throws {
    var seenSourceSets: Set<Set<RemappingSource>> = []
    for (index, chord) in chords.enumerated() {
      guard chord.sources.count >= 2 else {
        throw RemappingValidationError.chordTooFewSources(index: index)
      }
      for source in chord.sources {
        switch source {
        case .axis: throw RemappingValidationError.chordContinuousSource(index: index)
        case .button, .dpad, .axisDirection: break
        }
      }
      guard !chord.destination.isContinuous else {
        throw RemappingValidationError.chordContinuousDestination(index: index)
      }
      guard seenSourceSets.insert(chord.sources).inserted else {
        throw RemappingValidationError.duplicateChordSources(index: index)
      }
    }
  }

  private func validateSequences() throws {
    var seenSourceOrderings: [[RemappingSource]] = []
    for (index, sequence) in sequences.enumerated() {
      guard sequence.sources.count >= 2 else {
        throw RemappingValidationError.sequenceTooFewSources(index: index)
      }
      for source in sequence.sources {
        switch source {
        case .axis: throw RemappingValidationError.sequenceContinuousSource(index: index)
        case .button, .dpad, .axisDirection: break
        }
      }
      guard !sequence.destination.isContinuous else {
        throw RemappingValidationError.sequenceContinuousDestination(index: index)
      }
      guard sequence.windowMs.isFinite else {
        throw RemappingValidationError.sequenceWindowOutOfRange(index: index)
      }
      guard RemappingSequence.windowRange.contains(sequence.windowMs) else {
        throw RemappingValidationError.sequenceWindowOutOfRange(index: index)
      }
      guard !seenSourceOrderings.contains(sequence.sources) else {
        throw RemappingValidationError.duplicateSequenceSources(index: index)
      }
      seenSourceOrderings.append(sequence.sources)
    }
  }

  private func validateLayers() throws {
    var activators: Set<RemappingSource> = []
    let boundSources = Set(bindings.map(\.source))
    for (index, layer) in layers.enumerated() {
      let trimmedName = layer.name.trimmingCharacters(in: .whitespacesAndNewlines)
      guard trimmedName == layer.name, Self.layerNameLengthRange.contains(layer.name.count),
        layer.name.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) })
      else { throw RemappingValidationError.layerNameInvalid(index: index) }
      switch layer.activator {
      case .axis: throw RemappingValidationError.layerActivatorNotDiscrete(index: index)
      case .button, .dpad, .axisDirection: break
      }
      guard activators.insert(layer.activator).inserted else {
        throw RemappingValidationError.duplicateLayerActivator(index: index)
      }
      guard !boundSources.contains(layer.activator) else {
        throw RemappingValidationError.layerActivatorAlsoBound(index: index)
      }
    }
  }

  private func validateName() throws {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed == name, Self.profileNameLengthRange.contains(name.count),
      name.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) })
    else { throw RemappingValidationError.invalidProfileName }
  }

  private func validateApplicationScope() throws {
    guard case .application(let identifier) = applicationScope else { return }
    guard Self.isValidBundleIdentifier(identifier) else {
      throw RemappingValidationError.invalidBundleIdentifier(identifier)
    }
  }

  private func validate(_ binding: RemappingBinding, at index: Int) throws {
    let isAxisSource: Bool
    switch binding.source {
    case .axis, .axisDirection: isAxisSource = true
    case .button, .dpad: isAxisSource = false
    }

    if isAxisSource {
      guard let tuning = binding.axisTuning else {
        throw RemappingValidationError.axisTuningRequired(index: index)
      }
      try Self.validate(tuning, at: index)
    } else if binding.axisTuning != nil {
      throw RemappingValidationError.axisTuningNotApplicable(index: index)
    }

    switch binding.source {
    case .axis:
      guard binding.destination.isContinuous else {
        throw RemappingValidationError.incompatibleSourceAndDestination(index: index)
      }
    case .axisDirection, .button, .dpad:
      guard !binding.destination.isContinuous else {
        throw RemappingValidationError.incompatibleSourceAndDestination(index: index)
      }
    }

    if let turbo = binding.turbo {
      guard binding.destination.acceptsTurbo else {
        throw RemappingValidationError.turboNotSupported(index: index)
      }
      try Self.validate(turbo, at: index)
    }

    if binding.longHold != nil || binding.doubleTap != nil {
      guard !isAxisSource else { throw RemappingValidationError.longHoldNotSupported(index: index) }
      guard !binding.destination.isContinuous else {
        throw RemappingValidationError.longHoldNotSupported(index: index)
      }
      guard binding.turbo == nil else {
        throw RemappingValidationError.turboAndActivationConflict(index: index)
      }
    }

    if let longHold = binding.longHold { try Self.validate(longHold, at: index) }

    if let doubleTap = binding.doubleTap { try Self.validate(doubleTap, at: index) }
  }

  private static func validate(_ tuning: RemappingAxisTuning, at index: Int) throws {
    let fields = [
      ("deadzone", tuning.deadzone, RemappingAxisTuning.deadzoneRange),
      ("gain", tuning.gain, RemappingAxisTuning.gainRange),
      (
        "digital activation threshold", tuning.digitalActivationThreshold,
        RemappingAxisTuning.digitalActivationThresholdRange
      ),
    ]
    for (field, value, range) in fields {
      guard value.isFinite else {
        throw RemappingValidationError.nonFiniteTuning(index: index, field: field)
      }
      guard range.contains(value) else {
        throw RemappingValidationError.tuningOutOfRange(index: index, field: field)
      }
    }
  }

  private static func validate(_ turbo: RemappingTurbo, at index: Int) throws {
    let fields = [
      ("repeat rate", turbo.repeatRateHz, RemappingTurbo.repeatRateHzRange),
      ("duty cycle", turbo.dutyCycle, RemappingTurbo.dutyCycleRange),
    ]
    for (field, value, range) in fields {
      guard value.isFinite else {
        throw RemappingValidationError.nonFiniteTurbo(index: index, field: field)
      }
      guard range.contains(value) else {
        throw RemappingValidationError.turboOutOfRange(index: index, field: field)
      }
    }
  }

  private static func validate(_ longHold: RemappingLongHold, at index: Int) throws {
    guard longHold.durationMs.isFinite else {
      throw RemappingValidationError.nonFiniteLongHold(index: index, field: "duration")
    }
    guard RemappingLongHold.durationRange.contains(longHold.durationMs) else {
      throw RemappingValidationError.longHoldOutOfRange(index: index, field: "duration")
    }
  }

  private static func validate(_ doubleTap: RemappingDoubleTap, at index: Int) throws {
    guard doubleTap.windowMs.isFinite else {
      throw RemappingValidationError.nonFiniteDoubleTap(index: index, field: "window")
    }
    guard RemappingDoubleTap.windowRange.contains(doubleTap.windowMs) else {
      throw RemappingValidationError.doubleTapOutOfRange(index: index, field: "window")
    }
  }

  private static func isValidBundleIdentifier(_ identifier: String) -> Bool {
    guard Self.bundleIdentifierLengthRange.contains(identifier.utf8.count),
      identifier.allSatisfy({ $0.isASCII })
    else { return false }
    let components = identifier.split(separator: ".", omittingEmptySubsequences: false)
    guard components.count >= 2 else { return false }
    return components.allSatisfy { component in
      guard let first = component.first, let last = component.last,
        first.isLetter || first.isNumber, last.isLetter || last.isNumber
      else { return false }
      return component.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" }
    }
  }
}
