import Foundation

extension RemappingEngineState {

  /// Replaces the profile of a controller, or removes its mapping with `nil`.
  ///
  /// Returns the actions that release what the earlier session held. A profile equal to the current
  /// one changes nothing.
  mutating func setProfile(
    _ profile: RemappingProfile?,
    for identifier: LogicalControllerID
  ) -> [RemappingEngineAction] {
    guard devices[identifier]?.profile != profile else { return [] }
    let actions = releaseController(identifier)
    if let profile {
      devices[identifier] = RemappingDeviceState(profile: profile, identifier: identifier)
    }
    return actions
  }

  /// Applies the changes of one snapshot in order, as one transition of `identifier`.
  ///
  /// The profile is applied first. Each change is preceded by chord processing and the replay of
  /// due held-back presses, and followed by an update of the passthrough contribution. The uptime
  /// of a controller never goes back.
  mutating func process(
    changes: [RemappingInputChange],
    from identifier: LogicalControllerID,
    profile: RemappingProfile,
    at uptimeNanoseconds: UInt64
  ) -> [RemappingEngineAction] {
    var actions = setProfile(profile, for: identifier)
    let monotonicUptime = max(uptimeNanoseconds, devices[identifier]?.lastUptime ?? 0)
    for change in changes {
      if var device = devices[identifier] {
        device.lastUptime = monotonicUptime
        actions += processChords(for: &device)
        actions += replayPendingChordPresses(device: &device, at: monotonicUptime)
        devices[identifier] = device
      }
      actions += process(change: change, from: identifier, at: monotonicUptime)
      if var device = devices[identifier] {
        actions += device.updatePassthrough()
        devices[identifier] = device
      }
    }
    return actions
  }

  /// Applies one input change.
  ///
  /// Sticks run their stick mapping first and then their axis sources. Triggers run their trigger
  /// mapping first and then their axis source.
  mutating func process(
    change: RemappingInputChange,
    from identifier: LogicalControllerID,
    at uptimeNanoseconds: UInt64
  ) -> [RemappingEngineAction] {
    if devices[identifier]?.isPaused == true {
      switch change {
      case .leftStick(let x, let y):
        return processAxes(
          [(.leftStickX, x), (.leftStickY, y)],
          for: identifier,
          at: uptimeNanoseconds
        )
      case .rightStick(let x, let y):
        return processAxes(
          [(.rightStickX, x), (.rightStickY, y)],
          for: identifier,
          at: uptimeNanoseconds
        )
      case .pointer(let x, let y):
        return processAxes(
          [(.pointerX, x), (.pointerY, y)],
          for: identifier,
          at: uptimeNanoseconds
        )
      case .leftTrigger(let value):
        return processAxes([(.leftTrigger, value)], for: identifier, at: uptimeNanoseconds)
      case .rightTrigger(let value):
        return processAxes([(.rightTrigger, value)], for: identifier, at: uptimeNanoseconds)
      case .motion, .touch: return []
      case .button, .dpad: break
      }
    }
    switch change {
    case .button(let button, let isPressed):
      return setSource(.button(button), isActive: isPressed, for: identifier, at: uptimeNanoseconds)
    case .dpad(let direction): return setDpad(direction, for: identifier, at: uptimeNanoseconds)
    case .leftStick(let x, let y):
      let actions = processAdvancedStick(.left, x: x, y: y, for: identifier, at: uptimeNanoseconds)
      return actions
        + processAxes([(.leftStickX, x), (.leftStickY, y)], for: identifier, at: uptimeNanoseconds)
        + processStickRegions(.left, x: x, y: y, for: identifier, at: uptimeNanoseconds)
    case .rightStick(let x, let y):
      let actions = processAdvancedStick(.right, x: x, y: y, for: identifier, at: uptimeNanoseconds)
      return actions
        + processAxes(
          [(.rightStickX, x), (.rightStickY, y)],
          for: identifier,
          at: uptimeNanoseconds
        ) + processStickRegions(.right, x: x, y: y, for: identifier, at: uptimeNanoseconds)
    case .pointer(let x, let y):
      return processAxes([(.pointerX, x), (.pointerY, y)], for: identifier, at: uptimeNanoseconds)
    case .leftTrigger(let value):
      return processAdvancedTrigger(.left, value: value, for: identifier, at: uptimeNanoseconds)
        + processAxes([(.leftTrigger, value)], for: identifier, at: uptimeNanoseconds)
        + processTriggerBands(.left, value: value, for: identifier, at: uptimeNanoseconds)
    case .rightTrigger(let value):
      return processAdvancedTrigger(.right, value: value, for: identifier, at: uptimeNanoseconds)
        + processAxes([(.rightTrigger, value)], for: identifier, at: uptimeNanoseconds)
        + processTriggerBands(.right, value: value, for: identifier, at: uptimeNanoseconds)
    case .motion(let sample): return processMotion(sample, for: identifier)
    case .touch(let sample): return processTouch(sample, for: identifier, at: uptimeNanoseconds)
    }
  }

  /// Applies a hat direction as changes of the cardinal d-pad sources.
  ///
  /// Releases come before presses.
  mutating func setDpad(
    _ direction: HatDirection,
    for identifier: LogicalControllerID,
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

  /// Applies several axis values in order.
  mutating func processAxes(
    _ values: [(RemappingAxis, Float)],
    for identifier: LogicalControllerID,
    at uptimeNanoseconds: UInt64
  ) -> [RemappingEngineAction] {
    var actions: [RemappingEngineAction] = []
    for (axis, value) in values {
      actions += processAxis(axis, value: value, for: identifier, at: uptimeNanoseconds)
    }
    return actions
  }

  /// Applies one axis value.
  ///
  /// The raw value is recorded. Axis bindings drive gamepad axis and continuous destinations. The
  /// negative and positive direction sources then follow their threshold and hysteresis. Continuous
  /// output that stopped gets a zero action.
  mutating func processAxis(
    _ axis: RemappingAxis,
    value rawValue: Float,
    for identifier: LogicalControllerID,
    at uptimeNanoseconds: UInt64
  ) -> [RemappingEngineAction] {
    guard var device = devices[identifier] else { return [] }
    device.analog.physicalAxes[axis] = rawValue
    let oldContinuous = continuousTotals()
    var actions: [RemappingEngineAction] = []

    for binding in device.binding(for: .axis(axis))?.expandedActions ?? [] {
      if let tuning = binding.axisTuning, case .gamepadAxis(let destination) = binding.destination {
        let value = RemappingTransform.value(rawValue, tuning: tuning)
        device.analog.virtualAxisBindings.insert(binding.id)
        if let state = device.outputs.gamepad.update(
          RemappingGamepadState(axes: [destination: value]),
          for: binding.id
        ) {
          actions.append(.gamepad(state, identifier))
        }
      }

      actions += midiControlChange(binding, rawValue: rawValue, device: &device)

      if let tuning = binding.axisTuning,
        case .pointerPosition(let pointerAxis) = binding.destination
      {
        actions.append(
          .system(
            .pointerPlaced(
              axis: pointerAxis,
              position: Double(RemappingTransform.value(rawValue, tuning: tuning))
            )
          )
        )
      }

      if let tuning = binding.axisTuning,
        let continuousDestination = RemappingContinuousDestination(binding.destination)
      {
        let transformed = RemappingTransform.value(rawValue, tuning: tuning)
        if transformed == 0 {
          device.outputs.continuous.removeValue(forKey: binding.id)
        } else {
          device.outputs.continuous[binding.id] = RemappingContinuousOutput(
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

  /// Applies a source becoming active or inactive, and returns the output actions.
  ///
  /// Does nothing when the source is already in that state. Chords that end with a release settle
  /// first, and due held-back presses are replayed. The gyro activation and layer activators are
  /// handled next; a layer activator ends the processing. Other sources run their actions, unless a
  /// chord or a held-back press suppresses them. The press then enters the sequence history, and
  /// chords and sequences are evaluated.
  mutating func setSource(
    _ source: RemappingSource,
    isActive: Bool,
    for identifier: LogicalControllerID,
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
        device.motion.gyroToggleActive.toggle()
      }
      if gyroWasActive != device.isGyroActive {
        device.motion.gyroAwaitingBaseline = true
        if !device.isGyroActive { actions += device.clearGyroStick() }
      }
    }

    let oldContinuous = continuousTotals()
    if !device.isPaused,
      let layerActions = handleLayerActivator(source, isActive: isActive, device: &device)
    {
      devices[identifier] = device
      return actions + layerActions + stoppedContinuousActions(previous: oldContinuous)
    }

    let wasConsumed = device.chords.consumedChordSources.contains(source)
    let buffered = isActive && device.bufferChordPress(source, at: uptimeNanoseconds)
    let modifierOwned = device.effectiveChords.contains {
      $0.mode == .modifier && $0.sources.contains(source)
    }
    let suppress =
      buffered || wasConsumed || modifierOwned
      || (isActive && sourceCompletesChord(source, in: device))
    for binding in device.binding(for: source)?.expandedActions ?? []
    where !device.isPaused || binding.destination.isPause {
      actions += processAction(
        binding,
        isActive: isActive,
        suppressed: suppress,
        device: &device,
        at: uptimeNanoseconds
      )
    }
    if isActive && !wasConsumed {
      device.chords.sequenceHistory.append(
        RemappingSequenceHistoryEntry(
          source: source,
          uptime: uptimeNanoseconds,
          awaitingChord: buffered
        )
      )
    }
    if !isActive {
      device.chords.consumedChordSources.remove(source)
      device.chords.replayedChordSources.remove(source)
    }
    actions += processChords(for: &device)
    actions += processSequences(for: &device, at: uptimeNanoseconds)
    devices[identifier] = device
    return actions
  }

  /// Returns the cardinal d-pad directions that a hat direction holds.
  private static func cardinalDirections(for direction: HatDirection) -> Set<RemappingDpadDirection>
  {
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

  /// Orders d-pad directions by their raw value.
  private static func dpadLessThan(
    _ lhs: RemappingDpadDirection,
    _ rhs: RemappingDpadDirection
  ) -> Bool { lhs.rawValue < rhs.rawValue }
}
