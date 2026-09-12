import Foundation

private let nanosecondsPerMillisecond: Double = 1_000_000

private let nanosecondsPerSecond: Double = 1_000_000_000

extension RemappingEngineState {
  var hasScheduledOutput: Bool {
    nextScheduledTick(after: 0, continuousIntervalNanoseconds: 1) != nil
  }

  func nextScheduledTick(
    after uptimeNanoseconds: UInt64,
    continuousIntervalNanoseconds: UInt64
  ) -> UInt64? {
    var deadline: UInt64?
    for device in devices.values {
      let currentUptime = max(uptimeNanoseconds, device.lastUptime)
      if let gyroDeadline = device.gyroDeadline {
        deadline = min(deadline ?? gyroDeadline, gyroDeadline)
      }
      if let motionDeadline = device.virtualMotionDeadline {
        deadline = min(deadline ?? motionDeadline, motionDeadline)
      }
      if let motionStickDeadline = device.motionStickDeadline {
        deadline = min(deadline ?? motionStickDeadline, motionStickDeadline)
      }
      for trigger in device.triggers.values {
        if let triggerDeadline = trigger.deadline {
          deadline = min(deadline ?? triggerDeadline, triggerDeadline)
        }
      }
      if !device.continuous.isEmpty || device.sticks.values.contains(where: \.needsTicks) {
        let next = Self.saturatingAdd(currentUptime, continuousIntervalNanoseconds)
        deadline = min(deadline ?? next, next)
      }
      if let chordDeadline = device.pendingChordDeadline {
        deadline = min(deadline ?? chordDeadline, chordDeadline)
      }
      for pulseDeadline in device.pulseDeadlines.values {
        deadline = min(deadline ?? pulseDeadline, pulseDeadline)
      }
      for turbo in device.turbos.values {
        let turboDeadline = turbo.nextTransition(after: currentUptime)
        deadline = min(deadline ?? turboDeadline, turboDeadline)
      }
      for (id, tracker) in device.activations {
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

  var heldOutputs: Set<RemappingHeldOutput> {
    var outputs = Set(keyReferences.keys.map(RemappingHeldOutput.key))
    outputs.formUnion(modifierReferences.keys.map(RemappingHeldOutput.modifier))
    outputs.formUnion(mouseButtonReferences.keys.map(RemappingHeldOutput.mouseButton))
    return outputs
  }

  mutating func tick(at uptimeNanoseconds: UInt64) -> [RemappingEngineAction] {
    var actions: [RemappingEngineAction] = []
    for identifier in sortedDeviceIdentifiers {
      actions += advanceTriggers(for: identifier, at: uptimeNanoseconds)
      actions += expireMotionStick(for: identifier, at: uptimeNanoseconds)
      guard var device = devices[identifier] else { continue }
      let tickUptime = max(uptimeNanoseconds, device.lastUptime)
      device.lastUptime = tickUptime
      actions += device.advanceSticks(at: tickUptime)
      if let deadline = device.gyroDeadline, tickUptime >= deadline {
        actions += device.clearGyroStick()
      }
      if let deadline = device.virtualMotionDeadline, tickUptime >= deadline {
        actions += device.clearVirtualMotion()
      }
      actions += processChords(for: &device)
      actions += replayPendingChordPresses(device: &device, at: tickUptime)
      actions += processSequences(for: &device, at: tickUptime)
      for bindingID in device.pulseDeadlines.keys.sorted(by: Self.uuidLessThan) {
        guard let deadline = device.pulseDeadlines[bindingID], tickUptime >= deadline else {
          continue
        }
        device.pulseDeadlines.removeValue(forKey: bindingID)
        if let destination = device.heldBindings[bindingID] {
          actions += setBinding(bindingID, destination: destination, isDown: false, device: &device)
        }
      }
      for bindingID in device.turbos.keys.sorted(by: Self.uuidLessThan) {
        guard var turbo = device.turbos[bindingID] else { continue }
        let shouldBeDown = turbo.isDown(at: tickUptime)
        if shouldBeDown != turbo.outputIsDown {
          actions += setBinding(
            bindingID,
            destination: turbo.destination,
            isDown: shouldBeDown,
            device: &device
          )
          turbo.outputIsDown = shouldBeDown
          device.turbos[bindingID] = turbo
        }
      }

      for id in device.activations.keys.sorted(by: Self.uuidLessThan) {
        guard let binding = device.actionBinding(id: id) else { continue }
        guard var tracker = device.activations[id] else { continue }

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

        device.activations[id] = tracker
      }

      devices[identifier] = device
    }
    actions += continuousActions()
    return actions
  }

  mutating func releaseController(_ identifier: DeviceIdentifier) -> [RemappingEngineAction] {
    guard var device = devices[identifier] else { return [] }
    let oldContinuous = continuousTotals()
    devices.removeValue(forKey: identifier)
    var actions: [RemappingEngineAction] = []
    for bindingID in device.heldBindings.keys.sorted(by: Self.uuidLessThan) {
      guard let destination = device.heldBindings[bindingID] else { continue }
      actions += setBinding(bindingID, destination: destination, isDown: false, device: &device)
    }
    if let state = device.gamepad.drain() { actions.append(.gamepad(state, identifier)) }
    actions += device.clearVirtualMotion()
    actions += stoppedContinuousActions(previous: oldContinuous)
    return actions
  }

  mutating func drain() -> [RemappingEngineAction] {
    var actions: [RemappingEngineAction] = []
    for identifier in sortedDeviceIdentifiers { actions += releaseController(identifier) }
    return actions
  }

  mutating func setBinding(
    _ bindingID: UUID,
    destination: RemappingDestination,
    isDown: Bool,
    device: inout RemappingDeviceState
  ) -> [RemappingEngineAction] {
    let wasDown = device.heldBindings[bindingID] != nil
    guard wasDown != isDown else { return [] }
    let heldDestination = device.heldBindings[bindingID] ?? destination
    if isDown {
      device.heldBindings[bindingID] = destination
    } else {
      device.heldBindings.removeValue(forKey: bindingID)
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
      guard let state = device.gamepad.update(contribution, for: bindingID) else { return [] }
      return [.gamepad(state, device.identifier)]
    }
    if case .physical(let output) = effectiveDestination {
      return [.physical(output, active: isDown, owner: bindingID, device.identifier)]
    }
    return isDown ? press(effectiveDestination) : release(effectiveDestination)
  }

  mutating func tapBinding(
    _ bindingID: UUID,
    destination: RemappingDestination,
    device: inout RemappingDeviceState
  ) -> [RemappingEngineAction] {
    setBinding(bindingID, destination: destination, isDown: true, device: &device)
      + setBinding(bindingID, destination: destination, isDown: false, device: &device)
  }

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

  func continuousTotals() -> [RemappingContinuousDestination: Double] {
    var totals: [RemappingContinuousDestination: Double] = [:]
    for device in devices.values {
      for output in device.continuous.values {
        totals[output.destination, default: 0] += output.amount
      }
    }
    return totals.mapValues { min(max($0, -1), 1) }
  }

  private mutating func press(_ destination: RemappingDestination) -> [RemappingEngineAction] {
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

  private mutating func release(_ destination: RemappingDestination) -> [RemappingEngineAction] {
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

  private func continuousActions() -> [RemappingEngineAction] {
    let totals = continuousTotals()
    return RemappingContinuousDestination.allCases.compactMap { destination in
      let amount = totals[destination, default: 0]
      return amount == 0 ? nil : .system(destination.action(amount: amount))
    }
  }

  private static func increment<Key: Hashable>(_ references: inout [Key: Int], key: Key) -> Int {
    let count = references[key, default: 0] + 1
    references[key] = count
    return count
  }

  private static func decrement<Key: Hashable>(_ references: inout [Key: Int], key: Key) -> Int {
    let count = max(references[key, default: 0] - 1, 0)
    if count == 0 { references.removeValue(forKey: key) } else { references[key] = count }
    return count
  }

  private var sortedDeviceIdentifiers: [DeviceIdentifier] {
    devices.keys.sorted { $0.runtimeIdentifier < $1.runtimeIdentifier }
  }

  private static func sortedModifiers(
    _ modifiers: Set<RemappingKeyModifier>
  ) -> [RemappingKeyModifier] { modifiers.sorted { $0.rawValue < $1.rawValue } }

  private static func uuidLessThan(_ lhs: UUID, _ rhs: UUID) -> Bool {
    lhs.uuidString < rhs.uuidString
  }

  private static func saturatingAdd(_ lhs: UInt64, _ rhs: UInt64) -> UInt64 {
    let (sum, overflowed) = lhs.addingReportingOverflow(rhs)
    return overflowed ? .max : sum
  }
}

struct RemappingTurboOutput {
  let destination: RemappingDestination
  let configuration: RemappingTurbo
  let startedAt: UInt64
  var outputIsDown: Bool

  func isDown(at uptimeNanoseconds: UInt64) -> Bool {
    guard uptimeNanoseconds >= startedAt else { return outputIsDown }
    return (uptimeNanoseconds - startedAt) % periodNanoseconds < onDurationNanoseconds
  }

  func nextTransition(after uptimeNanoseconds: UInt64) -> UInt64 {
    guard uptimeNanoseconds >= startedAt else {
      return Self.saturatingAdd(startedAt, onDurationNanoseconds)
    }
    guard isDown(at: uptimeNanoseconds) == outputIsDown else { return uptimeNanoseconds }

    let phase = (uptimeNanoseconds - startedAt) % periodNanoseconds
    let remaining = outputIsDown ? onDurationNanoseconds - phase : periodNanoseconds - phase
    return Self.saturatingAdd(uptimeNanoseconds, remaining)
  }

  private var periodNanoseconds: UInt64 {
    max(1, UInt64((nanosecondsPerSecond / configuration.repeatRateHz).rounded()))
  }

  private var onDurationNanoseconds: UInt64 {
    max(1, UInt64((Double(periodNanoseconds) * configuration.dutyCycle).rounded()))
  }

  private static func saturatingAdd(_ lhs: UInt64, _ rhs: UInt64) -> UInt64 {
    let (sum, overflowed) = lhs.addingReportingOverflow(rhs)
    return overflowed ? .max : sum
  }
}

struct RemappingContinuousOutput {
  let destination: RemappingContinuousDestination
  let amount: Double
}

enum RemappingContinuousDestination: CaseIterable, Hashable {
  case mouseX
  case mouseY
  case scrollX
  case scrollY

  init?(_ destination: RemappingDestination) {
    switch destination {
    case .mouseMovement(.x): self = .mouseX
    case .mouseMovement(.y): self = .mouseY
    case .scroll(.x): self = .scrollX
    case .scroll(.y): self = .scrollY
    case .keyboard, .mouseButton, .gamepadButton, .gamepadDpad, .gamepadAxis, .physical:
      return nil
    }
  }

  func action(amount: Double) -> RemappingSystemInputAction {
    switch self {
    case .mouseX: .mouseMoved(axis: .x, amount: amount)
    case .mouseY: .mouseMoved(axis: .y, amount: amount)
    case .scrollX: .scrolled(axis: .x, amount: amount)
    case .scrollY: .scrolled(axis: .y, amount: amount)
    }
  }
}

enum RemappingHeldOutput: Hashable {
  case key(RemappingKeyboardKey)
  case modifier(RemappingKeyModifier)
  case mouseButton(RemappingMouseButton)

  var releaseAction: RemappingSystemInputAction {
    switch self {
    case .key(let key): .keyUp(key)
    case .modifier(let modifier): .modifierUp(modifier)
    case .mouseButton(let button): .mouseButtonUp(button)
    }
  }

  var releaseOrder: Int {
    switch self {
    case .key: 0
    case .mouseButton: 1
    case .modifier: 2
    }
  }

  var stableName: String {
    switch self {
    case .key(let key): "key:\(key.rawValue)"
    case .modifier(let modifier): "modifier:\(modifier.rawValue)"
    case .mouseButton(let button): "mouse:\(button.rawValue)"
    }
  }
}
