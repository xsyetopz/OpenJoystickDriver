import Foundation

extension RemappingEngineState {
  /// Whether any output needs a future tick.
  var hasScheduledOutput: Bool {
    nextScheduledTick(after: 0, continuousIntervalNanoseconds: 1) != nil
  }

  /// Returns the earliest uptime at which output needs a tick, or `nil` when none does.
  ///
  /// The deadlines come from the expiry of gyro and motion stick output, trigger skip windows,
  /// held-back chord presses, pulses, turbo repeats, long-hold and double-tap timers, and the
  /// sequence history. Continuous output and sticks that need ticks use the given interval.
  func nextScheduledTick(
    after uptimeNanoseconds: UInt64,
    continuousIntervalNanoseconds: UInt64
  ) -> UInt64? {
    var deadline: UInt64?
    for device in devices.values {
      let currentUptime = max(uptimeNanoseconds, device.lastUptime)
      if let gyroDeadline = device.motion.gyroDeadline {
        deadline = min(deadline ?? gyroDeadline, gyroDeadline)
      }
      if let motionStickDeadline = device.motion.motionStickDeadline {
        deadline = min(deadline ?? motionStickDeadline, motionStickDeadline)
      }
      for trigger in device.analog.triggers.values {
        if let triggerDeadline = trigger.deadline {
          deadline = min(deadline ?? triggerDeadline, triggerDeadline)
        }
      }
      if !device.outputs.continuous.isEmpty
        || device.analog.sticks.values.contains(where: \.needsTicks)
      {
        let next = Self.saturatingAdd(currentUptime, continuousIntervalNanoseconds)
        deadline = min(deadline ?? next, next)
      }
      if let chordDeadline = device.pendingChordDeadline {
        deadline = min(deadline ?? chordDeadline, chordDeadline)
      }
      for pulseDeadline in device.outputs.pulseDeadlines.values {
        deadline = min(deadline ?? pulseDeadline, pulseDeadline)
      }
      for turbo in device.outputs.turbos.values {
        let turboDeadline = turbo.nextTransition(after: currentUptime)
        deadline = min(deadline ?? turboDeadline, turboDeadline)
      }
      for (id, tracker) in device.outputs.activations {
        guard let binding = device.actionBinding(id: id) else { continue }
        if let longHold = binding.longHold, let pressTime = tracker.pressUptime,
          tracker.firedBindingID == nil, tracker.pendingDefault, tracker.releaseUptime == nil
        {
          let holdDeadline = Self.saturatingAdd(
            pressTime,
            UInt64(longHold.durationMs * nanosecondsPerMillisecond)
          )
          deadline = min(deadline ?? holdDeadline, holdDeadline)
        }
        if let doubleTap = binding.doubleTap, let releaseTime = tracker.releaseUptime,
          tracker.pendingDefault
        {
          let windowDeadline = Self.saturatingAdd(
            releaseTime,
            UInt64(doubleTap.windowMs * nanosecondsPerMillisecond)
          )
          deadline = min(deadline ?? windowDeadline, windowDeadline)
        }
      }
      if let sequenceDeadline = device.sequenceHistoryDeadline {
        deadline = min(deadline ?? sequenceDeadline, sequenceDeadline)
      }
    }
    return deadline
  }

  /// Keyboard, modifier and pointer button outputs that are down.
  var heldOutputs: Set<RemappingHeldOutput> {
    var outputs = Set(keyReferences.keys.map(RemappingHeldOutput.key))
    outputs.formUnion(modifierReferences.keys.map(RemappingHeldOutput.modifier))
    outputs.formUnion(mouseButtonReferences.keys.map(RemappingHeldOutput.mouseButton))
    return outputs
  }

  /// Advances time-driven output to an uptime and returns the actions.
  ///
  /// Controllers advance in sorted order. Each one runs triggers, motion stick expiry, sticks, gyro
  /// expiry, chords, held-back presses, sequences, pulses, turbo repeats, long holds and double
  /// taps. Continuous output comes last, across all controllers.
  mutating func tick(at uptimeNanoseconds: UInt64) -> [RemappingEngineAction] {
    var actions: [RemappingEngineAction] = []
    for identifier in sortedLogicalControllerIDs {
      actions += advanceTriggers(for: identifier, at: uptimeNanoseconds)
      actions += expireMotionStick(for: identifier, at: uptimeNanoseconds)
      guard var device = devices[identifier] else { continue }
      let tickUptime = max(uptimeNanoseconds, device.lastUptime)
      device.lastUptime = tickUptime
      actions += device.advanceSticks(at: tickUptime)
      if let deadline = device.motion.gyroDeadline, tickUptime >= deadline {
        actions += device.clearGyroStick()
      }
      actions += processChords(for: &device)
      actions += replayPendingChordPresses(device: &device, at: tickUptime)
      actions += processSequences(for: &device, at: tickUptime)
      for bindingID in device.outputs.pulseDeadlines.keys.sorted(by: Self.uuidLessThan) {
        guard let deadline = device.outputs.pulseDeadlines[bindingID], tickUptime >= deadline else {
          continue
        }
        device.outputs.pulseDeadlines.removeValue(forKey: bindingID)
        if let destination = device.outputs.heldBindings[bindingID] {
          actions += setBinding(bindingID, destination: destination, isDown: false, device: &device)
        }
      }
      for bindingID in device.outputs.turbos.keys.sorted(by: Self.uuidLessThan) {
        guard var turbo = device.outputs.turbos[bindingID] else { continue }
        let shouldBeDown = turbo.isDown(at: tickUptime)
        if shouldBeDown != turbo.outputIsDown {
          actions += setBinding(
            bindingID,
            destination: turbo.destination,
            isDown: shouldBeDown,
            device: &device
          )
          turbo.outputIsDown = shouldBeDown
          device.outputs.turbos[bindingID] = turbo
        }
      }

      for id in device.outputs.activations.keys.sorted(by: Self.uuidLessThan) {
        guard let binding = device.actionBinding(id: id) else { continue }
        guard var tracker = device.outputs.activations[id] else { continue }

        if let longHold = binding.longHold, let pressTime = tracker.pressUptime,
          tracker.firedBindingID == nil, tracker.pendingDefault, tracker.releaseUptime == nil
        {
          let threshold = Self.saturatingAdd(
            pressTime,
            UInt64(longHold.durationMs * nanosecondsPerMillisecond)
          )
          if tickUptime >= threshold {
            tracker.firedBindingID = binding.id
            tracker.pendingDefault = false
            actions += setBinding(
              binding.id,
              destination: longHold.destination,
              isDown: true,
              device: &device
            )
          }
        }

        if let doubleTap = binding.doubleTap, let releaseTime = tracker.releaseUptime,
          tracker.pendingDefault
        {
          let windowEnd = Self.saturatingAdd(
            releaseTime,
            UInt64(doubleTap.windowMs * nanosecondsPerMillisecond)
          )
          if tickUptime >= windowEnd {
            actions += tapBinding(binding.id, destination: binding.destination, device: &device)
            tracker = RemappingActivationTracker()
          }
        }

        device.outputs.activations[id] = tracker
      }

      devices[identifier] = device
    }
    actions += continuousActions()
    return actions
  }

  /// Removes the mapping session of a controller and returns the actions that release its outputs.
  ///
  /// Held bindings and the gamepad contribution of the session are released, and continuous output
  /// that it alone drove is stopped.
  mutating func releaseController(_ identifier: LogicalControllerID) -> [RemappingEngineAction] {
    guard var device = devices[identifier] else { return [] }
    let oldContinuous = continuousTotals()
    devices.removeValue(forKey: identifier)
    var actions: [RemappingEngineAction] = []
    for bindingID in device.outputs.heldBindings.keys.sorted(by: Self.uuidLessThan) {
      guard let destination = device.outputs.heldBindings[bindingID] else { continue }
      actions += setBinding(bindingID, destination: destination, isDown: false, device: &device)
    }
    if let state = device.outputs.gamepad.drain() { actions.append(.gamepad(state, identifier)) }
    actions += stoppedContinuousActions(previous: oldContinuous)
    return actions
  }

  /// Forgets all source baselines and releases every controller.
  mutating func drain() -> [RemappingEngineAction] {
    sourceBaselines.removeAll()
    var actions: [RemappingEngineAction] = []
    for identifier in sortedLogicalControllerIDs { actions += releaseController(identifier) }
    return actions
  }

  /// Presses or releases the destination of a binding owner.
  ///
  /// Does nothing when the owner is already in that state. Gamepad buttons and d-pad directions
  /// become contributions to the virtual gamepad, physical destinations become physical actions,
  /// and keyboard and pointer button destinations go through reference counts. A release uses the
  /// destination that was pressed.
  mutating func setBinding(
    _ bindingID: UUID,
    destination: RemappingDestination,
    isDown: Bool,
    device: inout RemappingDeviceState
  ) -> [RemappingEngineAction] {
    let wasDown = device.outputs.heldBindings[bindingID] != nil
    guard wasDown != isDown else { return [] }
    let heldDestination = device.outputs.heldBindings[bindingID] ?? destination
    if isDown {
      device.outputs.heldBindings[bindingID] = destination
    } else {
      device.outputs.heldBindings.removeValue(forKey: bindingID)
    }
    let effectiveDestination = isDown ? destination : heldDestination
    let virtualContribution: RemappingGamepadState?
    switch effectiveDestination {
    case .gamepadButton(let button): virtualContribution = RemappingGamepadState(buttons: [button])
    case .gamepadDpad(let direction): virtualContribution = RemappingGamepadState(dpad: [direction])
    default: virtualContribution = nil
    }
    if let virtualContribution {
      let contribution = isDown ? virtualContribution : .neutral
      guard let state = device.outputs.gamepad.update(contribution, for: bindingID) else {
        return []
      }
      return [.gamepad(state, device.identifier)]
    }
    if case .physical(let output) = effectiveDestination {
      return [.physical(output, active: isDown, owner: bindingID, device.identifier)]
    }
    return isDown ? press(effectiveDestination) : release(effectiveDestination)
  }

  /// Presses and releases a destination at once.
  mutating func tapBinding(
    _ bindingID: UUID,
    destination: RemappingDestination,
    device: inout RemappingDeviceState
  ) -> [RemappingEngineAction] {
    setBinding(bindingID, destination: destination, isDown: true, device: &device)
      + setBinding(bindingID, destination: destination, isDown: false, device: &device)
  }

  /// Returns zero-amount actions for continuous destinations whose total went from nonzero to zero.
  func stoppedContinuousActions(
    previous: [RemappingContinuousDestination: Double]
  ) -> [RemappingEngineAction] {
    let current = continuousTotals()
    return RemappingContinuousDestination.allCases.compactMap { destination in
      guard previous[destination, default: 0] != 0, current[destination, default: 0] == 0 else {
        return nil
      }
      return .system(destination.action(amount: 0))
    }
  }

  /// Sums the continuous output of all controllers per destination, clamped to `-1...1`.
  func continuousTotals() -> [RemappingContinuousDestination: Double] {
    var totals: [RemappingContinuousDestination: Double] = [:]
    for device in devices.values {
      for output in device.outputs.continuous.values {
        totals[output.destination, default: 0] += output.amount
      }
    }
    return totals.mapValues { min(max($0, -1), 1) }
  }

  /// Presses a destination and returns the system actions it causes.
  ///
  /// A key, modifier or pointer button goes down with its first holder. Modifiers go down before
  /// the key, in a stable order.
  mutating func press(_ destination: RemappingDestination) -> [RemappingEngineAction] {
    switch destination {
    case .keyboard(let key, let modifiers):
      var actions: [RemappingEngineAction] = []
      for modifier in Self.sortedModifiers(modifiers) {
        let referenceCount = Self.increment(&modifierReferences, key: modifier)
        guard referenceCount == 1 else { continue }
        actions.append(.system(.modifierDown(modifier)))
      }
      if Self.increment(&keyReferences, key: key) == 1 { actions.append(.system(.keyDown(key))) }
      return actions
    case .mouseButton(let button):
      return Self.increment(&mouseButtonReferences, key: button) == 1
        ? [.system(.mouseButtonDown(button))] : []
    case .mouseMovement, .scroll, .gamepadButton, .gamepadDpad, .gamepadAxis, .physical: return []
    }
  }

  /// Releases a destination and returns the system actions it causes.
  ///
  /// A key, modifier or pointer button goes up with its last holder. The key goes up before the
  /// modifiers, which go up in reverse order.
  mutating func release(_ destination: RemappingDestination) -> [RemappingEngineAction] {
    switch destination {
    case .keyboard(let key, let modifiers):
      var actions: [RemappingEngineAction] = []
      if Self.decrement(&keyReferences, key: key) == 0 { actions.append(.system(.keyUp(key))) }
      for modifier in Self.sortedModifiers(modifiers).reversed() {
        let referenceCount = Self.decrement(&modifierReferences, key: modifier)
        guard referenceCount == 0 else { continue }
        actions.append(.system(.modifierUp(modifier)))
      }
      return actions
    case .mouseButton(let button):
      return Self.decrement(&mouseButtonReferences, key: button) == 0
        ? [.system(.mouseButtonUp(button))] : []
    case .mouseMovement, .scroll, .gamepadButton, .gamepadDpad, .gamepadAxis, .physical: return []
    }
  }

  /// Returns an action for each continuous destination with a nonzero total.
  private func continuousActions() -> [RemappingEngineAction] {
    let totals = continuousTotals()
    return RemappingContinuousDestination.allCases.compactMap { destination in
      let amount = totals[destination, default: 0]
      return amount == 0 ? nil : .system(destination.action(amount: amount))
    }
  }

  /// Adds a holder of a key and returns the count after adding.
  private static func increment<Key: Hashable>(_ references: inout [Key: Int], key: Key) -> Int {
    let count = references[key, default: 0] + 1
    references[key] = count
    return count
  }

  /// Removes a holder of a key, never going below zero, and returns the remaining count.
  ///
  /// A count of zero removes the entry.
  private static func decrement<Key: Hashable>(_ references: inout [Key: Int], key: Key) -> Int {
    let count = max(references[key, default: 0] - 1, 0)
    if count == 0 { references.removeValue(forKey: key) } else { references[key] = count }
    return count
  }

  /// Controller identifiers in sorted order.
  private var sortedLogicalControllerIDs: [LogicalControllerID] {
    devices.keys.sorted()
  }

  /// Returns modifiers ordered by their raw value.
  private static func sortedModifiers(
    _ modifiers: Set<RemappingKeyModifier>
  ) -> [RemappingKeyModifier] { modifiers.sorted { $0.rawValue < $1.rawValue } }

  /// Orders identifiers by their string form.
  private static func uuidLessThan(_ lhs: UUID, _ rhs: UUID) -> Bool {
    lhs.uuidString < rhs.uuidString
  }

  /// Adds two values, saturating at `UInt64.max` instead of overflowing.
  static func saturatingAdd(_ lhs: UInt64, _ rhs: UInt64) -> UInt64 {
    let (sum, overflowed) = lhs.addingReportingOverflow(rhs)
    return overflowed ? .max : sum
  }
}
