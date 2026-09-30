import Foundation

extension RemappingProfile {
  /// Validates the complete persistence and dispatch contract for this profile.
  public func validate() throws {
    try validateName()
    if joyConPair != nil,
      JoyConHalf(vendorID: device.vendorID, productID: device.productID) != .left
    {
      throw RemappingValidationError.invalidJoyConPairDevice
    }
    var stickSources: Set<RemappingStickSource> = []
    for mapping in stickMappings {
      guard stickSources.insert(mapping.source).inserted else {
        throw RemappingValidationError.duplicateStickMapping(mapping.source)
      }
      do { try mapping.validate() } catch {
        throw RemappingValidationError.invalidStickMapping(mapping.source)
      }
    }
    var triggerSources: Set<RemappingTriggerSource> = []
    for mapping in triggerMappings {
      guard triggerSources.insert(mapping.source).inserted else {
        throw RemappingValidationError.duplicateTriggerMapping(mapping.source)
      }
      do { try mapping.validate() } catch {
        throw RemappingValidationError.invalidTriggerMapping(mapping.source)
      }
    }
    var touchSurfaces: Set<RemappingTouchSurface> = []
    for mapping in touchMappings {
      guard touchSurfaces.insert(mapping.surface).inserted else {
        throw RemappingValidationError.duplicateTouchMapping(mapping.surface)
      }
      guard mapping.pointerSensitivity.isFinite,
        RemappingTouchMapping.pointerSensitivityRange.contains(mapping.pointerSensitivity),
        mapping.stickRadius.isFinite,
        RemappingTouchMapping.stickRadiusRange.contains(mapping.stickRadius),
        mapping.deadzone.isFinite, RemappingTouchMapping.deadzoneRange.contains(mapping.deadzone)
      else { throw RemappingValidationError.invalidTouchMapping(mapping.surface) }
      if mapping.mode != .pointer, outputPolicy.virtualGamepad == .disabled {
        throw RemappingValidationError.virtualOutputRequired
      }
    }
    do { try gyroOutput.validate() } catch let error as RemappingGyroOutputError {
      throw RemappingValidationError.invalidGyroOutput(error)
    }
    if gyroOutput.mode == .leftStick || gyroOutput.mode == .rightStick,
      outputPolicy.virtualGamepad == .disabled
    {
      throw RemappingValidationError.virtualOutputRequired
    }
    if motionTuning.steering != nil || layers.contains(where: { $0.motionTuning?.steering != nil }),
      outputPolicy.virtualGamepad == .disabled
    {
      throw RemappingValidationError.virtualOutputRequired
    }
    if stickMappings.contains(where: { $0.mode == .steering }),
      outputPolicy.virtualGamepad == .disabled
    {
      throw RemappingValidationError.virtualOutputRequired
    }
    do { try motionTuning.validate() } catch let error as RemappingMotionTuningError {
      throw RemappingValidationError.invalidMotionTuning(error)
    }
    try validateApplicationScope()
    let actionCount = (bindings + layers.flatMap(\.bindings)).reduce(0) {
      $0 + $1.additionalActions.count
    }
    let mappingCount =
      bindings.count + touchMappings.count + triggerMappings.count + chords.count + sequences.count
      + actionCount
      + layers.reduce(0) { $0 + 1 + $1.bindings.count + $1.chords.count + $1.sequences.count }
    guard mappingCount <= Self.maximumBindingCount else {
      throw RemappingValidationError.tooManyBindings(mappingCount)
    }

    var bindingIDs: Set<UUID> = []
    for mapping in touchMappings { try validateIdentifier(mapping.id, identifiers: &bindingIDs) }
    try validateBindings(bindings, identifiers: &bindingIDs)
    try validateChords(chords, identifiers: &bindingIDs)
    try validateSequences(sequences, identifiers: &bindingIDs)
    try validateLayers(identifiers: &bindingIDs)

    let encodedSize: Int
    do { encodedSize = try JSONEncoder().encode(self).count } catch {
      throw RemappingValidationError.encodingFailed
    }
    guard encodedSize <= Self.maximumEncodedBytes else {
      throw RemappingValidationError.encodedSizeExceeded(encodedSize)
    }
  }

  private func validateBindings(_ bindings: [RemappingBinding], identifiers: inout Set<UUID>) throws
  {
    var sources: Set<RemappingSource> = []
    for (index, binding) in bindings.enumerated() {
      try validateIdentifier(binding.id, identifiers: &identifiers)
      try validateSource(binding.source)
      guard sources.insert(binding.source).inserted else {
        throw RemappingValidationError.duplicateSource(binding.source)
      }
      try validate(binding, at: index)
      for action in binding.additionalActions {
        try validateIdentifier(action.id, identifiers: &identifiers)
        try validate(
          action.binding(source: binding.source, axisTuning: binding.axisTuning),
          at: index
        )
      }
    }
  }

  private func validateIdentifier(_ id: UUID, identifiers: inout Set<UUID>) throws {
    guard identifiers.insert(id).inserted else {
      throw RemappingValidationError.duplicateBindingID(id)
    }
  }

  private func validateChords(_ chords: [RemappingChord], identifiers: inout Set<UUID>) throws {
    var seenSourceSets: Set<Set<RemappingSource>> = []
    for (index, chord) in chords.enumerated() {
      try validateIdentifier(chord.id, identifiers: &identifiers)
      guard chord.windowMs.isFinite, RemappingChord.windowRange.contains(chord.windowMs) else {
        throw RemappingValidationError.chordWindowOutOfRange(index: index)
      }
      try validateDestination(chord.destination)
      guard chord.sources.count >= 2 else {
        throw RemappingValidationError.chordTooFewSources(index: index)
      }
      for source in chord.sources {
        try validateSource(source)
        switch source {
        case .axis: throw RemappingValidationError.chordContinuousSource(index: index)
        case .button, .dpad, .axisDirection, .triggerStage, .motionLean, .touchContact, .touchGrid,
          .touchSwipe:
          break
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

  private func validateSequences(
    _ sequences: [RemappingSequence],
    identifiers: inout Set<UUID>
  ) throws {
    var seenSourceOrderings: [[RemappingSource]] = []
    for (index, sequence) in sequences.enumerated() {
      try validateIdentifier(sequence.id, identifiers: &identifiers)
      try validateDestination(sequence.destination)
      guard sequence.sources.count >= 2 else {
        throw RemappingValidationError.sequenceTooFewSources(index: index)
      }
      for source in sequence.sources {
        try validateSource(source)
        switch source {
        case .axis: throw RemappingValidationError.sequenceContinuousSource(index: index)
        case .button, .dpad, .axisDirection, .triggerStage, .motionLean, .touchContact, .touchGrid,
          .touchSwipe:
          break
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

  private func validateLayers(identifiers: inout Set<UUID>) throws {
    var layerIDs: Set<UUID> = []
    var activators: Set<RemappingSource> = []
    let boundSources = Set((bindings + layers.flatMap(\.bindings)).map(\.source))
    for (index, layer) in layers.enumerated() {
      if let tuning = layer.motionTuning {
        do { try tuning.validate() } catch let error as RemappingMotionTuningError {
          throw RemappingValidationError.invalidMotionTuning(error)
        }
      }
      guard layerIDs.insert(layer.id).inserted else {
        throw RemappingValidationError.duplicateLayerID(layer.id)
      }
      try validateBindings(layer.bindings, identifiers: &identifiers)
      try validateChords(layer.chords, identifiers: &identifiers)
      try validateSequences(layer.sequences, identifiers: &identifiers)
      let trimmedName = layer.name.trimmingCharacters(in: .whitespacesAndNewlines)
      guard trimmedName == layer.name, Self.layerNameLengthRange.contains(layer.name.count),
        layer.name.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) })
      else { throw RemappingValidationError.layerNameInvalid(index: index) }
      try validateSource(layer.activator)
      switch layer.activator {
      case .axis: throw RemappingValidationError.layerActivatorNotDiscrete(index: index)
      case .button, .dpad, .axisDirection, .triggerStage, .motionLean, .touchContact, .touchGrid,
        .touchSwipe:
        break
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

  private func validateDestination(_ destination: RemappingDestination) throws {
    if case .gamepadButton(let button) = destination, !button.supportsVirtualOutput {
      throw RemappingValidationError.unsupportedGamepadButton(button)
    }
    if case .physical(let output) = destination {
      do { try output.validate() } catch { throw RemappingValidationError.invalidPhysicalOutput }
    }
    if destination.isVirtualGamepad, outputPolicy.virtualGamepad == .disabled {
      throw RemappingValidationError.virtualOutputRequired
    }
  }

  private func validateSource(_ source: RemappingSource) throws {
    switch source {
    case .triggerStage(let trigger, _):
      guard triggerMappings.contains(where: { $0.source == trigger }) else {
        throw RemappingValidationError.triggerStageWithoutMapping(trigger)
      }
    case .motionLean:
      let hasLean = motionTuning.lean != nil || layers.contains { $0.motionTuning?.lean != nil }
      guard hasLean else { throw RemappingValidationError.motionLeanWithoutMapping }
    case .touchGrid(let grid):
      guard RemappingTouchGridSource.dimensionRange.contains(grid.columns),
        RemappingTouchGridSource.dimensionRange.contains(grid.rows),
        (0..<grid.columns).contains(grid.column), (0..<grid.rows).contains(grid.row)
      else { throw RemappingValidationError.invalidTouchGrid }
    case .touchSwipe(let swipe):
      guard swipe.minimumDistance.isFinite,
        RemappingTouchSwipeSource.minimumDistanceRange.contains(swipe.minimumDistance)
      else { throw RemappingValidationError.invalidTouchSwipe }
    case .button, .dpad, .axis, .axisDirection, .touchContact: break
    }
  }

  private func validate(_ binding: RemappingBinding, at index: Int) throws {
    guard binding.pulseDurationMs.isFinite,
      RemappingBinding.pulseDurationRange.contains(binding.pulseDurationMs),
      binding.behavior == .pulse
        || binding.pulseDurationMs == RemappingBinding.defaultPulseDurationMs
    else { throw RemappingValidationError.bindingBehaviorConflict(index: index) }
    if binding.behavior != .hold {
      guard !binding.destination.isContinuous, binding.turbo == nil, binding.longHold == nil,
        binding.doubleTap == nil
      else { throw RemappingValidationError.bindingBehaviorConflict(index: index) }
    }
    try validateDestination(binding.destination)
    if let hold = binding.longHold { try validateDestination(hold.destination) }
    if let tap = binding.doubleTap { try validateDestination(tap.destination) }
    let isAxisSource: Bool
    switch binding.source {
    case .axis, .axisDirection: isAxisSource = true
    case .button, .dpad, .triggerStage, .motionLean, .touchContact, .touchGrid, .touchSwipe:
      isAxisSource = false
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
    case .axisDirection, .triggerStage, .motionLean, .button, .dpad, .touchContact, .touchGrid,
      .touchSwipe:
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

}
