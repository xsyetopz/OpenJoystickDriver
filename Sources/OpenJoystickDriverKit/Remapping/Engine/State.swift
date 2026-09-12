import Foundation

private let nanosecondsPerMillisecond: Double = 1_000_000

struct RemappingEngineState {
  var devices: [DeviceIdentifier: RemappingDeviceState] = [:]
  var keyReferences: [RemappingKeyboardKey: Int] = [:]
  var modifierReferences: [RemappingKeyModifier: Int] = [:]
  var mouseButtonReferences: [RemappingMouseButton: Int] = [:]

  mutating func setProfile(
    _ profile: RemappingProfile?,
    for identifier: DeviceIdentifier
  ) -> [RemappingEngineAction] {
    guard devices[identifier]?.profile != profile else { return [] }
    let actions = releaseController(identifier)
    if let profile {
      devices[identifier] = RemappingDeviceState(profile: profile, identifier: identifier)
    }
    return actions
  }

  mutating func process(
    events: [ControllerEvent],
    from identifier: DeviceIdentifier,
    profile: RemappingProfile,
    at uptimeNanoseconds: UInt64
  ) -> [RemappingEngineAction] {
    var actions = setProfile(profile, for: identifier)
    let monotonicUptime = max(uptimeNanoseconds, devices[identifier]?.lastUptime ?? 0)
    for event in events {
      if var device = devices[identifier] {
        device.lastUptime = monotonicUptime
        actions += processChords(for: &device)
        actions += replayPendingChordPresses(device: &device, at: monotonicUptime)
        devices[identifier] = device
      }
      actions += process(event: event, from: identifier, at: monotonicUptime)
      if var device = devices[identifier] {
        actions += device.updatePassthrough()
        devices[identifier] = device
      }
    }
    return actions
  }

  private mutating func process(
    event: ControllerEvent,
    from identifier: DeviceIdentifier,
    at uptimeNanoseconds: UInt64
  ) -> [RemappingEngineAction] {
    switch event {
    case .buttonPressed(let button):
      guard let source = inputSource(for: button, identifier: identifier) else { return [] }
      return setSource(source, isActive: true, for: identifier, at: uptimeNanoseconds)
    case .buttonReleased(let button):
      guard let source = inputSource(for: button, identifier: identifier) else { return [] }
      return setSource(source, isActive: false, for: identifier, at: uptimeNanoseconds)
    case .dpadChanged(let direction):
      return setDpad(direction, for: identifier, at: uptimeNanoseconds)
    case .leftStickChanged(let x, let y):
      let actions = processAdvancedStick(.left, x: x, y: y, for: identifier, at: uptimeNanoseconds)
      return actions
        + processAxes([(.leftStickX, x), (.leftStickY, y)], for: identifier, at: uptimeNanoseconds)
    case .rightStickChanged(let x, let y):
      let actions = processAdvancedStick(.right, x: x, y: y, for: identifier, at: uptimeNanoseconds)
      return actions
        + processAxes(
          [(.rightStickX, x), (.rightStickY, y)],
          for: identifier,
          at: uptimeNanoseconds
        )
    case .leftTriggerChanged(let value):
      return processAdvancedTrigger(
        .left, value: value, for: identifier, at: uptimeNanoseconds
      ) + processAxes([(.leftTrigger, value)], for: identifier, at: uptimeNanoseconds)
    case .rightTriggerChanged(let value):
      return processAdvancedTrigger(
        .right, value: value, for: identifier, at: uptimeNanoseconds
      ) + processAxes([(.rightTrigger, value)], for: identifier, at: uptimeNanoseconds)
    case .motionSample(let sample): return processMotion(sample, for: identifier)
    case .touchSample(let sample):
      return processTouch(sample, for: identifier, at: uptimeNanoseconds)
    }
  }

  private mutating func setDpad(
    _ direction: DpadDirection,
    for identifier: DeviceIdentifier,
    at uptimeNanoseconds: UInt64
  ) -> [RemappingEngineAction] {
    guard var device = devices[identifier] else { return [] }
    let nextDirections = Self.cardinalDirections(for: direction)
    let removed = device.dpadDirections.subtracting(nextDirections)
    let added = nextDirections.subtracting(device.dpadDirections)
    device.dpadDirections = nextDirections
    devices[identifier] = device

    var actions: [RemappingEngineAction] = []
    for direction in removed.sorted(by: Self.dpadLessThan) {
      actions += setSource(
        .dpad(direction),
        isActive: false,
        for: identifier,
        at: uptimeNanoseconds
      )
    }
    for direction in added.sorted(by: Self.dpadLessThan) {
      actions += setSource(.dpad(direction), isActive: true, for: identifier, at: uptimeNanoseconds)
    }
    return actions
  }

  private mutating func processAxes(
    _ values: [(RemappingAxis, Float)],
    for identifier: DeviceIdentifier,
    at uptimeNanoseconds: UInt64
  ) -> [RemappingEngineAction] {
    var actions: [RemappingEngineAction] = []
    for (axis, value) in values {
      actions += processAxis(axis, value: value, for: identifier, at: uptimeNanoseconds)
    }
    return actions
  }

  private mutating func processAxis(
    _ axis: RemappingAxis,
    value rawValue: Float,
    for identifier: DeviceIdentifier,
    at uptimeNanoseconds: UInt64
  ) -> [RemappingEngineAction] {
    guard var device = devices[identifier] else { return [] }
    device.physicalAxes[axis] = rawValue
    let oldContinuous = continuousTotals()
    var actions: [RemappingEngineAction] = []

    for binding in device.binding(for: .axis(axis))?.expandedActions ?? [] {
      if let tuning = binding.axisTuning, case .gamepadAxis(let destination) = binding.destination {
        let value = RemappingTransform.value(rawValue, tuning: tuning)
        device.virtualAxisBindings.insert(binding.id)
        if let state = device.gamepad.update(
          RemappingGamepadState(axes: [destination: value]),
          for: binding.id
        ) {
          actions.append(.gamepad(state, identifier))
        }
      }

      if let tuning = binding.axisTuning,
        let continuousDestination = RemappingContinuousDestination(binding.destination)
      {
        let transformed = RemappingTransform.value(rawValue, tuning: tuning)
        if transformed == 0 {
          device.continuous.removeValue(forKey: binding.id)
        } else {
          device.continuous[binding.id] = RemappingContinuousOutput(
            destination: continuousDestination,
            amount: transformed
          )
        }
      }
    }

    for direction in [RemappingAxisDirection.negative, .positive] {
      let source = RemappingSource.axisDirection(axis, direction)
      guard let tuning = device.directionTuning(for: source) else { continue }
      let transformed = RemappingTransform.value(rawValue, tuning: tuning)
      let wasActive = device.activeSources.contains(source)
      let isActive = RemappingTransform.isDirectionActive(
        value: transformed,
        direction: direction,
        threshold: tuning.digitalActivationThreshold,
        wasActive: wasActive
      )
      devices[identifier] = device
      actions += setSource(source, isActive: isActive, for: identifier, at: uptimeNanoseconds)
      guard let updated = devices[identifier] else { return actions }
      device = updated
    }
    devices[identifier] = device
    actions += stoppedContinuousActions(previous: oldContinuous)
    return actions
  }

  mutating func setSource(
    _ source: RemappingSource,
    isActive: Bool,
    for identifier: DeviceIdentifier,
    at uptimeNanoseconds: UInt64
  ) -> [RemappingEngineAction] {
    guard var device = devices[identifier] else { return [] }
    let wasActive = device.activeSources.contains(source)
    let gyroWasActive = device.isGyroActive
    guard wasActive != isActive else { return [] }
    var actions: [RemappingEngineAction] = []
    if !isActive { actions += processChords(for: &device, releasing: source) }
    actions += replayPendingChordPresses(
      device: &device,
      at: uptimeNanoseconds,
      releasing: isActive ? nil : source
    )
    if isActive {
      device.activeSources.insert(source)
      device.sourcePressTimes[source] = uptimeNanoseconds
    } else {
      device.activeSources.remove(source)
      device.sourcePressTimes.removeValue(forKey: source)
    }
    if device.profile.gyroOutput.activationSource == source {
      if isActive, device.profile.gyroOutput.activationMode == .toggle {
        device.gyroToggleActive.toggle()
      }
      if gyroWasActive != device.isGyroActive {
        device.gyroAwaitingBaseline = true
        if !device.isGyroActive { actions += device.clearGyroStick() }
      }
    }

    let oldContinuous = continuousTotals()
    if let layerActions = handleLayerActivator(source, isActive: isActive, device: &device) {
      devices[identifier] = device
      return actions + layerActions + stoppedContinuousActions(previous: oldContinuous)
    }

    let wasConsumed = device.consumedChordSources.contains(source)
    let buffered = isActive && device.bufferChordPress(source, at: uptimeNanoseconds)
    let modifierOwned = device.effectiveChords.contains {
      $0.mode == .modifier && $0.sources.contains(source)
    }
    let suppress =
      buffered || wasConsumed || modifierOwned
      || (isActive && sourceCompletesChord(source, in: device))
    for binding in device.binding(for: source)?.expandedActions ?? [] {
      actions += processAction(
        binding,
        isActive: isActive,
        suppressed: suppress,
        device: &device,
        at: uptimeNanoseconds
      )
    }
    if isActive && !wasConsumed {
      device.sequenceHistory.append(
        RemappingSequenceHistoryEntry(
          source: source,
          uptime: uptimeNanoseconds,
          awaitingChord: buffered
        )
      )
    }
    if !isActive {
      device.consumedChordSources.remove(source)
      device.replayedChordSources.remove(source)
    }
    actions += processChords(for: &device)
    actions += processSequences(for: &device, at: uptimeNanoseconds)
    devices[identifier] = device
    return actions
  }

  private func inputSource(for button: Button, identifier _: DeviceIdentifier) -> RemappingSource? {
    return Self.source(for: button)
  }

  static func source(for button: Button) -> RemappingSource? {
    switch button {
    case .a, .cross: .button(.south)
    case .b, .circle: .button(.east)
    case .x, .square: .button(.west)
    case .y, .triangle: .button(.north)
    case .leftBumper, .l1: .button(.leftShoulder)
    case .rightBumper, .r1: .button(.rightShoulder)
    case .leftStick: .button(.leftStick)
    case .rightStick: .button(.rightStick)
    case .start: .button(.start)
    case .back: .button(.back)
    case .guide, .ps: .button(.guide)
    case .share: .button(.share)
    case .options: .button(.options)
    case .touchpad: .button(.touchpad)
    case .l2Digital: .button(.leftTriggerClick)
    case .r2Digital: .button(.rightTriggerClick)
    case .mute: .button(.mute)
    case .leftGrip: .button(.leftGrip)
    case .rightGrip: .button(.rightGrip)
    case .leftPadClick: .button(.leftPadClick)
    case .rightPadClick: .button(.rightPadClick)
    case .leftSL: .button(.leftSL)
    case .leftSR: .button(.leftSR)
    case .rightSL: .button(.rightSL)
    case .rightSR: .button(.rightSR)
    case .leftFunction: .button(.leftFunction)
    case .rightFunction: .button(.rightFunction)
    case .leftPaddle: .button(.leftPaddle)
    case .rightPaddle: .button(.rightPaddle)
    case .dpadUp: .dpad(.up)
    case .dpadDown: .dpad(.down)
    case .dpadLeft: .dpad(.left)
    case .dpadRight: .dpad(.right)
    }
  }

  private static func cardinalDirections(
    for direction: DpadDirection
  ) -> Set<RemappingDpadDirection> {
    switch direction {
    case .neutral: []
    case .north: [.up]
    case .northEast: [.up, .right]
    case .east: [.right]
    case .southEast: [.down, .right]
    case .south: [.down]
    case .southWest: [.down, .left]
    case .west: [.left]
    case .northWest: [.up, .left]
    }
  }

  private static func dpadLessThan(
    _ lhs: RemappingDpadDirection,
    _ rhs: RemappingDpadDirection
  ) -> Bool { lhs.rawValue < rhs.rawValue }

  private mutating func handleLayerActivator(
    _ source: RemappingSource,
    isActive: Bool,
    device: inout RemappingDeviceState
  ) -> [RemappingEngineAction]? {
    let profile = device.profile
    var actions: [RemappingEngineAction] = []
    var handled = false
    let previousTuning = device.effectiveMotionTuning
    let previousLayers = device.activeLayers

    for layer in profile.layers where layer.activator == source {
      handled = true
      switch layer.activationMode {
      case .hold:
        if isActive {
          if !device.activeLayers.contains(layer.id) { device.activeLayers.append(layer.id) }
        } else {
          device.activeLayers.removeAll { $0 == layer.id }
        }
      case .toggle:
        if isActive {
          if device.layerToggleState.contains(layer.id) {
            device.layerToggleState.remove(layer.id)
            device.activeLayers.removeAll { $0 == layer.id }
          } else {
            device.layerToggleState.insert(layer.id)
            device.activeLayers.append(layer.id)
          }
        }
      }
    }

    guard handled else { return nil }
    guard previousLayers != device.activeLayers else { return [] }
    if previousTuning != device.effectiveMotionTuning {
      actions += device.clearGyroStick()
      actions += device.clearVirtualMotion()
      actions += device.clearMotionSteering()
      device.motionStickDeadline = nil
      for direction in device.activeMotionLeans {
        let source = RemappingSource.motionLean(direction)
        actions += cancelActions(for: [source], device: &device)
        device.activeSources.remove(source)
        device.sourcePressTimes.removeValue(forKey: source)
      }
      device.activeMotionLeans.removeAll()
      device.motion.resetCalibration()
      device.gyroAwaitingBaseline = true
    }
    actions += reconcileLayerOutputs(device: &device)
    device.sequenceHistory.removeAll()
    device.deferredSequences.removeAll()
    device.replayedChordSources.formUnion(device.pendingChordPresses.map(\.source))
    device.consumedChordSources.formUnion(device.pendingChordPresses.map(\.source))
    device.pendingChordPresses.removeAll()

    actions += processChords(for: &device)
    return actions
  }

  private func sourceCompletesChord(
    _ source: RemappingSource,
    in device: RemappingDeviceState
  ) -> Bool { device.selectedChords().contains { $0.sources.contains(source) } }

  mutating func processChords(
    for device: inout RemappingDeviceState,
    releasing source: RemappingSource? = nil
  ) -> [RemappingEngineAction] {
    let selected = device.selectedChords(releasing: source)
    let selectedIDs = Set(selected.map(\.id))
    var actions: [RemappingEngineAction] = []
    let retiredIDs = device.activeChords.subtracting(selectedIDs).sorted {
      $0.uuidString < $1.uuidString
    }
    for id in retiredIDs {
      guard let destination = device.heldBindings[id] else { continue }
      actions += setBinding(id, destination: destination, isDown: false, device: &device)
    }
    for chord in selected where !device.activeChords.contains(chord.id) {
      actions += cancelActions(for: chord.sources, device: &device)
      device.sequenceHistory.removeAll { chord.sources.contains($0.source) }
      device.deferredSequences.removeAll { !$0.awaitingSources.isDisjoint(with: chord.sources) }
      device.pendingChordPresses.removeAll { chord.sources.contains($0.source) }
      device.consumedChordSources.formUnion(chord.sources)
      actions += setBinding(chord.id, destination: chord.destination, isDown: true, device: &device)
    }
    device.activeChords = selectedIDs
    return actions
  }

  /// Checks if recent input history matches any defined sequence.
  mutating func processSequences(
    for device: inout RemappingDeviceState,
    at uptimeNanoseconds: UInt64
  ) -> [RemappingEngineAction] {
    var actions = commitDeferredSequences(device: &device)
    let allSequences = device.effectiveSequences

    for sequence in allSequences {
      let sources = sequence.sources
      guard device.sequenceHistory.count >= sources.count else { continue }
      let windowNs = UInt64(sequence.windowMs * nanosecondsPerMillisecond)
      let tail = Array(device.sequenceHistory.suffix(sources.count))

      guard tail.count == sources.count else { continue }
      let matches = zip(tail, sources).allSatisfy { $0.0.source == $0.1 }
      guard matches else { continue }

      guard let firstUptime = tail.first?.uptime, let lastUptime = tail.last?.uptime else {
        continue
      }
      guard lastUptime >= firstUptime, lastUptime - firstUptime <= windowNs else { continue }

      let awaitingSources = Set(tail.filter(\.awaitingChord).map(\.source))
      if awaitingSources.isEmpty {
        actions += tapBinding(sequence.id, destination: sequence.destination, device: &device)
      } else {
        device.deferredSequences.append(
          RemappingDeferredSequence(sequence: sequence, awaitingSources: awaitingSources)
        )
      }
      // Each deferred match owns at least one pending press, which this clear removes
      // from history. It cannot create another match until that press resolves.
      device.sequenceHistory.removeAll()
      break
    }

    device.pruneSequenceHistory(at: uptimeNanoseconds)
    return actions
  }
}

struct RemappingDeviceState {
  let sessionID = UUID()
  var motion = RemappingMotionProcessor()
  let gyroBindingID = UUID()
  let motionSteeringBindingID = UUID()
  var gyroDeadline: UInt64?
  var virtualMotionDeadline: UInt64?
  var motionStickDeadline: UInt64?
  var hasVirtualMotionOutput = false
  var gyroToggleActive = false
  var gyroAwaitingBaseline = true
  var gyroTrackball = RemappingMotionTrackball()
  var activeMotionLeans: Set<RemappingMotionLeanDirection> = []
  var sticks: [RemappingStickSource: RemappingStickRuntime] = [:]
  var triggers: [RemappingTriggerSource: RemappingDualStageTriggerRuntime] = [:]
  var touchSurfaces: [RemappingTouchSurface: RemappingTouchSurfaceState] = [:]
  let profile: RemappingProfile
  let identifier: DeviceIdentifier
  var gamepad = RemappingGamepadAccumulator()
  var virtualAxisBindings: Set<UUID> = []
  let passthroughBindingID = UUID()
  var physicalAxes: [RemappingAxis: Float] = [:]
  var activeSources: Set<RemappingSource> = []
  var sourcePressTimes: [RemappingSource: UInt64] = [:]
  var lastUptime: UInt64 = 0
  var pendingChordPresses: [RemappingPendingChordPress] = []
  var consumedChordSources: Set<RemappingSource> = []
  var replayedChordSources: Set<RemappingSource> = []
  var dpadDirections: Set<RemappingDpadDirection> = []
  var heldBindings: [UUID: RemappingDestination] = [:]
  var armedReleaseBindings: Set<UUID> = []
  var pulseDeadlines: [UUID: UInt64] = [:]
  var turbos: [UUID: RemappingTurboOutput] = [:]
  var continuous: [UUID: RemappingContinuousOutput] = [:]
  var activations: [UUID: RemappingActivationTracker] = [:]
  var activeChords: Set<UUID> = []
  var sequenceHistory: [RemappingSequenceHistoryEntry] = []
  var deferredSequences: [RemappingDeferredSequence] = []
  var activeLayers: [UUID] = []
  var layerToggleState: Set<UUID> = []

  func binding(for source: RemappingSource) -> RemappingBinding? {
    for layerID in activeLayers.reversed() {
      guard let layer = profile.layers.first(where: { $0.id == layerID }) else { continue }
      if let binding = layer.bindings.first(where: { $0.source == source }) { return binding }
    }
    return profile.bindings.first { $0.source == source }
  }
}

struct RemappingActivationTracker {
  var pressUptime: UInt64?
  var releaseUptime: UInt64?
  var tapCount: Int = 0
  var firedBindingID: UUID?
  var pendingDefault: Bool = false
}

struct RemappingSequenceHistoryEntry: Equatable {
  let source: RemappingSource
  let uptime: UInt64
  var awaitingChord: Bool = false
}
