import Foundation

/// Consumes normalized controller events and emits keyboard and pointer actions.
///
/// The caller owns profile selection and target-application policy. An active
/// profile is supplied with each event batch, and this engine never forwards
/// events to a virtual controller. Time is injected as monotonic uptime
/// nanoseconds so turbo and continuous output can be tested without sleeping.
public actor RemappingEventEngine {
  private let sink: any RemappingSystemInputSink
  nonisolated public let emissionBarrier: RemappingEmissionBarrier
  private var state = RemappingEngineState()
  private var faulted = false
  private var uncertainHeldOutputs: Set<RemappingHeldOutput> = []

  public init(
    sink: any RemappingSystemInputSink,
    emissionBarrier: RemappingEmissionBarrier = RemappingEmissionBarrier()
  ) {
    self.sink = sink
    self.emissionBarrier = emissionBarrier
  }

  /// Processes a normalized event batch using the supplied validated profile.
  ///
  /// A changed profile first neutralizes the controller's previous mapping.
  public func process(
    events: [ControllerEvent],
    from identifier: DeviceIdentifier,
    using profile: RemappingProfile,
    at uptimeNanoseconds: UInt64
  ) throws {
    guard let permit = emissionBarrier.currentPermit() else {
      throw RemappingEventEngineError.outputSuspended
    }
    try process(
      events: events,
      from: identifier,
      using: profile,
      at: uptimeNanoseconds,
      requiring: permit
    )
  }

  public func process(
    events: [ControllerEvent],
    from identifier: DeviceIdentifier,
    using profile: RemappingProfile,
    at uptimeNanoseconds: UInt64,
    requiring permit: RemappingEmissionPermit
  ) throws {
    try ensureAvailable()
    try profile.validate()
    try commit(requiring: permit) { state in
      state.process(
        events: events,
        from: identifier,
        profile: profile,
        at: uptimeNanoseconds
      )
    }
  }

  /// Replaces or deactivates the profile for one exact controller.
  public func setProfile(
    _ profile: RemappingProfile?,
    for identifier: DeviceIdentifier
  ) throws {
    guard let permit = emissionBarrier.currentPermit() else {
      throw RemappingEventEngineError.outputSuspended
    }
    try setProfile(profile, for: identifier, requiring: permit)
  }

  public func setProfile(
    _ profile: RemappingProfile?,
    for identifier: DeviceIdentifier,
    requiring permit: RemappingEmissionPermit
  ) throws {
    try ensureAvailable()
    try profile?.validate()
    try commit(requiring: permit) { state in
      state.setProfile(profile, for: identifier)
    }
  }

  /// Advances deterministic turbo phases and continuous pointer/scroll output.
  public func tick(at uptimeNanoseconds: UInt64) throws {
    guard let permit = emissionBarrier.currentPermit() else {
      throw RemappingEventEngineError.outputSuspended
    }
    try tick(at: uptimeNanoseconds, requiring: permit)
  }

  public func tick(
    at uptimeNanoseconds: UInt64,
    requiring permit: RemappingEmissionPermit
  ) throws {
    try ensureAvailable()
    try commit(requiring: permit) { state in
      state.tick(at: uptimeNanoseconds)
    }
  }

  /// Whether turbo or nonzero continuous output requires future tick work.
  ///
  /// Ordinary held keys and mouse buttons do not require scheduling and are not
  /// included. A faulted engine reports `false` because fail-closed handling
  /// clears all active mapping state.
  public func hasScheduledOutput() -> Bool {
    state.hasScheduledOutput
  }

  /// Returns the earliest monotonic deadline required by scheduled output.
  ///
  /// Turbo deadlines are exact phase boundaries. Continuous destinations use
  /// the caller-owned cadence because their platform scaling and delivery rate
  /// are adapter policy. Arithmetic saturates at `UInt64.max`.
  public func nextScheduledTick(
    after uptimeNanoseconds: UInt64,
    continuousIntervalNanoseconds: UInt64
  ) -> UInt64? {
    state.nextScheduledTick(
      after: uptimeNanoseconds,
      continuousIntervalNanoseconds: continuousIntervalNanoseconds
    )
  }

  /// Releases every output owned by one exact controller and forgets its profile.
  public func releaseAll(for identifier: DeviceIdentifier) throws {
    guard let permit = emissionBarrier.currentPermit() else {
      throw RemappingEventEngineError.outputSuspended
    }
    try releaseAll(for: identifier, requiring: permit)
  }

  public func releaseAll(
    for identifier: DeviceIdentifier,
    requiring permit: RemappingEmissionPermit
  ) throws {
    try ensureAvailable()
    try commit(requiring: permit) { state in
      state.releaseController(identifier)
    }
  }

  /// Releases all keyboard and pointer state. Repeated drains are no-ops.
  public func drain() throws {
    guard let permit = emissionBarrier.currentPermit() else {
      throw RemappingEventEngineError.outputSuspended
    }
    try drain(requiring: permit)
  }

  public func drain(requiring permit: RemappingEmissionPermit) throws {
    try ensureAvailable()
    try commit(requiring: permit) { state in
      state.drain()
    }
  }

  /// Performs the one terminal neutralization after routing admission has closed permanently.
  public func drainAfterTermination() throws {
    try emissionBarrier.withTermination {
      if faulted {
        try recoverUncertainOutputs()
      }
      try commitUnchecked { state in state.drain() }
    }
  }

  /// Retries uncertain releases after a sink or permission failure.
  ///
  /// The engine remains faulted if any release fails and cannot emit new presses
  /// until recovery completes.
  public func recover() throws {
    guard let permit = emissionBarrier.currentPermit() else {
      throw RemappingEventEngineError.outputSuspended
    }
    try recover(requiring: permit)
  }

  public func recover(requiring permit: RemappingEmissionPermit) throws {
    try emissionBarrier.withEmissionPermit(permit) {
      guard faulted else { return }
      try recoverUncertainOutputs()
    }
  }

  private func recoverUncertainOutputs() throws {
    var remaining = uncertainHeldOutputs
    for output in Self.releaseOrder(uncertainHeldOutputs) {
      do {
        try sink.send(output.releaseAction)
        remaining.remove(output)
      } catch {
        uncertainHeldOutputs = remaining
        throw RemappingEventEngineError.sinkUnavailable
      }
    }
    uncertainHeldOutputs = []
    faulted = false
  }

  private func ensureAvailable() throws {
    guard !faulted else { throw RemappingEventEngineError.faulted }
  }

  private func commit(
    requiring permit: RemappingEmissionPermit,
    _ transition: (inout RemappingEngineState) -> [RemappingSystemInputAction]
  ) throws {
    try emissionBarrier.withEmissionPermit(permit) {
      try commitUnchecked(transition)
    }
  }

  private func commitUnchecked(
    _ transition: (inout RemappingEngineState) -> [RemappingSystemInputAction]
  ) throws {
    let previous = state
    var candidate = previous
    let actions = transition(&candidate)
    var potentiallyHeld = previous.heldOutputs
    for action in actions {
      do {
        try sink.send(action)
        Self.accountForDelivered(action, in: &potentiallyHeld)
      } catch {
        Self.accountForUncertain(action, in: &potentiallyHeld)
        failClosed(potentiallyHeld: potentiallyHeld)
        throw RemappingEventEngineError.sinkUnavailable
      }
    }
    state = candidate
  }

  private func failClosed(
    potentiallyHeld: Set<RemappingHeldOutput>
  ) {
    state = RemappingEngineState()
    faulted = true

    var remaining = potentiallyHeld
    for output in Self.releaseOrder(potentiallyHeld) {
      do {
        try sink.send(output.releaseAction)
        remaining.remove(output)
      } catch {
        break
      }
    }
    uncertainHeldOutputs = remaining
  }

  private static func accountForDelivered(
    _ action: RemappingSystemInputAction,
    in heldOutputs: inout Set<RemappingHeldOutput>
  ) {
    switch action {
    case .modifierDown(let modifier): heldOutputs.insert(.modifier(modifier))
    case .modifierUp(let modifier): heldOutputs.remove(.modifier(modifier))
    case .keyDown(let key): heldOutputs.insert(.key(key))
    case .keyUp(let key): heldOutputs.remove(.key(key))
    case .mouseButtonDown(let button): heldOutputs.insert(.mouseButton(button))
    case .mouseButtonUp(let button): heldOutputs.remove(.mouseButton(button))
    case .mouseMoved, .scrolled: break
    }
  }

  private static func accountForUncertain(
    _ action: RemappingSystemInputAction,
    in heldOutputs: inout Set<RemappingHeldOutput>
  ) {
    switch action {
    case .modifierDown(let modifier), .modifierUp(let modifier):
      heldOutputs.insert(.modifier(modifier))
    case .keyDown(let key), .keyUp(let key):
      heldOutputs.insert(.key(key))
    case .mouseButtonDown(let button), .mouseButtonUp(let button):
      heldOutputs.insert(.mouseButton(button))
    case .mouseMoved, .scrolled: break
    }
  }

  private static func releaseOrder(
    _ outputs: Set<RemappingHeldOutput>
  ) -> [RemappingHeldOutput] {
    outputs.sorted { lhs, rhs in
      if lhs.releaseOrder != rhs.releaseOrder {
        return lhs.releaseOrder < rhs.releaseOrder
      }
      if lhs.releaseOrder == 2 {
        return lhs.stableName > rhs.stableName
      }
      return lhs.stableName < rhs.stableName
    }
  }
}
