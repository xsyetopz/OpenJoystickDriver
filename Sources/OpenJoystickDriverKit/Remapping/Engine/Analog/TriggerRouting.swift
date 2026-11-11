extension RemappingEngineState {
  /// Feeds a trigger value to its dual-stage runtime and applies the stage changes as source
  /// changes.
  ///
  /// Returns no actions when the profile has no mapping for the trigger.
  mutating func processAdvancedTrigger(
    _ source: RemappingTriggerSource,
    value: Float,
    for identifier: LogicalControllerID,
    at uptime: UInt64
  ) -> [RemappingEngineAction] {
    guard var device = devices[identifier],
      let mapping = device.profile.triggerMappings.first(where: { $0.source == source })
    else { return [] }
    var runtime =
      device.analog.triggers[source] ?? RemappingDualStageTriggerRuntime(mapping: mapping)
    let changes = runtime.update(value: value, at: uptime)
    device.analog.triggers[source] = runtime
    devices[identifier] = device
    return applyTriggerChanges(changes, source: source, identifier: identifier, at: uptime)
  }

  /// Advances every trigger runtime of a controller to an uptime and applies the stage changes.
  mutating func advanceTriggers(
    for identifier: LogicalControllerID,
    at uptime: UInt64
  ) -> [RemappingEngineAction] {
    guard var device = devices[identifier] else { return [] }
    var changes: [(RemappingTriggerSource, RemappingTriggerStageChange)] = []
    for source in RemappingTriggerSource.allCases {
      guard var runtime = device.analog.triggers[source] else { continue }
      changes += runtime.advance(at: uptime).map { (source, $0) }
      device.analog.triggers[source] = runtime
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

  /// Turns stage changes of a trigger into source changes of the controller.
  private mutating func applyTriggerChanges(
    _ changes: [RemappingTriggerStageChange],
    source: RemappingTriggerSource,
    identifier: LogicalControllerID,
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
