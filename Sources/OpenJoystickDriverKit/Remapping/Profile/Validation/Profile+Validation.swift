import Foundation

extension RemappingProfile {
  /// Validates the complete persistence and dispatch contract for this profile.
  ///
  /// Checks the name, the Joy-Con pair device, every stick, trigger, touch, gyro and motion
  /// setting, the application scope, the mapping count, each binding, chord, sequence and layer,
  /// and the encoded size.
  /// - Throws: ``RemappingValidationError``.
  public func validate() throws {
    try validateName()
    if joyConPair != nil,
      JoyConHalf(vendorID: device.vendorID, productID: device.productID) != .left
    {
      throw RemappingValidationError.invalidJoyConPairDevice
    }
    if pointerSpeed?.isValid == false { throw RemappingValidationError.invalidPointerSpeed }
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

    try validateMacros()
    var bindingIDs: Set<UUID> = []
    for mapping in touchMappings { try validateIdentifier(mapping.id, identifiers: &bindingIDs) }
    try validateBindings(bindings, identifiers: &bindingIDs)
    try validateChords(chords, identifiers: &bindingIDs)
    try validateSequences(sequences, identifiers: &bindingIDs)
    try validateLayers(identifiers: &bindingIDs)
    try validateRegionOverlap()

    let encodedSize: Int
    do { encodedSize = try JSONEncoder().encode(self).count } catch {
      throw RemappingValidationError.encodingFailed
    }
    guard encodedSize <= Self.maximumEncodedBytes else {
      throw RemappingValidationError.encodedSizeExceeded(encodedSize)
    }
  }

  /// Checks the bindings of one scope: unique identifiers and sources, valid sources and
  /// destinations, and each binding's rules, together with its additional actions.
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
      if let remark = binding.remark {
        guard remark.trimmingCharacters(in: .whitespacesAndNewlines) == remark,
          RemappingBinding.remarkLengthRange.contains(remark.count),
          remark.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) })
        else { throw RemappingValidationError.bindingRemarkInvalid(index: index) }
      }
      for action in binding.additionalActions {
        try validateIdentifier(action.id, identifiers: &identifiers)
        try validate(
          action.binding(source: binding.source, axisTuning: binding.axisTuning),
          at: index
        )
      }
    }
  }

  /// Records an identifier and rejects one that was already seen.
  /// - Throws: ``RemappingValidationError/duplicateBindingID(_:)``.
  private func validateIdentifier(_ id: UUID, identifiers: inout Set<UUID>) throws {
    guard identifiers.insert(id).inserted else {
      throw RemappingValidationError.duplicateBindingID(id)
    }
  }

  /// Checks the chords of one scope: window, destination, at least two discrete sources, and no
  /// repeated source set.
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
          .touchSwipe, .stickRegion, .triggerBand, .touchArea:
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

  /// Checks the sequences of one scope: destination, at least two discrete sources, window, and no
  /// repeated source order.
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
          .touchSwipe, .stickRegion, .triggerBand, .touchArea:
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

  /// Checks every layer: its motion tuning, its contents, its name, and an activator that is
  /// discrete, unique and not bound elsewhere.
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
        .touchSwipe, .stickRegion, .triggerBand, .touchArea:
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

  /// Checks that the profile name is 1 to 80 characters, has no surrounding whitespace and no
  /// control characters.
  private func validateName() throws {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed == name, Self.profileNameLengthRange.contains(name.count),
      name.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) })
    else { throw RemappingValidationError.invalidProfileName }
  }

  /// Checks the bundle identifier of an application scope.
  private func validateApplicationScope() throws {
    guard case .application(let identifiers) = applicationScope else { return }
    guard !identifiers.isEmpty else { throw RemappingValidationError.noAppIDs }
    var seen = Set<String>()
    for identifier in identifiers {
      guard Self.isValidAppID(identifier) else {
        throw RemappingValidationError.invalidAppID(identifier)
      }
      guard seen.insert(identifier).inserted else {
        throw RemappingValidationError.duplicateAppID(identifier)
      }
    }
  }

  /// Checks that a destination is supported and that virtual gamepad destinations have a virtual
  /// gamepad.
  func validateDestination(_ destination: RemappingDestination) throws {
    if case .gamepadButton(let button) = destination, !button.supportsVirtualOutput {
      throw RemappingValidationError.unsupportedGamepadButton(button)
    }
    if case .gamepadAxis(let axis) = destination, axis.isPointer {
      throw RemappingValidationError.unsupportedGamepadAxis(axis)
    }
    if case .physical(let output) = destination {
      do { try output.validate() } catch { throw RemappingValidationError.invalidPhysicalOutput }
    }
    if case .macro(let id) = destination, !macros.contains(where: { $0.id == id }) {
      throw RemappingValidationError.unknownMacro(id)
    }
    if let action = destination.invalidSystemActionName {
      throw RemappingValidationError.invalidSystemAction(action: action)
    }
    if case .layerSet(let id, _) = destination, !layers.contains(where: { $0.id == id }) {
      throw RemappingValidationError.unknownLayer(id)
    }
    if case .speak(let text, let voice) = destination {
      guard (1...Self.maximumSpeechCharacters).contains(text.unicodeScalars.count) else {
        throw RemappingValidationError.invalidSpeech(field: "text")
      }
      guard voice?.isEmpty != true else {
        throw RemappingValidationError.invalidSpeech(field: "voice")
      }
    }
    guard destination.midiFieldsAreInRange else {
      throw RemappingValidationError.invalidMIDIDestination
    }
    if destination.isVirtualGamepad, outputPolicy.virtualGamepad == .disabled {
      throw RemappingValidationError.virtualOutputRequired
    }
  }

  /// Checks that a source has what it needs: a trigger mapping for a trigger stage, motion lean
  /// tuning for a lean, a grid in range, a swipe distance in range.
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
    case .stickRegion(let region):
      guard region.isValid else { throw RemappingValidationError.invalidStickRegion }
    case .triggerBand(let band):
      guard band.isValid else { throw RemappingValidationError.invalidTriggerBand }
      guard !triggerMappings.contains(where: { $0.source == band.trigger }) else {
        throw RemappingValidationError.triggerBandWithDualStage(band.trigger)
      }
    case .touchArea(let area):
      guard area.isValid else { throw RemappingValidationError.invalidTouchArea }
    case .button, .dpad, .axis, .axisDirection, .touchContact: break
    }
  }

  /// Checks one binding: behavior, pulse duration, destinations, axis tuning, source and
  /// destination fit, turbo, long hold and multi-tap.
  private func validate(_ binding: RemappingBinding, at index: Int) throws {
    guard binding.pulseDurationMs.isFinite,
      RemappingBinding.pulseDurationRange.contains(binding.pulseDurationMs),
      binding.behavior == .pulse
        || binding.pulseDurationMs == RemappingBinding.defaultPulseDurationMs
    else { throw RemappingValidationError.bindingBehaviorConflict(index: index) }
    if binding.behavior != .hold {
      guard !binding.destination.isContinuous, binding.turbo == nil, binding.longHold == nil,
        binding.multiTap.isEmpty
      else { throw RemappingValidationError.bindingBehaviorConflict(index: index) }
    }
    if binding.destination.isSpeak, ![.hold, .tapOnPress].contains(binding.behavior) {
      throw RemappingValidationError.bindingBehaviorConflict(index: index)
    }
    if binding.destination.isProfileControl, ![.hold, .tapOnPress].contains(binding.behavior) {
      throw RemappingValidationError.bindingBehaviorConflict(index: index)
    }
    if binding.destination.isSystemTrigger,
      ![.hold, .tapOnPress, .tapOnRelease, .press].contains(binding.behavior)
    {
      throw RemappingValidationError.bindingBehaviorConflict(index: index)
    }
    try validateDestination(binding.destination)
    if let hold = binding.longHold { try validateDestination(hold.destination) }
    for tap in binding.multiTap { try validateDestination(tap.destination) }
    let isAxisSource: Bool
    switch binding.source {
    case .axis, .axisDirection: isAxisSource = true
    case .button, .dpad, .triggerStage, .motionLean, .touchContact, .touchGrid, .touchSwipe,
      .stickRegion, .triggerBand, .touchArea:
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
      guard binding.destination.isContinuous || binding.destination.isMIDIControlChange else {
        throw RemappingValidationError.incompatibleSourceAndDestination(index: index)
      }
    case .axisDirection, .triggerStage, .motionLean, .button, .dpad, .touchContact, .touchGrid,
      .touchSwipe, .stickRegion, .triggerBand, .touchArea:
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

    if binding.longHold != nil || !binding.multiTap.isEmpty {
      guard !isAxisSource else { throw RemappingValidationError.longHoldNotSupported(index: index) }
      guard !binding.destination.isContinuous else {
        throw RemappingValidationError.longHoldNotSupported(index: index)
      }
      guard binding.turbo == nil else {
        throw RemappingValidationError.turboAndActivationConflict(index: index)
      }
    }

    if let longHold = binding.longHold { try Self.validate(longHold, at: index) }

    try Self.validate(binding.multiTap, at: index)
  }

}
