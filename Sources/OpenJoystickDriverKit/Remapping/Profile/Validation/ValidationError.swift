import Foundation

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
    case .invalidStickRegion:
      "A stick region needs 0 <= inner < outer <= 1, both angles or none, hysteresis 0 to 0.25."
    case .invalidTriggerBand: "A trigger band needs 0 <= from < to <= 1 and hysteresis 0 to 0.25."
    case .invalidTouchArea: "A touch area must be nonempty and inside the surface."
    case .triggerBandWithDualStage(let trigger):
      "The \(trigger.rawValue) trigger has bands and a dual-stage mapping."
    case .overlappingRegions: "Regions of one stick, or bands of one trigger, must not overlap."
    case .invalidMotionTuning(let error): error.localizedDescription
    case .invalidGyroOutput(let error): error.localizedDescription
    case .invalidPointerSpeed: "Pointer speed scales must be finite numbers from 0 to 10."
    case .unsupportedPointerSpeedDriver:
      "The pointer speed reads a trigger or stick that the controller does not report."
    case .invalidJoyConPairDevice:
      "Joy-Con pair profiles must target a Nintendo left Joy-Con model (057e:2006 or 057e:2067)."
    case .bindingBehaviorConflict(let index):
      "Binding \(index) uses a behavior incompatible with its destination or activation settings."
    case .unsupportedGamepadButton(let button):
      "The virtual controller cannot output \(button.rawValue)."
    case .unsupportedGamepadAxis(let axis):
      "The virtual controller cannot output \(axis.rawValue)."
    case .virtualOutputRequired: "Gamepad destinations require virtual gamepad output."
    case .invalidPhysicalOutput: "A physical-controller output value is invalid."
    case .invalidProfileName: "Profile names must contain 1 through 80 printable characters."
    case .tooManyBindings(let count): "A remapping profile cannot contain \(count) bindings."
    case .duplicateBindingID(let id): "The binding identifier \(id.uuidString) is duplicated."
    case .duplicateLayerID(let id): "The layer identifier \(id.uuidString) is duplicated."
    case .duplicateSource: "Each controller source can appear in only one binding."
    case .invalidAppID(let identifier):
      "The target application bundle identifier is invalid: \(identifier)."
    case .noAppIDs: "An application target needs at least one bundle identifier."
    case .duplicateAppID(let identifier):
      "The target application bundle identifier is listed twice: \(identifier)."
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
    case .nonFiniteMultiTap(let index, let field):
      "Binding \(index) has a non-finite multi-tap \(field)."
    case .multiTapOutOfRange(let index, let field):
      "Binding \(index) has an out-of-range multi-tap \(field)."
    case .duplicateMultiTapCount(let index):
      "Binding \(index) has two multi-tap entries with the same count."
    case .turboAndActivationConflict(let index):
      "Binding \(index) cannot combine turbo with long-hold or multi-tap."
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
    case .bindingRemarkInvalid(let index): "Binding \(index) has an invalid remark."
    case .layerNameInvalid(let index): "Layer \(index) has an invalid name."
    case .layerActivatorNotDiscrete(let index):
      "Layer \(index) has a non-discrete (axis) activator."
    case .duplicateLayerActivator(let index): "Layer \(index) duplicates another layer's activator."
    case .layerActivatorAlsoBound(let index):
      "Layer \(index) activator is also bound as a regular source."
    case .tooManyMacros(let count): "A remapping profile cannot contain \(count) macros."
    case .duplicateMacroID(let id): "The macro identifier \(id.uuidString) is duplicated."
    case .duplicateMacroName(let index): "Macro \(index) repeats the name of an earlier macro."
    case .invalidMacro(let index, let field): "Macro \(index) has an invalid \(field)."
    case .invalidMacroStepDestination(let index, let step):
      "Step \(step) of macro \(index) has a destination that a macro step cannot use."
    case .macroNestingNotAllowed(let index, let step):
      "Step \(step) of macro \(index) runs a macro, which a macro step cannot do."
    case .macroRunTimeExceeded(let index, let limit):
      "Macro \(index) runs longer than the \(limit) limit."
    case .unknownMacro(let id):
      "A destination runs the macro \(id.uuidString), which does not exist."
    case .invalidSystemAction(let action): "The \(action) destination has an invalid value."
    case .unknownLayer(let id):
      "A destination sets the layer \(id.uuidString), which does not exist."
    case .unknownSwitchProfile(let id):
      "A destination switches to the profile \(id.uuidString), which does not exist."
    case .switchProfileForOtherModel(let id):
      "A destination switches to the profile \(id.uuidString), which is for another model."
    case .invalidSpeech(let field): "A Speak destination has an invalid \(field)."
    case .unknownSpeechVoice(let voice):
      "A Speak destination names the voice \(voice), which this Mac does not have."
    case .invalidMIDIDestination:
      "A MIDI destination needs a channel of 1 to 16, a note or controller of 0 to 127, and a "
        + "velocity of 1 to 127."
    case .encodingFailed: "The remapping profile could not be encoded."
    case .encodedSizeExceeded(let size):
      "The encoded remapping profile is too large (\(size) bytes)."
    }
  }
}
