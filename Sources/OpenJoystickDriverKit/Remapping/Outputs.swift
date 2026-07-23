import Foundation

extension RemappingEngineState {
  var hasScheduledOutput: Bool {
    devices.values.contains { device in
      !device.turbos.isEmpty || !device.continuous.isEmpty
    }
  }

  func nextScheduledTick(
    after uptimeNanoseconds: UInt64,
    continuousIntervalNanoseconds: UInt64
  ) -> UInt64? {
    var deadline: UInt64?
    if devices.values.contains(where: { !$0.continuous.isEmpty }) {
      deadline = Self.saturatingAdd(
        uptimeNanoseconds,
        continuousIntervalNanoseconds
      )
    }
    for device in devices.values {
      for turbo in device.turbos.values {
        let turboDeadline = turbo.nextTransition(after: uptimeNanoseconds)
        deadline = min(deadline ?? turboDeadline, turboDeadline)
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

  mutating func tick(at uptimeNanoseconds: UInt64) -> [RemappingSystemInputAction] {
    var actions: [RemappingSystemInputAction] = []
    for identifier in sortedDeviceIdentifiers {
      guard var device = devices[identifier] else { continue }
      for bindingID in device.turbos.keys.sorted(by: Self.uuidLessThan) {
        guard var turbo = device.turbos[bindingID] else { continue }
        let shouldBeDown = turbo.isDown(at: uptimeNanoseconds)
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
      devices[identifier] = device
    }
    actions += continuousActions()
    return actions
  }

  mutating func releaseController(
    _ identifier: DeviceIdentifier
  ) -> [RemappingSystemInputAction] {
    guard var device = devices[identifier] else { return [] }
    let oldContinuous = continuousTotals()
    devices.removeValue(forKey: identifier)
    var actions: [RemappingSystemInputAction] = []
    for bindingID in device.heldBindings.keys.sorted(by: Self.uuidLessThan) {
      guard let destination = device.heldBindings[bindingID] else { continue }
      actions += setBinding(
        bindingID,
        destination: destination,
        isDown: false,
        device: &device
      )
    }
    actions += stoppedContinuousActions(previous: oldContinuous)
    return actions
  }

  mutating func drain() -> [RemappingSystemInputAction] {
    var actions: [RemappingSystemInputAction] = []
    for identifier in sortedDeviceIdentifiers {
      actions += releaseController(identifier)
    }
    return actions
  }

  mutating func setBinding(
    _ bindingID: UUID,
    destination: RemappingDestination,
    isDown: Bool,
    device: inout RemappingDeviceState
  ) -> [RemappingSystemInputAction] {
    let wasDown = device.heldBindings[bindingID] != nil
    guard wasDown != isDown else { return [] }
    if isDown {
      device.heldBindings[bindingID] = destination
      return press(destination)
    }
    device.heldBindings.removeValue(forKey: bindingID)
    return release(destination)
  }

  func stoppedContinuousActions(
    previous: [RemappingContinuousDestination: Double]
  ) -> [RemappingSystemInputAction] {
    let current = continuousTotals()
    return RemappingContinuousDestination.allCases.compactMap { destination in
      guard previous[destination, default: 0] != 0,
        current[destination, default: 0] == 0
      else { return nil }
      return destination.action(amount: 0)
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

  private mutating func press(
    _ destination: RemappingDestination
  ) -> [RemappingSystemInputAction] {
    switch destination {
    case .keyboard(let key, let modifiers):
      var actions: [RemappingSystemInputAction] = []
      for modifier in Self.sortedModifiers(modifiers) {
        let referenceCount = Self.increment(&modifierReferences, key: modifier)
        guard referenceCount == 1 else { continue }
        actions.append(.modifierDown(modifier))
      }
      if Self.increment(&keyReferences, key: key) == 1 {
        actions.append(.keyDown(key))
      }
      return actions
    case .mouseButton(let button):
      return Self.increment(&mouseButtonReferences, key: button) == 1
        ? [.mouseButtonDown(button)] : []
    case .mouseMovement, .scroll:
      return []
    }
  }

  private mutating func release(
    _ destination: RemappingDestination
  ) -> [RemappingSystemInputAction] {
    switch destination {
    case .keyboard(let key, let modifiers):
      var actions: [RemappingSystemInputAction] = []
      if Self.decrement(&keyReferences, key: key) == 0 {
        actions.append(.keyUp(key))
      }
      for modifier in Self.sortedModifiers(modifiers).reversed() {
        let referenceCount = Self.decrement(&modifierReferences, key: modifier)
        guard referenceCount == 0 else { continue }
        actions.append(.modifierUp(modifier))
      }
      return actions
    case .mouseButton(let button):
      return Self.decrement(&mouseButtonReferences, key: button) == 0
        ? [.mouseButtonUp(button)] : []
    case .mouseMovement, .scroll:
      return []
    }
  }

  private func continuousActions() -> [RemappingSystemInputAction] {
    let totals = continuousTotals()
    return RemappingContinuousDestination.allCases.compactMap { destination in
      let amount = totals[destination, default: 0]
      return amount == 0 ? nil : destination.action(amount: amount)
    }
  }

  private static func increment<Key: Hashable>(
    _ references: inout [Key: Int],
    key: Key
  ) -> Int {
    let count = references[key, default: 0] + 1
    references[key] = count
    return count
  }

  private static func decrement<Key: Hashable>(
    _ references: inout [Key: Int],
    key: Key
  ) -> Int {
    let count = max(references[key, default: 0] - 1, 0)
    if count == 0 {
      references.removeValue(forKey: key)
    } else {
      references[key] = count
    }
    return count
  }

  private var sortedDeviceIdentifiers: [DeviceIdentifier] {
    devices.keys.sorted { $0.runtimeIdentifier < $1.runtimeIdentifier }
  }

  private static func sortedModifiers(
    _ modifiers: Set<RemappingKeyModifier>
  ) -> [RemappingKeyModifier] {
    modifiers.sorted { $0.rawValue < $1.rawValue }
  }

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
    guard isDown(at: uptimeNanoseconds) == outputIsDown else {
      return uptimeNanoseconds
    }

    let phase = (uptimeNanoseconds - startedAt) % periodNanoseconds
    let remaining = outputIsDown
      ? onDurationNanoseconds - phase
      : periodNanoseconds - phase
    return Self.saturatingAdd(uptimeNanoseconds, remaining)
  }

  private var periodNanoseconds: UInt64 {
    max(1, UInt64((1_000_000_000 / configuration.repeatRateHz).rounded()))
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
    case .keyboard, .mouseButton: return nil
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
