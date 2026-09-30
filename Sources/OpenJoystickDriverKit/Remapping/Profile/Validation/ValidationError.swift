import Foundation

public enum RemappingValidationError: Error, Equatable, LocalizedError, Sendable {
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
      "Joy-Con pair profiles must target a Nintendo left Joy-Con model (057e:2006 or 057e:2067)."
    case .bindingBehaviorConflict(let index):
      "Binding \(index) uses a behavior incompatible with its destination or activation settings."
    case .unsupportedGamepadButton(let button):
      "The virtual controller cannot output \(button.rawValue)."
    case .virtualOutputRequired: "Gamepad destinations require virtual gamepad output."
    case .invalidPhysicalOutput: "A physical-controller output value is invalid."
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
