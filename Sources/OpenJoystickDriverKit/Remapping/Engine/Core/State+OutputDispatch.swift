import Foundation

extension RemappingEngineState {
  /// Whether any output needs a future tick.
  var hasScheduledOutput: Bool {
    nextScheduledTick(after: 0, continuousIntervalNanoseconds: 1) != nil
  }

  /// Returns the earliest uptime at which output needs a tick, or `nil` when none does.
  ///
  /// The deadlines come from the expiry of gyro and motion stick output, trigger skip windows,
  /// held-back chord presses, pulses, turbo repeats, long-hold and multi-tap timers, and the
  /// sequence history. Continuous output and sticks that need ticks use the given interval.
  func nextScheduledTick(
    after uptimeNanoseconds: UInt64,
    continuousIntervalNanoseconds: UInt64
  ) -> UInt64? {
    devices.values.compactMap { device in
      Self.scheduledDeadlines(
        of: device,
        currentUptime: max(uptimeNanoseconds, device.lastUptime),
        continuousIntervalNanoseconds: continuousIntervalNanoseconds
      ).min()
    }.min()
  }

  /// Returns every uptime at which output of `device` needs a tick.
  private static func scheduledDeadlines(
    of device: RemappingDeviceState,
    currentUptime: UInt64,
    continuousIntervalNanoseconds: UInt64
  ) -> [UInt64] {
    var deadlines = [device.motion.gyroDeadline, device.motion.motionStickDeadline].compactMap {
      $0
    }
    deadlines += device.analog.triggers.values.compactMap(\.deadline)
    if !device.outputs.continuous.isEmpty
      || device.analog.sticks.values.contains(where: \.needsTicks)
    {
      deadlines.append(saturatingAdd(currentUptime, continuousIntervalNanoseconds))
    }
    if let chordDeadline = device.pendingChordDeadline { deadlines.append(chordDeadline) }
    deadlines += device.outputs.pulseDeadlines.values
    deadlines += device.outputs.turbos.values.map { $0.nextTransition(after: currentUptime) }
    deadlines += device.outputs.macros.values.map(\.nextAt)
    for (id, tracker) in device.outputs.activations {
      guard let binding = device.actionBinding(id: id) else { continue }
      if let holdDeadline = longHoldDeadline(of: binding, tracker: tracker) {
        deadlines.append(holdDeadline)
      }
      if let windowDeadline = multiTapDeadline(of: binding, tracker: tracker) {
        deadlines.append(windowDeadline)
      }
    }
    if let sequenceDeadline = device.sequenceHistoryDeadline { deadlines.append(sequenceDeadline) }
    return deadlines
  }

  /// Returns when the long hold of `binding` fires, or `nil` while no press waits for it.
  private static func longHoldDeadline(
    of binding: RemappingBinding,
    tracker: RemappingActivationTracker
  ) -> UInt64? {
    guard let longHold = binding.longHold, let pressTime = tracker.pressUptime,
      tracker.firedBindingID == nil, tracker.pendingDefault, tracker.releaseUptime == nil
    else { return nil }
    return saturatingAdd(pressTime, UInt64(longHold.durationMs * nanosecondsPerMillisecond))
  }

  /// Returns when the multi-tap window of `binding` closes, or `nil` while no tap waits for it.
  private static func multiTapDeadline(
    of binding: RemappingBinding,
    tracker: RemappingActivationTracker
  ) -> UInt64? {
    guard !binding.multiTap.isEmpty, let releaseTime = tracker.releaseUptime,
      tracker.pendingDefault
    else { return nil }
    return saturatingAdd(
      releaseTime,
      UInt64(
        binding.multiTap.continuationWindowMs(after: tracker.tapCount) * nanosecondsPerMillisecond
      )
    )
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
  /// expiry, chords, held-back presses, sequences, pulses, turbo repeats, long holds and
  /// multi-taps. Continuous output comes last, across all controllers.
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
      actions += expirePulses(device: &device, at: tickUptime)
      actions += advanceTurbos(device: &device, at: tickUptime)
      for owner in device.outputs.macros.keys.sorted(by: Self.uuidLessThan) {
        actions += advanceMacro(owner, device: &device, at: tickUptime)
      }
      actions += advanceActivations(device: &device, at: tickUptime)
      devices[identifier] = device
    }
    actions += continuousActions()
    return actions
  }

  /// Releases each pulse binding whose pulse ended by `uptime`.
  private mutating func expirePulses(
    device: inout RemappingDeviceState,
    at uptime: UInt64
  ) -> [RemappingEngineAction] {
    var actions: [RemappingEngineAction] = []
    for bindingID in device.outputs.pulseDeadlines.keys.sorted(by: Self.uuidLessThan) {
      guard let deadline = device.outputs.pulseDeadlines[bindingID], uptime >= deadline else {
        continue
      }
      device.outputs.pulseDeadlines.removeValue(forKey: bindingID)
      if let destination = device.outputs.heldBindings[bindingID] {
        actions += setBinding(bindingID, destination: destination, isDown: false, device: &device)
      }
    }
    return actions
  }

  /// Presses or releases each turbo binding whose repeat phase changed by `uptime`.
  private mutating func advanceTurbos(
    device: inout RemappingDeviceState,
    at uptime: UInt64
  ) -> [RemappingEngineAction] {
    var actions: [RemappingEngineAction] = []
    for bindingID in device.outputs.turbos.keys.sorted(by: Self.uuidLessThan) {
      guard var turbo = device.outputs.turbos[bindingID] else { continue }
      let shouldBeDown = turbo.isDown(at: uptime)
      guard shouldBeDown != turbo.outputIsDown else { continue }
      actions += setBinding(
        bindingID,
        destination: turbo.destination,
        isDown: shouldBeDown,
        device: &device
      )
      turbo.outputIsDown = shouldBeDown
      device.outputs.turbos[bindingID] = turbo
    }
    return actions
  }

  /// Fires each long hold due by `uptime`, then resolves each multi-tap whose window closed.
  private mutating func advanceActivations(
    device: inout RemappingDeviceState,
    at uptime: UInt64
  ) -> [RemappingEngineAction] {
    var actions: [RemappingEngineAction] = []
    for id in device.outputs.activations.keys.sorted(by: Self.uuidLessThan) {
      guard let binding = device.actionBinding(id: id) else { continue }
      guard var tracker = device.outputs.activations[id] else { continue }
      if let longHold = binding.longHold,
        let threshold = Self.longHoldDeadline(of: binding, tracker: tracker), uptime >= threshold
      {
        tracker.firedBindingID = binding.id
        tracker.pendingDefault = false
        actions += setBinding(
          binding.id,
          destination: longHold.destination,
          isDown: true,
          device: &device
        )
      }
      if let windowEnd = Self.multiTapDeadline(of: binding, tracker: tracker), uptime >= windowEnd {
        actions += resolveTaps(binding, tapCount: tracker.tapCount, device: &device)
        tracker = RemappingActivationTracker()
      }
      device.outputs.activations[id] = tracker
    }
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
    var actions = stopMacros(device: &device) + stopSpeech(device: &device)
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
    if case .macro(let macroID) = effectiveDestination {
      return isDown
        ? startMacro(macroID, owner: bindingID, device: &device)
        : endMacroSource(owner: bindingID, device: &device)
    }
    if case .speak(let text, let voice) = effectiveDestination {
      guard isDown else { return [] }
      device.outputs.isSpeaking = true
      return [.speak(text, voice: voice, device.identifier)]
    }
    if effectiveDestination.isProfileControl {
      return isDown ? runProfileControl(effectiveDestination, device: &device) : []
    }
    if let midi = Self.midiMessage(effectiveDestination, isDown: isDown) { return [.midi(midi)] }
    if let virtualContribution = Self.gamepadContribution(of: effectiveDestination) {
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

  /// Returns the MIDI message that pressing or releasing `destination` sends, or `nil` for a
  /// destination that is not MIDI.
  private static func midiMessage(
    _ destination: RemappingDestination,
    isDown: Bool
  ) -> RemappingMIDIMessage? {
    switch destination {
    case .midiNote(let channel, let note, let velocity):
      if isDown {
        .noteOn(channel: channel, note: note, velocity: velocity)
      } else {
        .noteOff(channel: channel, note: note)
      }
    case .midiControlChange(let channel, let controller):
      .controlChange(
        channel: channel,
        controller: controller,
        value: isDown ? RemappingDestination.midiMaxData : 0
      )
    default: nil
    }
  }

  /// Returns the virtual gamepad state a held gamepad button or d-pad destination contributes.
  private static func gamepadContribution(
    of destination: RemappingDestination
  ) -> RemappingGamepadState? {
    switch destination {
    case .gamepadButton(let button): RemappingGamepadState(buttons: [button])
    case .gamepadDpad(let direction): RemappingGamepadState(dpad: [direction])
    default: nil
    }
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
    case .mouseMovement, .pointerPosition, .scroll, .gamepadButton, .gamepadDpad, .gamepadAxis,
      .physical, .macro, .profileSwitch, .layerSet, .pause, .speak, .midiNote,
      .midiControlChange:
      return []
    case .systemKey, .systemAction, .openApplication, .openURL, .runShortcut, .typeText:
      return destination.systemActionRequest(isDown: true).map { [.systemAction($0)] } ?? []
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
    case .mouseMovement, .pointerPosition, .scroll, .gamepadButton, .gamepadDpad, .gamepadAxis,
      .physical, .macro, .profileSwitch, .layerSet, .pause, .speak, .midiNote,
      .midiControlChange:
      return []
    case .systemKey, .systemAction, .openApplication, .openURL, .runShortcut, .typeText:
      return destination.systemActionRequest(isDown: false).map { [.systemAction($0)] } ?? []
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
  static func uuidLessThan(_ lhs: UUID, _ rhs: UUID) -> Bool {
    lhs.uuidString < rhs.uuidString
  }

  /// Adds two values, saturating at `UInt64.max` instead of overflowing.
  static func saturatingAdd(_ lhs: UInt64, _ rhs: UInt64) -> UInt64 {
    let (sum, overflowed) = lhs.addingReportingOverflow(rhs)
    return overflowed ? .max : sum
  }
}
