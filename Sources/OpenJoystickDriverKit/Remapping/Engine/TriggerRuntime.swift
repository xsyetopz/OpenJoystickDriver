import Foundation

struct RemappingTriggerStageChange: Equatable {
  let stage: RemappingTriggerStage
  let isActive: Bool
}

struct RemappingDualStageTriggerRuntime {
  private enum Phase {
    case idle
    case pending(deadline: UInt64)
    case soft
    case quickFull
  }

  let mapping: RemappingTriggerMapping
  private var phase = Phase.idle
  private var softPhysical = false
  private var fullPhysical = false
  private var softOutput = false
  private var fullOutput = false

  init(mapping: RemappingTriggerMapping) { self.mapping = mapping }

  var deadline: UInt64? {
    guard case .pending(let deadline) = phase else { return nil }
    return deadline
  }

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

  mutating func advance(at uptime: UInt64) -> [RemappingTriggerStageChange] {
    evaluate(at: uptime)
  }

  mutating func reset() -> [RemappingTriggerStageChange] {
    phase = .idle
    softPhysical = false
    fullPhysical = false
    return setOutputs(soft: false, full: false)
  }

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
        return setOutputs(
          soft: true,
          full: mapping.mode.permitsLateFullPull && fullPhysical
        )
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

  private mutating func setOutputs(
    soft: Bool,
    full: Bool
  ) -> [RemappingTriggerStageChange] {
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

  private static func active(
    value: Double,
    threshold: Double,
    hysteresis: Double,
    wasActive: Bool
  ) -> Bool {
    wasActive ? value > max(0, threshold - hysteresis) : value >= threshold
  }
}
