public import Foundation

/// Why a profile failed ``RemappingProfile/validate()``.
///
/// Cases with an `index` name the position of the binding, chord, sequence or layer in its list.
public enum RemappingValidationError: Error, Equatable, LocalizedError, Sendable {
  /// A binding's behavior does not fit its destination, pulse duration or timed actions.
  case bindingBehaviorConflict(index: Int)
  /// The virtual gamepad cannot output this button.
  case unsupportedGamepadButton(Control)
  /// The virtual gamepad cannot output this axis.
  case unsupportedGamepadAxis(RemappingAxis)
  /// A virtual gamepad destination or stick output is used while the output policy has no virtual
  /// gamepad.
  case virtualOutputRequired
  /// A physical-controller output value is out of range.
  case invalidPhysicalOutput
  /// The motion tuning has an invalid field.
  case invalidMotionTuning(RemappingMotionTuningError)
  /// The gyro output has an invalid field.
  case invalidGyroOutput(RemappingGyroOutputError)
  /// A Joy-Con pair profile does not target a left Joy-Con model.
  case invalidJoyConPairDevice
  /// The pointer speed has a minimum or maximum scale that is not finite or not 0 to 10.
  case invalidPointerSpeed
  /// The pointer speed reads a trigger or stick that the controller does not report.
  case unsupportedPointerSpeedDriver
  /// The mapping of this stick has an invalid field.
  case invalidStickMapping(RemappingStickSource)
  /// Two mappings read this stick.
  case duplicateStickMapping(RemappingStickSource)
  /// The mapping of this trigger has an invalid field.
  case invalidTriggerMapping(RemappingTriggerSource)
  /// Two mappings read this trigger.
  case duplicateTriggerMapping(RemappingTriggerSource)
  /// A binding reads a stage of this trigger, which has no dual-stage mapping.
  case triggerStageWithoutMapping(RemappingTriggerSource)
  /// A binding reads a motion lean, but no motion tuning defines one.
  case motionLeanWithoutMapping
  /// The touch mapping of this surface has an invalid field.
  case invalidTouchMapping(RemappingTouchSurface)
  /// Two touch mappings read this surface.
  case duplicateTouchMapping(RemappingTouchSurface)
  /// A touch grid source has invalid dimensions or cell coordinates.
  case invalidTouchGrid
  /// A touch swipe source has an invalid minimum distance.
  case invalidTouchSwipe
  /// A stick region has a radius, sector or hysteresis out of range.
  case invalidStickRegion
  /// A trigger band has a pressure or hysteresis out of range.
  case invalidTriggerBand
  /// A touch area is empty or outside the surface.
  case invalidTouchArea
  /// A trigger has bands and a dual-stage mapping.
  case triggerBandWithDualStage(RemappingTriggerSource)
  /// Two regions of one stick, or two bands of one trigger, share a position.
  case overlappingRegions
  /// The profile name is empty, too long, padded with whitespace or holds control characters.
  case invalidProfileName
  /// The profile holds more mappings than the limit; the value is the count.
  case tooManyBindings(Int)
  /// Two bindings, chords, sequences, actions or touch mappings share this identifier.
  case duplicateBindingID(UUID)
  /// Two layers share this identifier.
  case duplicateLayerID(UUID)
  /// Two bindings of one scope read this source.
  case duplicateSource(RemappingSource)
  /// The application bundle identifier is not valid; the value is the identifier.
  case invalidAppID(String)
  /// An application scope lists no bundle identifier.
  case noAppIDs
  /// An application scope lists this bundle identifier more than once.
  case duplicateAppID(String)
  /// An axis source has no axis tuning.
  case axisTuningRequired(index: Int)
  /// A source that is not an axis has axis tuning.
  case axisTuningNotApplicable(index: Int)
  /// The source and destination do not fit: an axis source needs a continuous destination and any
  /// other source a discrete one.
  case incompatibleSourceAndDestination(index: Int)
  /// An axis tuning field is not finite.
  case nonFiniteTuning(index: Int, field: String)
  /// An axis tuning field is out of range.
  case tuningOutOfRange(index: Int, field: String)
  /// Turbo is set on a continuous or physical destination.
  case turboNotSupported(index: Int)
  /// A turbo field is not finite.
  case nonFiniteTurbo(index: Int, field: String)
  /// A turbo field is out of range.
  case turboOutOfRange(index: Int, field: String)
  /// A long hold is set on an axis source or a continuous destination.
  case longHoldNotSupported(index: Int)
  /// A long-hold field is not finite.
  case nonFiniteLongHold(index: Int, field: String)
  /// A long-hold field is out of range.
  case longHoldOutOfRange(index: Int, field: String)
  /// A multi-tap field is not finite.
  case nonFiniteMultiTap(index: Int, field: String)
  /// A multi-tap field is out of range.
  case multiTapOutOfRange(index: Int, field: String)
  /// Two multi-tap entries have the same count.
  case duplicateMultiTapCount(index: Int)
  /// Turbo is combined with a long hold or a multi-tap.
  case turboAndActivationConflict(index: Int)
  /// A chord window is out of range.
  case chordWindowOutOfRange(index: Int)
  /// A chord has fewer than two sources.
  case chordTooFewSources(index: Int)
  /// A chord has an axis source.
  case chordContinuousSource(index: Int)
  /// A chord has a continuous destination.
  case chordContinuousDestination(index: Int)
  /// A chord has the same source set as an earlier chord.
  case duplicateChordSources(index: Int)
  /// A sequence has fewer than two sources.
  case sequenceTooFewSources(index: Int)
  /// A sequence has an axis source.
  case sequenceContinuousSource(index: Int)
  /// A sequence has a continuous destination.
  case sequenceContinuousDestination(index: Int)
  /// A sequence window is not finite or is out of range.
  case sequenceWindowOutOfRange(index: Int)
  /// A sequence has the same source order as an earlier sequence.
  case duplicateSequenceSources(index: Int)
  /// A binding remark is empty, too long, padded with whitespace or holds control characters.
  case bindingRemarkInvalid(index: Int)
  /// A layer name is empty, too long, padded with whitespace or holds control characters.
  case layerNameInvalid(index: Int)
  /// A layer activator is an axis.
  case layerActivatorNotDiscrete(index: Int)
  /// A layer has the same activator as an earlier layer.
  case duplicateLayerActivator(index: Int)
  /// A layer activator also has a binding.
  case layerActivatorAlsoBound(index: Int)
  /// The profile holds more macros than the limit; the value is the count.
  case tooManyMacros(Int)
  /// Two macros share this identifier.
  case duplicateMacroID(UUID)
  /// The macro at this index has the same name as an earlier macro.
  case duplicateMacroName(index: Int)
  /// A field of the macro at this index is invalid or out of range; `field` is its path inside
  /// the macro, such as `steps[2].durationMs`.
  case invalidMacro(index: Int, field: String)
  /// A step of a macro has a destination that a step cannot use.
  case invalidMacroStepDestination(index: Int, step: Int)
  /// A step of a macro runs a macro.
  case macroNestingNotAllowed(index: Int, step: Int)
  /// A macro runs longer than its limit; `limit` names the limit that it exceeds.
  case macroRunTimeExceeded(index: Int, limit: String)
  /// A destination runs a macro that the profile does not hold.
  case unknownMacro(UUID)
  /// A system action destination has a value outside its limits; the value is the action name.
  case invalidSystemAction(action: String)
  /// A destination sets a layer that the profile does not hold.
  case unknownLayer(UUID)
  /// A destination switches to a profile that does not exist.
  case unknownSwitchProfile(UUID)
  /// A destination switches to a profile for another controller model.
  case switchProfileForOtherModel(UUID)
  /// A `Speak` destination has an empty or too long text or an empty voice; `field` is `text` or
  /// `voice`.
  case invalidSpeech(field: String)
  /// A `Speak` destination names a voice that this Mac does not have.
  case unknownSpeechVoice(String)
  /// A MIDI destination has a channel, note, controller or velocity out of range.
  case invalidMIDIDestination
  /// The profile could not be encoded.
  case encodingFailed
  /// The encoded profile is over the size limit; the value is its size in bytes.
  case encodedSizeExceeded(Int)

  /// Message that tells the user what to review in the profile.
  public var errorDescription: String? {
    let localized = Localization()
    return switch self {
    case .invalidStickMapping(let source):
      localized.string("ui.profileValidation.invalidStickMapping", source.rawValue)
    case .duplicateStickMapping(let source):
      localized.string("ui.profileValidation.duplicateStickMapping", source.rawValue)
    case .invalidTriggerMapping(let source):
      localized.string("ui.profileValidation.invalidTriggerMapping", source.rawValue)
    case .duplicateTriggerMapping(let source):
      localized.string("ui.profileValidation.duplicateTriggerMapping", source.rawValue)
    case .triggerStageWithoutMapping(let source):
      localized.string("ui.profileValidation.triggerStageWithoutMapping", source.rawValue)
    case .motionLeanWithoutMapping:
      localized.string("ui.profileValidation.motionLeanWithoutMapping")
    case .invalidTouchMapping(let surface):
      localized.string("ui.profileValidation.invalidTouchMapping", surface.rawValue)
    case .duplicateTouchMapping(let surface):
      localized.string("ui.profileValidation.duplicateTouchMapping", surface.rawValue)
    case .invalidTouchGrid: localized.string("ui.profileValidation.invalidTouchGrid")
    case .invalidTouchSwipe: localized.string("ui.profileValidation.invalidTouchSwipe")
    case .invalidStickRegion: localized.string("ui.profileValidation.invalidStickRegion")
    case .invalidTriggerBand: localized.string("ui.profileValidation.invalidTriggerBand")
    case .invalidTouchArea: localized.string("ui.profileValidation.invalidTouchArea")
    case .triggerBandWithDualStage(let trigger):
      localized.string("ui.profileValidation.triggerBandWithDualStage", trigger.rawValue)
    case .overlappingRegions: localized.string("ui.profileValidation.overlappingRegions")
    case .invalidMotionTuning(let error): error.localizedDescription
    case .invalidGyroOutput(let error): error.localizedDescription
    case .invalidPointerSpeed: localized.string("ui.profileValidation.invalidPointerSpeed")
    case .unsupportedPointerSpeedDriver:
      localized.string("ui.profileValidation.unsupportedPointerSpeedDriver")
    case .invalidJoyConPairDevice: localized.string("ui.profileValidation.invalidJoyConPairDevice")
    case .bindingBehaviorConflict(let index):
      localized.string("ui.profileValidation.bindingBehaviorConflict", String(index))
    case .unsupportedGamepadButton(let button):
      localized.string("ui.profileValidation.unsupportedGamepadButton", button.rawValue)
    case .unsupportedGamepadAxis(let axis):
      localized.string("ui.profileValidation.unsupportedGamepadAxis", axis.rawValue)
    case .virtualOutputRequired: localized.string("ui.profileValidation.virtualOutputRequired")
    case .invalidPhysicalOutput: localized.string("ui.profileValidation.invalidPhysicalOutput")
    case .invalidProfileName: localized.string("ui.profileValidation.invalidProfileName")
    case .tooManyBindings(let count):
      localized.plural("ui.profileValidation.tooManyBindings", count: count)
    case .duplicateBindingID(let id):
      localized.string("ui.profileValidation.duplicateBindingID", id.uuidString)
    case .duplicateLayerID(let id):
      localized.string("ui.profileValidation.duplicateLayerID", id.uuidString)
    case .duplicateSource: localized.string("ui.profileValidation.duplicateSource")
    case .invalidAppID(let identifier):
      localized.string("ui.profileValidation.invalidAppID", identifier)
    case .noAppIDs: localized.string("ui.profileValidation.noAppIDs")
    case .duplicateAppID(let identifier):
      localized.string("ui.profileValidation.duplicateAppID", identifier)
    case .axisTuningRequired(let index):
      localized.string("ui.profileValidation.axisTuningRequired", String(index))
    case .axisTuningNotApplicable(let index):
      localized.string("ui.profileValidation.axisTuningNotApplicable", String(index))
    case .incompatibleSourceAndDestination(let index):
      localized.string("ui.profileValidation.incompatibleSourceAndDestination", String(index))
    case .nonFiniteTuning(let index, let field):
      localized.string("ui.profileValidation.nonFiniteTuning", String(index), field)
    case .tuningOutOfRange(let index, let field):
      localized.string("ui.profileValidation.tuningOutOfRange", String(index), field)
    case .turboNotSupported(let index):
      localized.string("ui.profileValidation.turboNotSupported", String(index))
    case .nonFiniteTurbo(let index, let field):
      localized.string("ui.profileValidation.nonFiniteTurbo", String(index), field)
    case .turboOutOfRange(let index, let field):
      localized.string("ui.profileValidation.turboOutOfRange", String(index), field)
    case .longHoldNotSupported(let index):
      localized.string("ui.profileValidation.longHoldNotSupported", String(index))
    case .nonFiniteLongHold(let index, let field):
      localized.string("ui.profileValidation.nonFiniteLongHold", String(index), field)
    case .longHoldOutOfRange(let index, let field):
      localized.string("ui.profileValidation.longHoldOutOfRange", String(index), field)
    case .nonFiniteMultiTap(let index, let field):
      localized.string("ui.profileValidation.nonFiniteMultiTap", String(index), field)
    case .multiTapOutOfRange(let index, let field):
      localized.string("ui.profileValidation.multiTapOutOfRange", String(index), field)
    case .duplicateMultiTapCount(let index):
      localized.string("ui.profileValidation.duplicateMultiTapCount", String(index))
    case .turboAndActivationConflict(let index):
      localized.string("ui.profileValidation.turboAndActivationConflict", String(index))
    case .chordWindowOutOfRange(let index):
      localized.string("ui.profileValidation.chordWindowOutOfRange", String(index))
    case .chordTooFewSources(let index):
      localized.string("ui.profileValidation.chordTooFewSources", String(index))
    case .chordContinuousSource(let index):
      localized.string("ui.profileValidation.chordContinuousSource", String(index))
    case .chordContinuousDestination(let index):
      localized.string("ui.profileValidation.chordContinuousDestination", String(index))
    case .duplicateChordSources(let index):
      localized.string("ui.profileValidation.duplicateChordSources", String(index))
    case .sequenceTooFewSources(let index):
      localized.string("ui.profileValidation.sequenceTooFewSources", String(index))
    case .sequenceContinuousSource(let index):
      localized.string("ui.profileValidation.sequenceContinuousSource", String(index))
    case .sequenceContinuousDestination(let index):
      localized.string("ui.profileValidation.sequenceContinuousDestination", String(index))
    case .sequenceWindowOutOfRange(let index):
      localized.string("ui.profileValidation.sequenceWindowOutOfRange", String(index))
    case .duplicateSequenceSources(let index):
      localized.string("ui.profileValidation.duplicateSequenceSources", String(index))
    case .bindingRemarkInvalid(let index):
      localized.string("ui.profileValidation.bindingRemarkInvalid", String(index))
    case .layerNameInvalid(let index):
      localized.string("ui.profileValidation.layerNameInvalid", String(index))
    case .layerActivatorNotDiscrete(let index):
      localized.string("ui.profileValidation.layerActivatorNotDiscrete", String(index))
    case .duplicateLayerActivator(let index):
      localized.string("ui.profileValidation.duplicateLayerActivator", String(index))
    case .layerActivatorAlsoBound(let index):
      localized.string("ui.profileValidation.layerActivatorAlsoBound", String(index))
    case .tooManyMacros(let count):
      localized.plural("ui.profileValidation.tooManyMacros", count: count)
    case .duplicateMacroID(let id):
      localized.string("ui.profileValidation.duplicateMacroID", id.uuidString)
    case .duplicateMacroName(let index):
      localized.string("ui.profileValidation.duplicateMacroName", String(index))
    case .invalidMacro(let index, let field):
      localized.string("ui.profileValidation.invalidMacro", String(index), field)
    case .invalidMacroStepDestination(let index, let step):
      localized.string(
        "ui.profileValidation.invalidMacroStepDestination",
        String(step),
        String(index)
      )
    case .macroNestingNotAllowed(let index, let step):
      localized.string("ui.profileValidation.macroNestingNotAllowed", String(step), String(index))
    case .macroRunTimeExceeded(let index, let limit):
      localized.string("ui.profileValidation.macroRunTimeExceeded", String(index), limit)
    case .unknownMacro(let id): localized.string("ui.profileValidation.unknownMacro", id.uuidString)
    case .invalidSystemAction(let action):
      localized.string("ui.profileValidation.invalidSystemAction", action)
    case .unknownLayer(let id): localized.string("ui.profileValidation.unknownLayer", id.uuidString)
    case .unknownSwitchProfile(let id):
      localized.string("ui.profileValidation.unknownSwitchProfile", id.uuidString)
    case .switchProfileForOtherModel(let id):
      localized.string("ui.profileValidation.switchProfileForOtherModel", id.uuidString)
    case .invalidSpeech(let field): localized.string("ui.profileValidation.invalidSpeech", field)
    case .unknownSpeechVoice(let voice):
      localized.string("platform.macos.profileValidation.unknownSpeechVoice", voice)
    case .invalidMIDIDestination: localized.string("ui.profileValidation.invalidMIDIDestination")
    case .encodingFailed: localized.string("ui.profileValidation.encodingFailed")
    case .encodedSizeExceeded(let size):
      localized.plural("ui.profileValidation.encodedSizeExceeded", count: size)
    }
  }
}
