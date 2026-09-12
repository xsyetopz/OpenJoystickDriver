import Foundation

/// Consumes normalized controller events and emits system and virtual gamepad actions.
///
/// The caller owns profile selection and target-application policy. An active
/// profile is supplied with each event batch. Gamepad destinations are delivered
/// through the injected virtual output sink. Time is injected as monotonic uptime
/// nanoseconds so turbo and continuous output can be tested without sleeping.
public actor RemappingEventEngine {
  private let sink: any RemappingSystemInputSink
  private let gamepadSink: (any RemappingGamepadSink)?
  private let physicalOutputSink: (any RemappingPhysicalOutputSink)?
  private var heldGamepadDevices: Set<DeviceIdentifier> = []
  private var uncertainGamepadDevices: Set<DeviceIdentifier> = []
  private var heldMotionDevices: Set<DeviceIdentifier> = []
  private var uncertainMotionDevices: Set<DeviceIdentifier> = []
  private var heldPhysicalOwners: [DeviceIdentifier: Set<UUID>] = [:]
  private var uncertainPhysicalDevices: Set<DeviceIdentifier> = []
  nonisolated public let emissionBarrier: RemappingEmissionBarrier
  private var state = RemappingEngineState()
  private var faulted = false
  private var operationInProgress = false
  private var operationWaiters: [CheckedContinuation<Void, Never>] = []
  private var uncertainHeldOutputs: Set<RemappingHeldOutput> = []

  public init(
    sink: any RemappingSystemInputSink,
    gamepadSink: (any RemappingGamepadSink)? = nil,
    physicalOutputSink: (any RemappingPhysicalOutputSink)? = nil,
    emissionBarrier: RemappingEmissionBarrier = RemappingEmissionBarrier()
  ) {
    self.sink = sink
    self.gamepadSink = gamepadSink
    self.physicalOutputSink = physicalOutputSink
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
  ) async throws {
    guard let permit = emissionBarrier.currentPermit() else {
      throw RemappingEventEngineError.outputSuspended
    }
    try await process(
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
  ) async throws {
    try ensureAvailable()
    try profile.validate()
    try await commit(requiring: permit) { state in
      state.process(events: events, from: identifier, profile: profile, at: uptimeNanoseconds)
    }
  }

  /// Replaces or deactivates the profile for one exact controller.
  public func setProfile(
    _ profile: RemappingProfile?,
    for identifier: DeviceIdentifier
  ) async throws {
    guard let permit = emissionBarrier.currentPermit() else {
      throw RemappingEventEngineError.outputSuspended
    }
    try await setProfile(profile, for: identifier, requiring: permit)
  }

  public func setProfile(
    _ profile: RemappingProfile?,
    for identifier: DeviceIdentifier,
    requiring permit: RemappingEmissionPermit
  ) async throws {
    try ensureAvailable()
    try profile?.validate()
    try await commit(requiring: permit) { state in state.setProfile(profile, for: identifier) }
  }

  /// Advances deterministic turbo phases and continuous pointer/scroll output.
  public func tick(at uptimeNanoseconds: UInt64) async throws {
    guard let permit = emissionBarrier.currentPermit() else {
      throw RemappingEventEngineError.outputSuspended
    }
    try await tick(at: uptimeNanoseconds, requiring: permit)
  }

  public func tick(
    at uptimeNanoseconds: UInt64,
    requiring permit: RemappingEmissionPermit
  ) async throws {
    try ensureAvailable()
    try await commit(requiring: permit) { state in state.tick(at: uptimeNanoseconds) }
  }

  /// Whether turbo or nonzero continuous output requires future tick work.
  ///
  /// Ordinary held keys and mouse buttons do not require scheduling and are not
  /// included. A faulted engine reports `false` because fail-closed handling
  /// clears all active mapping state.
  public func hasScheduledOutput() -> Bool { state.hasScheduledOutput }

  public func motionCalibrationStatus(
    for identifier: DeviceIdentifier
  ) -> RemappingMotionCalibrationStatus? { state.motionCalibrationStatus(for: identifier) }

  /// Identifies the current mapping lifetime, including profile replacement and reconnect.
  public func motionSessionIdentifier(for identifier: DeviceIdentifier) -> UUID? {
    state.devices[identifier]?.sessionID
  }

  public func calibrateMotion(
    _ command: RemappingMotionCalibrationCommand,
    for identifier: DeviceIdentifier
  ) async throws -> RemappingMotionCalibrationStatus {
    guard let permit = emissionBarrier.currentPermit() else {
      throw RemappingEventEngineError.outputSuspended
    }
    return try await calibrateMotion(command, for: identifier, requiring: permit)
  }

  public func calibrateMotion(
    _ command: RemappingMotionCalibrationCommand,
    for identifier: DeviceIdentifier,
    requiring permit: RemappingEmissionPermit,
    expectedSessionID: UUID? = nil
  ) async throws -> RemappingMotionCalibrationStatus {
    guard let sessionID = state.devices[identifier]?.sessionID else {
      throw RemappingMotionCalibrationError.controllerUnavailable
    }
    guard expectedSessionID == nil || expectedSessionID == sessionID else {
      throw RemappingMotionCalibrationError.controllerUnavailable
    }
    await acquireOperation()
    defer { finishOperation() }
    try ensureAvailable()
    guard let lease = emissionBarrier.acquireLease(requiring: permit) else {
      throw RemappingEventEngineError.outputSuspended
    }
    defer { lease.finish() }
    guard state.devices[identifier]?.sessionID == sessionID else {
      throw RemappingMotionCalibrationError.controllerUnavailable
    }
    var calibrated = state
    let status = try calibrated.calibrateMotion(command, for: identifier)
    var actions: [RemappingEngineAction] = []
    if command == .reset, var device = calibrated.devices[identifier] {
      actions = device.clearGyroStick() + device.clearVirtualMotion()
      calibrated.devices[identifier] = device
      actions += calibrated.clearMotionStick(for: identifier, at: device.lastUptime)
    }
    try await commitUnchecked { candidate in
      candidate = calibrated
      return actions
    }
    return status
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
  public func releaseAll(for identifier: DeviceIdentifier) async throws {
    guard let permit = emissionBarrier.currentPermit() else {
      throw RemappingEventEngineError.outputSuspended
    }
    try await releaseAll(for: identifier, requiring: permit)
  }

  public func releaseAll(
    for identifier: DeviceIdentifier,
    requiring permit: RemappingEmissionPermit
  ) async throws {
    try ensureAvailable()
    try await commit(requiring: permit) { state in state.releaseController(identifier) }
  }

  /// Releases all keyboard and pointer state. Repeated drains are no-ops.
  public func drain() async throws {
    guard let permit = emissionBarrier.currentPermit() else {
      throw RemappingEventEngineError.outputSuspended
    }
    try await drain(requiring: permit)
  }

  public func drain(requiring permit: RemappingEmissionPermit) async throws {
    try ensureAvailable()
    try await commit(requiring: permit) { state in state.drain() }
  }

  /// Performs the one terminal neutralization after routing admission has closed permanently.
  public func drainAfterTermination() async throws {
    await acquireOperation()
    defer { finishOperation() }
    guard let lease = emissionBarrier.acquireTerminationLease() else {
      throw RemappingEventEngineError.outputSuspended
    }
    defer { lease.finish() }
    if faulted { try await recoverUncertainOutputs() }
    try await commitUnchecked { state in state.drain() }
  }

  /// Retries uncertain releases after a sink or permission failure.
  ///
  /// The engine remains faulted if any release fails and cannot emit new presses
  /// until recovery completes.
  public func recover() async throws {
    guard let permit = emissionBarrier.currentPermit() else {
      throw RemappingEventEngineError.outputSuspended
    }
    try await recover(requiring: permit)
  }

  public func recover(requiring permit: RemappingEmissionPermit) async throws {
    await acquireOperation()
    defer { finishOperation() }
    guard let lease = emissionBarrier.acquireLease(requiring: permit) else {
      throw RemappingEventEngineError.outputSuspended
    }
    defer { lease.finish() }
    guard faulted else { return }
    try await recoverUncertainOutputs()
  }

  private func recoverUncertainOutputs() async throws {
    try await releaseUncertainOutputs()
    faulted = false
  }

  private func releaseUncertainOutputs() async throws {
    var failed = false
    for output in Self.releaseOrder(uncertainHeldOutputs) {
      do {
        try sink.send(output.releaseAction)
        uncertainHeldOutputs.remove(output)
      } catch {
        failed = true
        break
      }
    }
    for identifier in uncertainGamepadDevices.sorted(by: {
      $0.runtimeIdentifier < $1.runtimeIdentifier
    }) {
      do {
        guard let gamepadSink else { throw RemappingEventEngineError.sinkUnavailable }
        try await gamepadSink.send(.neutral, for: identifier)
        uncertainGamepadDevices.remove(identifier)
      } catch { failed = true }
    }
    for identifier in uncertainMotionDevices.sorted(by: {
      $0.runtimeIdentifier < $1.runtimeIdentifier
    }) {
      do {
        guard let gamepadSink else { throw RemappingEventEngineError.sinkUnavailable }
        try await gamepadSink.send(nil, for: identifier)
        uncertainMotionDevices.remove(identifier)
      } catch { failed = true }
    }
    for identifier in uncertainPhysicalDevices.sorted(by: {
      $0.runtimeIdentifier < $1.runtimeIdentifier
    }) {
      do {
        guard let physicalOutputSink else {
          throw RemappingEventEngineError.sinkUnavailable
        }
        try await physicalOutputSink.releaseAll(for: identifier)
        uncertainPhysicalDevices.remove(identifier)
      } catch { failed = true }
    }
    if failed { throw RemappingEventEngineError.sinkUnavailable }
  }

  private func ensureAvailable() throws {
    guard !faulted else { throw RemappingEventEngineError.faulted }
  }

  private func acquireOperation() async {
    if !operationInProgress {
      operationInProgress = true
      return
    }
    await withCheckedContinuation { operationWaiters.append($0) }
  }

  private func finishOperation() {
    guard !operationWaiters.isEmpty else {
      operationInProgress = false
      return
    }
    operationWaiters.removeFirst().resume()
  }

  private func commit(
    requiring permit: RemappingEmissionPermit,
    _ transition: (inout RemappingEngineState) -> [RemappingEngineAction]
  ) async throws {
    await acquireOperation()
    defer { finishOperation() }
    try ensureAvailable()
    guard let lease = emissionBarrier.acquireLease(requiring: permit) else {
      throw RemappingEventEngineError.outputSuspended
    }
    defer { lease.finish() }
    try await commitUnchecked(transition)
  }

  private func commitUnchecked(
    _ transition: (inout RemappingEngineState) -> [RemappingEngineAction]
  ) async throws {
    let previous = state
    var candidate = previous
    let actions = transition(&candidate)
    var potentiallyHeld = previous.heldOutputs
    for action in actions {
      do {
        switch action {
        case .system(let systemAction):
          try sink.send(systemAction)
          Self.accountForDelivered(systemAction, in: &potentiallyHeld)
        case .gamepad(let gamepadState, let identifier):
          guard let gamepadSink else { throw RemappingEventEngineError.sinkUnavailable }
          heldGamepadDevices.insert(identifier)
          try await gamepadSink.send(gamepadState, for: identifier)
          if gamepadState == .neutral { heldGamepadDevices.remove(identifier) }
        case .motion(let motion, let identifier):
          guard let gamepadSink else { throw RemappingEventEngineError.sinkUnavailable }
          heldMotionDevices.insert(identifier)
          try await gamepadSink.send(motion, for: identifier)
          if motion == nil { heldMotionDevices.remove(identifier) }
        case .physical(let output, let active, let owner, let identifier):
          guard let physicalOutputSink else { throw RemappingEventEngineError.sinkUnavailable }
          try await physicalOutputSink.set(output, active: active, owner: owner, for: identifier)
          if active {
            heldPhysicalOwners[identifier, default: []].insert(owner)
          } else {
            heldPhysicalOwners[identifier]?.remove(owner)
            if heldPhysicalOwners[identifier]?.isEmpty == true {
              heldPhysicalOwners.removeValue(forKey: identifier)
            }
          }
        }
      } catch {
        if case .system(let systemAction) = action {
          Self.accountForUncertain(systemAction, in: &potentiallyHeld)
        }
        if case .physical(_, _, _, let identifier) = action {
          uncertainPhysicalDevices.insert(identifier)
        }
        await failClosed(potentiallyHeld: potentiallyHeld)
        throw RemappingEventEngineError.sinkUnavailable
      }
    }
    state = candidate
  }

  private func failClosed(potentiallyHeld: Set<RemappingHeldOutput>) async {
    state = RemappingEngineState()
    faulted = true
    uncertainHeldOutputs = potentiallyHeld
    uncertainGamepadDevices.formUnion(heldGamepadDevices)
    heldGamepadDevices.removeAll()
    uncertainMotionDevices.formUnion(heldMotionDevices)
    heldMotionDevices.removeAll()
    uncertainPhysicalDevices.formUnion(heldPhysicalOwners.keys)
    heldPhysicalOwners.removeAll()
    try? await releaseUncertainOutputs()
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
    case .mouseMoved, .pointerDelta, .scrolled, .scrollDelta: break
    }
  }

  private static func accountForUncertain(
    _ action: RemappingSystemInputAction,
    in heldOutputs: inout Set<RemappingHeldOutput>
  ) {
    switch action {
    case .modifierDown(let modifier), .modifierUp(let modifier):
      heldOutputs.insert(.modifier(modifier))
    case .keyDown(let key), .keyUp(let key): heldOutputs.insert(.key(key))
    case .mouseButtonDown(let button), .mouseButtonUp(let button):
      heldOutputs.insert(.mouseButton(button))
    case .mouseMoved, .pointerDelta, .scrolled, .scrollDelta: break
    }
  }

  private static func releaseOrder(_ outputs: Set<RemappingHeldOutput>) -> [RemappingHeldOutput] {
    outputs.sorted { lhs, rhs in
      if lhs.releaseOrder != rhs.releaseOrder { return lhs.releaseOrder < rhs.releaseOrder }
      if lhs.releaseOrder == 2 { return lhs.stableName > rhs.stableName }
      return lhs.stableName < rhs.stableName
    }
  }
}
