import Foundation

/// A change of one trigger stage.
struct RemappingTriggerStageChange: Equatable {
  /// Stage that changed.
  let stage: RemappingTriggerStage
  /// Whether the stage became active.
  let isActive: Bool
}

/// State machine of one dual-stage trigger.
struct RemappingDualStageTriggerRuntime {
  /// Where the machine is in a soft pull.
  private enum Phase {
    /// The soft stage is not pulled.
    case idle
    /// The soft stage is pulled and the skip window runs until the deadline.
    case pending(deadline: UInt64)
    /// The soft pull settled as soft.
    case soft
    /// A full pull arrived inside the skip window, so only the full stage counts.
    case quickFull
  }

  /// Mapping that the runtime follows.
  let mapping: RemappingTriggerMapping
  /// Where the machine is in a soft pull.
  private var phase = Phase.idle
  /// Whether the trigger value is past the soft threshold, with hysteresis.
  private var softPhysical = false
  /// Whether the trigger value is past the full threshold, with hysteresis.
  private var fullPhysical = false
  /// Whether the soft stage is reported active.
  private var softOutput = false
  /// Whether the full stage is reported active.
  private var fullOutput = false

  /// Creates a runtime for a mapping.
  init(mapping: RemappingTriggerMapping) { self.mapping = mapping }

  /// End of the running skip window in nanoseconds, or `nil` when none runs.
  var deadline: UInt64? {
    guard case .pending(let deadline) = phase else { return nil }
    return deadline
  }

  /// Feeds a trigger value and returns the stage changes it causes.
  ///
  /// A non-finite value, or a mapping that does not validate, resets the runtime.
  mutating func update(value: Float, at uptime: UInt64) -> [RemappingTriggerStageChange] {
    guard value.isFinite, (try? mapping.validate()) != nil else { return reset() }
    let normalized = min(1, max(0, Double(value)))
    softPhysical = Self.active(
      value: normalized,
      threshold: mapping.softThreshold,
      hysteresis: mapping.hysteresis,
      wasActive: softPhysical
    )
    fullPhysical = Self.active(
      value: normalized,
      threshold: mapping.fullThreshold,
      hysteresis: mapping.hysteresis,
      wasActive: fullPhysical
    )
    return evaluate(at: uptime)
  }

  /// Re-evaluates at a later uptime, so that an ended skip window settles the stages.
  mutating func advance(at uptime: UInt64) -> [RemappingTriggerStageChange] { evaluate(at: uptime) }

  /// Returns to idle and returns the changes that release the active stages.
  mutating func reset() -> [RemappingTriggerStageChange] {
    phase = .idle
    softPhysical = false
    fullPhysical = false
    return setOutputs(soft: false, full: false)
  }

  /// Derives the reported stages from the physical stages, the mode and the skip window.
  private mutating func evaluate(at uptime: UInt64) -> [RemappingTriggerStageChange] {
    guard mapping.mode.buffersSoftPull else {
      phase = softPhysical ? .soft : .idle
      let soft = softPhysical && (mapping.mode != .exclusive || !fullPhysical)
      return setOutputs(soft: soft, full: fullPhysical)
    }

    switch phase {
    case .idle:
      guard softPhysical else { return setOutputs(soft: false, full: false) }
      let window = UInt64((mapping.skipWindowMs * 1_000_000).rounded())
      let (deadline, overflow) = uptime.addingReportingOverflow(window)
      phase = .pending(deadline: overflow ? .max : deadline)
      return setOutputs(soft: mapping.mode.emitsSoftWhileBuffered, full: false)
    case .pending(let deadline):
      guard softPhysical else {
        phase = .idle
        return setOutputs(soft: false, full: false)
      }
      if fullPhysical, uptime <= deadline {
        phase = .quickFull
        return setOutputs(soft: false, full: true)
      }
      if uptime >= deadline {
        phase = .soft
        return setOutputs(soft: true, full: mapping.mode.permitsLateFullPull && fullPhysical)
      }
      return setOutputs(soft: mapping.mode.emitsSoftWhileBuffered, full: false)
    case .soft:
      guard softPhysical else {
        phase = .idle
        return setOutputs(soft: false, full: false)
      }
      return setOutputs(soft: true, full: mapping.mode.permitsLateFullPull && fullPhysical)
    case .quickFull:
      guard softPhysical else {
        phase = .idle
        return setOutputs(soft: false, full: false)
      }
      return setOutputs(soft: false, full: fullPhysical)
    }
  }

  /// Sets the reported stages and returns their changes, with all releases before the presses.
  private mutating func setOutputs(soft: Bool, full: Bool) -> [RemappingTriggerStageChange] {
    var changes: [RemappingTriggerStageChange] = []
    for (stage, current, next) in [
      (RemappingTriggerStage.soft, softOutput, soft),
      (RemappingTriggerStage.full, fullOutput, full),
    ] where current && !next {
      changes.append(RemappingTriggerStageChange(stage: stage, isActive: false))
    }
    for (stage, current, next) in [
      (RemappingTriggerStage.soft, softOutput, soft),
      (RemappingTriggerStage.full, fullOutput, full),
    ] where !current && next {
      changes.append(RemappingTriggerStageChange(stage: stage, isActive: true))
    }
    softOutput = soft
    fullOutput = full
    return changes
  }

  /// Whether a stage is active.
  ///
  /// A value at or above the threshold activates it. Once active, it stays active while the value
  /// is above the threshold minus the hysteresis.
  private static func active(
    value: Double,
    threshold: Double,
    hysteresis: Double,
    wasActive: Bool
  ) -> Bool { wasActive ? value > max(0, threshold - hysteresis) : value >= threshold }
}
