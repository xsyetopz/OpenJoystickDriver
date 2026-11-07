import Foundation

/// One running macro, owned by the action whose destination is the macro.
struct RemappingMacroRun {
  /// Output that a step holds, with the owner that the output is pressed under.
  struct HeldStep {
    /// Owner identity of the output.
    let owner: UUID
    /// Destination that is down.
    let destination: RemappingDestination
  }

  /// The macro that runs.
  let macro: RemappingMacro
  /// Index of the step that runs next.
  var stepIndex = 0
  /// Passes that ended.
  var passes = 0
  /// Uptime at which the current pass started, in nanoseconds.
  var passStart: UInt64
  /// Uptime at which the next step may run, in nanoseconds.
  var nextAt: UInt64
  /// Whether the step at `stepIndex` is a chord that is down.
  var isHolding = false
  /// Whether the source is down.
  var sourceIsDown = true
  /// Outputs that steps hold, in the order they went down.
  var held: [HeldStep] = []
}

extension RemappingEngineState {
  /// Starts the macro of an action, or applies its `whileRunning` rule when it already runs.
  ///
  /// The first steps run at once.
  mutating func startMacro(
    _ macroID: UUID,
    owner: UUID,
    device: inout RemappingDeviceState
  ) -> [RemappingEngineAction] {
    guard let macro = device.profile.macros.first(where: { $0.id == macroID }) else { return [] }
    var actions: [RemappingEngineAction] = []
    if var run = device.outputs.macros[owner] {
      guard macro.whileRunning == .restart else {
        run.sourceIsDown = true
        device.outputs.macros[owner] = run
        return []
      }
      actions = stopMacro(owner, device: &device)
    }
    device.outputs.macros[owner] = RemappingMacroRun(
      macro: macro,
      passStart: device.lastUptime,
      nextAt: device.lastUptime
    )
    return actions + advanceMacro(owner, device: &device, at: device.lastUptime)
  }

  /// Records that the source of a macro was released, and stops the macro when it asks for that.
  mutating func endMacroSource(
    owner: UUID,
    device: inout RemappingDeviceState
  ) -> [RemappingEngineAction] {
    guard var run = device.outputs.macros[owner] else { return [] }
    run.sourceIsDown = false
    device.outputs.macros[owner] = run
    return run.macro.interruptOnRelease ? stopMacro(owner, device: &device) : []
  }

  /// Runs the steps of a macro that are due at an uptime.
  ///
  /// The end of a pass releases what its steps still hold. Another pass starts when the repeat asks
  /// for it, at least ``RemappingMacro/minimumPassIntervalMs`` after the previous one.
  mutating func advanceMacro(
    _ owner: UUID,
    device: inout RemappingDeviceState,
    at uptime: UInt64
  ) -> [RemappingEngineAction] {
    guard var run = device.outputs.macros[owner] else { return [] }
    var actions: [RemappingEngineAction] = []
    while run.nextAt <= uptime {
      guard run.stepIndex < run.macro.steps.count else {
        actions += releaseHeld(&run, count: run.held.count, device: &device)
        run.passes += 1
        let again: Bool
        switch run.macro.repeatMode {
        case .count(let count): again = run.passes < count
        case .whileHeld: again = run.sourceIsDown
        }
        guard again else {
          device.outputs.macros.removeValue(forKey: owner)
          return actions
        }
        run.stepIndex = 0
        run.passStart = max(
          run.nextAt,
          Self.saturatingAdd(
            run.passStart,
            UInt64(RemappingMacro.minimumPassIntervalMs * nanosecondsPerMillisecond)
          )
        )
        run.nextAt = run.passStart
        continue
      }
      actions += runStep(&run, device: &device)
    }
    device.outputs.macros[owner] = run
    return actions
  }

  /// Stops a macro and releases every output it holds; the one release path of macros.
  ///
  /// Used by a release of the source that interrupts, a restart, a profile change, a disconnect and
  /// the cancel of an action. Fail-closed handling needs no call: macro outputs are reference
  /// counted with all others, so it releases them with ``RemappingEngineState/heldOutputs``.
  mutating func stopMacro(
    _ owner: UUID,
    device: inout RemappingDeviceState
  ) -> [RemappingEngineAction] {
    guard var run = device.outputs.macros.removeValue(forKey: owner) else { return [] }
    return releaseHeld(&run, count: run.held.count, device: &device)
  }

  /// Stops every macro of a controller.
  mutating func stopMacros(device: inout RemappingDeviceState) -> [RemappingEngineAction] {
    var actions: [RemappingEngineAction] = []
    for owner in device.outputs.macros.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
      actions += stopMacro(owner, device: &device)
    }
    return actions
  }

  /// Runs the step at the run's index and moves on, or waits in a chord hold.
  private mutating func runStep(
    _ run: inout RemappingMacroRun,
    device: inout RemappingDeviceState
  ) -> [RemappingEngineAction] {
    var actions: [RemappingEngineAction] = []
    switch run.macro.steps[run.stepIndex] {
    case .tap(let destination):
      actions += pressStep(destination, run: &run, device: &device)
      actions += releaseHeld(&run, count: 1, device: &device)
    case .press(let destination): actions += pressStep(destination, run: &run, device: &device)
    case .release(let destination):
      if let index = run.held.lastIndex(where: { $0.destination == destination }) {
        let step = run.held.remove(at: index)
        actions += setBinding(
          step.owner,
          destination: destination,
          isDown: false,
          device: &device
        )
      }
    case .chord(let destinations, let holdMs):
      guard run.isHolding else {
        for destination in destinations {
          actions += pressStep(destination, run: &run, device: &device)
        }
        run.isHolding = true
        run.nextAt = Self.saturatingAdd(run.nextAt, Self.nanoseconds(holdMs))
        return actions
      }
      actions += releaseHeld(&run, count: destinations.count, device: &device)
      run.isHolding = false
    case .wait(let durationMs):
      run.nextAt = Self.saturatingAdd(run.nextAt, Self.nanoseconds(durationMs))
    }
    run.stepIndex += 1
    return actions
  }

  /// Presses a destination under a new owner and records it as held.
  private mutating func pressStep(
    _ destination: RemappingDestination,
    run: inout RemappingMacroRun,
    device: inout RemappingDeviceState
  ) -> [RemappingEngineAction] {
    let owner = UUID()
    run.held.append(.init(owner: owner, destination: destination))
    return setBinding(owner, destination: destination, isDown: true, device: &device)
  }

  /// Releases the last `count` held outputs of a run in reverse order.
  private mutating func releaseHeld(
    _ run: inout RemappingMacroRun,
    count: Int,
    device: inout RemappingDeviceState
  ) -> [RemappingEngineAction] {
    var actions: [RemappingEngineAction] = []
    for step in run.held.suffix(count).reversed() {
      actions += setBinding(
        step.owner,
        destination: step.destination,
        isDown: false,
        device: &device
      )
    }
    run.held.removeLast(count)
    return actions
  }

  /// Converts milliseconds to nanoseconds.
  private static func nanoseconds(_ milliseconds: Double) -> UInt64 {
    UInt64(milliseconds * nanosecondsPerMillisecond)
  }
}
