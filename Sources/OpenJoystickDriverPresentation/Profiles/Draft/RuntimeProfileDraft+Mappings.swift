import Foundation
import OpenJoystickDriverKit

extension RuntimeProfileDraft {
  /// Returns the draft with the motion tuning of a layer set; nil makes the layer inherit.
  ///
  /// - Throws: ``RuntimeProfileDraftError`` when the layer is missing or the tuning is invalid.
  func settingLayerMotionTuning(_ tuning: RemappingMotionTuning?, for layerID: UUID) throws -> Self
  { try editing { try $0.updateLayer(layerID, motionTuning: .some(tuning)) } }

  /// Returns the draft with the stick mappings replaced.
  ///
  /// - Throws: ``RuntimeProfileDraftError/validation(_:)`` when they break a profile rule.
  func settingStickMappings(_ mappings: [RemappingStickMapping]) throws -> Self {
    Self(profile: try Self.validate(profile.replacing(stickMappings: mappings)))
  }

  /// Returns the draft with the trigger mappings replaced.
  ///
  /// - Throws: ``RuntimeProfileDraftError/validation(_:)`` when they break a profile rule.
  func settingTriggerMappings(_ mappings: [RemappingTriggerMapping]) throws -> Self {
    Self(profile: try Self.validate(profile.replacing(triggerMappings: mappings)))
  }

  /// Returns the draft with the touch mappings replaced.
  ///
  /// - Throws: ``RuntimeProfileDraftError/validation(_:)`` when they break a profile rule.
  func settingTouchMappings(_ mappings: [RemappingTouchMapping]) throws -> Self {
    Self(profile: try Self.validate(profile.replacing(touchMappings: mappings)))
  }

  /// Returns the draft with the motion tuning, and the gyro output when one is given, replaced.
  ///
  /// - Throws: ``RuntimeProfileDraftError/validation(_:)`` when they break a profile rule.
  func settingMotionTuning(
    _ tuning: RemappingMotionTuning,
    gyroOutput: RemappingGyroOutput? = nil
  ) throws -> Self {
    Self(
      profile: try Self.validate(profile.replacing(motionTuning: tuning, gyroOutput: gyroOutput))
    )
  }

  /// Returns the draft with the destination of an assignment set.
  ///
  /// - Throws: ``RuntimeProfileDraftError`` when the assignment is missing or the result breaks a
  ///   profile rule.
  func settingDestination(_ destination: RemappingDestination, for bindingID: UUID) throws -> Self {
    try replacingBinding(bindingID) { binding in
      RemappingBinding(
        id: binding.id,
        source: binding.source,
        destination: destination,
        behavior: binding.behavior,
        pulseDurationMs: binding.pulseDurationMs,
        axisTuning: binding.axisTuning,
        turbo: binding.turbo,
        longHold: binding.longHold,
        multiTap: binding.multiTap,
        additionalActions: binding.additionalActions
      )
    }
  }

  /// Returns the draft with the source of an assignment set.
  ///
  /// An axis source keeps the axis tuning or takes the default, any other source has none, and the
  /// destination stays when it fits the source, else the first one that does is taken.
  ///
  /// - Throws: ``RuntimeProfileDraftError`` when the assignment is missing or the result breaks a
  ///   profile rule.
  func settingSource(_ source: RemappingSource, for bindingID: UUID) throws -> Self {
    try replacingBinding(bindingID) { binding in
      let tuning: RemappingAxisTuning?
      switch source {
      case .axis, .axisDirection: tuning = binding.axisTuning ?? .default
      case .button, .dpad, .triggerStage, .motionLean, .touchContact, .touchGrid, .touchSwipe:
        tuning = nil
      }
      let destination = Self.destination(for: source, preserving: binding.destination)
      return RemappingBinding(
        id: binding.id,
        source: source,
        destination: destination,
        behavior: binding.behavior,
        pulseDurationMs: binding.pulseDurationMs,
        axisTuning: tuning,
        turbo: binding.turbo,
        longHold: binding.longHold,
        multiTap: binding.multiTap,
        additionalActions: binding.additionalActions
      )
    }
  }

  /// Returns `current` when it fits `source`, else the first destination that does, else
  /// `current`.
  private static func destination(
    for source: RemappingSource,
    preserving current: RemappingDestination
  ) -> RemappingDestination {
    let options = DestinationOption.options(for: source, including: current)
    if let preserved = options.first(where: { $0.destination == current }) {
      return preserved.destination
    }
    return options.first?.destination ?? current
  }

  /// Returns the draft with the axis tuning of an assignment set.
  ///
  /// - Throws: ``RuntimeProfileDraftError`` when the assignment is missing or the result breaks a
  ///   profile rule.
  func settingAxisTuning(_ axisTuning: RemappingAxisTuning?, for bindingID: UUID) throws -> Self {
    try replacingBinding(bindingID) { binding in
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

  /// Returns the draft with the behaviors of an assignment set.
  ///
  /// The pulse duration applies only to the pulse behavior.
  ///
  /// - Throws: ``RuntimeProfileDraftError`` when the assignment is missing or the result breaks a
  ///   profile rule.
  func settingBindingBehaviors(
    behavior: RemappingBindingBehavior? = nil,
    pulseDurationMs: Double? = nil,
    turbo: RemappingTurbo?,
    longHold: RemappingLongHold?,
    multiTap: [RemappingMultiTap],
    for bindingID: UUID
  ) throws -> Self {
    try replacingBinding(bindingID) { binding in
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

  /// Returns the draft with an assignment added.
  ///
  /// An axis source takes `axisTuning` or the default.
  ///
  /// - Throws: ``RuntimeProfileDraftError/validation(_:)`` when the result breaks a profile rule.
  func addingBinding(
    source: RemappingSource,
    destination: RemappingDestination,
    axisTuning: RemappingAxisTuning? = nil
  ) throws -> Self {
    let tuning: RemappingAxisTuning?
    switch source {
    case .axis, .axisDirection: tuning = axisTuning ?? .default
    case .button, .dpad, .triggerStage, .motionLean, .touchContact, .touchGrid, .touchSwipe:
      tuning = nil
    }
    let binding = RemappingBinding(source: source, destination: destination, axisTuning: tuning)
    return Self(
      profile: try Self.validate(profile.replacing(bindings: profile.bindings + [binding]))
    )
  }

  /// Returns the draft without any binding, chord, sequence or layer, as `ojd binding clear --all`
  /// does.
  ///
  /// - Throws: ``RuntimeProfileDraftError/validation(_:)`` when the result breaks a profile rule.
  func removingAllBindings() throws -> Self {
    Self(profile: try Self.validate(profile.removingAllBindings()))
  }

  /// Returns the draft without the assignment.
  ///
  /// - Throws: ``RuntimeProfileDraftError`` when the assignment is missing or the result breaks a
  ///   profile rule.
  func removingBinding(_ bindingID: UUID) throws -> Self {
    guard profile.bindings.contains(where: { $0.id == bindingID }) else {
      throw RuntimeProfileDraftError.bindingNotFound(bindingID)
    }
    let bindings = profile.bindings.filter { $0.id != bindingID }
    return Self(profile: try Self.validate(profile.replacing(bindings: bindings)))
  }
}
