extension RemappingEngineState {
  mutating func processAdvancedTrigger(
    _ source: RemappingTriggerSource,
    value: Float,
    for identifier: DeviceIdentifier,
    at uptime: UInt64
  ) -> [RemappingEngineAction] {
    guard var device = devices[identifier],
      let mapping = device.profile.triggerMappings.first(where: { $0.source == source })
    else { return [] }
    var runtime = device.triggers[source] ?? RemappingDualStageTriggerRuntime(mapping: mapping)
    let changes = runtime.update(value: value, at: uptime)
    device.triggers[source] = runtime
    devices[identifier] = device
    return applyTriggerChanges(changes, source: source, identifier: identifier, at: uptime)
  }

  mutating func advanceTriggers(
    for identifier: DeviceIdentifier,
    at uptime: UInt64
  ) -> [RemappingEngineAction] {
    guard var device = devices[identifier] else { return [] }
    var changes: [(RemappingTriggerSource, RemappingTriggerStageChange)] = []
    for source in RemappingTriggerSource.allCases {
      guard var runtime = device.triggers[source] else { continue }
      changes += runtime.advance(at: uptime).map { (source, $0) }
      device.triggers[source] = runtime
    }
    devices[identifier] = device
    var actions: [RemappingEngineAction] = []
    for (source, change) in changes {
      actions += setSource(
        .triggerStage(source, change.stage),
        isActive: change.isActive,
        for: identifier,
        at: uptime
      )
    }
    return actions
  }

  private mutating func applyTriggerChanges(
    _ changes: [RemappingTriggerStageChange],
    source: RemappingTriggerSource,
    identifier: DeviceIdentifier,
    at uptime: UInt64
  ) -> [RemappingEngineAction] {
    var actions: [RemappingEngineAction] = []
    for change in changes {
      actions += setSource(
        .triggerStage(source, change.stage),
        isActive: change.isActive,
        for: identifier,
        at: uptime
      )
    }
    return actions
  }
}
