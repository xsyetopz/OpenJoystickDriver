import Foundation

public enum RemappingValidationError: Error, Equatable, LocalizedError, Sendable {
  case unsupportedSchemaVersion(Int)
  case bindingBehaviorConflict(index: Int)
  case unsupportedGamepadButton(RemappingButton)
  case virtualOutputRequired
  case invalidPhysicalOutput
  case invalidMotionTuning(RemappingMotionTuningError)
  case invalidGyroOutput(RemappingGyroOutputError)
  case invalidJoyConPairDevice
  case invalidStickMapping(RemappingStickSource)
  case duplicateStickMapping(RemappingStickSource)
  case invalidTriggerMapping(RemappingTriggerSource)
  case duplicateTriggerMapping(RemappingTriggerSource)
  case triggerStageWithoutMapping(RemappingTriggerSource)
  case motionLeanWithoutMapping
  case invalidTouchMapping(RemappingTouchSurface)
  case duplicateTouchMapping(RemappingTouchSurface)
  case invalidTouchGrid
  case invalidTouchSwipe
  case invalidProfileName
  case tooManyBindings(Int)
  case duplicateBindingID(UUID)
  case duplicateLayerID(UUID)
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
  case chordWindowOutOfRange(index: Int)
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
    case .invalidStickMapping(let source): "Review the settings for the \(source.rawValue) stick."
    case .duplicateStickMapping(let source):
      "The \(source.rawValue) stick has multiple mode mappings."
    case .invalidTriggerMapping(let source):
      "Review the settings for the \(source.rawValue) dual-stage trigger."
    case .duplicateTriggerMapping(let source):
      "The \(source.rawValue) trigger has multiple stage mappings."
    case .triggerStageWithoutMapping(let source):
      "The \(source.rawValue) trigger stage requires a dual-stage trigger mapping."
    case .motionLeanWithoutMapping: "Motion lean sources require motion lean settings."
    case .invalidTouchMapping(let surface):
      "Review the continuous mapping for the \(surface.rawValue) touch surface."
    case .duplicateTouchMapping(let surface):
      "The \(surface.rawValue) touch surface has multiple continuous mappings."
    case .invalidTouchGrid: "A touch grid source has invalid dimensions or cell coordinates."
    case .invalidTouchSwipe: "A touch swipe source has an invalid minimum distance."
    case .invalidMotionTuning(let error): error.localizedDescription
    case .invalidGyroOutput(let error): error.localizedDescription
    case .invalidJoyConPairDevice:
      "Joy-Con pair profiles must target the Nintendo left Joy-Con model (057e:2006)."
    case .bindingBehaviorConflict(let index):
      "Binding \(index) uses a behavior incompatible with its destination or activation settings."
    case .unsupportedGamepadButton(let button):
      "The virtual controller cannot output \(button.rawValue)."
    case .virtualOutputRequired: "Gamepad destinations require virtual gamepad output."
    case .invalidPhysicalOutput: "A physical-controller output value is invalid."
    case .unsupportedSchemaVersion(let version):
      "Unsupported remapping profile schema version: \(version)."
    case .invalidProfileName: "Profile names must contain 1 through 80 printable characters."
    case .tooManyBindings(let count): "A remapping profile cannot contain \(count) bindings."
    case .duplicateBindingID(let id): "The binding identifier \(id.uuidString) is duplicated."
    case .duplicateLayerID(let id): "The layer identifier \(id.uuidString) is duplicated."
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
    case .chordWindowOutOfRange(let index): "Chord \(index) has an out-of-range window."
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
    guard schemaVersion == Self.currentSchemaVersion else {
      throw RemappingValidationError.unsupportedSchemaVersion(schemaVersion)
    }
    try validateName()
    if joyConPair != nil, device != RemappingDeviceScope(vendorID: 0x057E, productID: 0x2006) {
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
    if gyroOutput.mode == .leftStick || gyroOutput.mode == .rightStick || gyroOutput.virtualMotion,
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
        case .button, .dpad, .axisDirection, .triggerStage, .motionLean, .touchContact,
          .touchGrid, .touchSwipe: break
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
        case .button, .dpad, .axisDirection, .triggerStage, .motionLean, .touchContact,
          .touchGrid, .touchSwipe: break
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
      case .button, .dpad, .axisDirection, .triggerStage, .motionLean, .touchContact,
        .touchGrid, .touchSwipe: break
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
      let hasLean = motionTuning.lean != nil
        || layers.contains { $0.motionTuning?.lean != nil }
      guard hasLean else {
        throw RemappingValidationError.motionLeanWithoutMapping
      }
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
