import Foundation

private let nanosecondsPerMillisecond: Double = 1_000_000

struct RemappingEngineState {
  var devices: [DeviceIdentifier: RemappingDeviceState] = [:]
  var keyReferences: [RemappingKeyboardKey: Int] = [:]
  var modifierReferences: [RemappingKeyModifier: Int] = [:]
  var mouseButtonReferences: [RemappingMouseButton: Int] = [:]

  mutating func setProfile(_ profile: RemappingProfile?, for identifier: DeviceIdentifier)
    -> [RemappingSystemInputAction]
  {
    guard devices[identifier]?.profile != profile else { return [] }
    let actions = releaseController(identifier)
    if let profile { devices[identifier] = RemappingDeviceState(profile: profile) }
    return actions
  }

  mutating func process(
    events: [ControllerEvent],
    from identifier: DeviceIdentifier,
    profile: RemappingProfile,
    at uptimeNanoseconds: UInt64
  ) -> [RemappingSystemInputAction] {
    var actions = setProfile(profile, for: identifier)
    for event in events {
      actions += process(event: event, from: identifier, at: uptimeNanoseconds)
    }
    return actions
  }

  private mutating func process(
    event: ControllerEvent,
    from identifier: DeviceIdentifier,
    at uptimeNanoseconds: UInt64
  ) -> [RemappingSystemInputAction] {
    switch event {
    case .buttonPressed(let button):
      guard let source = Self.source(for: button) else { return [] }
      return setSource(source, isActive: true, for: identifier, at: uptimeNanoseconds)
    case .buttonReleased(let button):
      guard let source = Self.source(for: button) else { return [] }
      return setSource(source, isActive: false, for: identifier, at: uptimeNanoseconds)
    case .dpadChanged(let direction):
      return setDpad(direction, for: identifier, at: uptimeNanoseconds)
    case .leftStickChanged(let x, let y):
      return processAxes(
        [(.leftStickX, x), (.leftStickY, y)],
        for: identifier,
        at: uptimeNanoseconds
      )
    case .rightStickChanged(let x, let y):
      return processAxes(
        [(.rightStickX, x), (.rightStickY, y)],
        for: identifier,
        at: uptimeNanoseconds
      )
    case .leftTriggerChanged(let value):
      return processAxes([(.leftTrigger, value)], for: identifier, at: uptimeNanoseconds)
    case .rightTriggerChanged(let value):
      return processAxes([(.rightTrigger, value)], for: identifier, at: uptimeNanoseconds)
    }
  }

  private mutating func setDpad(
    _ direction: DpadDirection,
    for identifier: DeviceIdentifier,
    at uptimeNanoseconds: UInt64
  ) -> [RemappingSystemInputAction] {
    guard var device = devices[identifier] else { return [] }
    let nextDirections = Self.cardinalDirections(for: direction)
    let removed = device.dpadDirections.subtracting(nextDirections)
    let added = nextDirections.subtracting(device.dpadDirections)
    device.dpadDirections = nextDirections
    devices[identifier] = device

    var actions: [RemappingSystemInputAction] = []
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
  ) -> [RemappingSystemInputAction] {
    var actions: [RemappingSystemInputAction] = []
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
  ) -> [RemappingSystemInputAction] {
    guard var device = devices[identifier] else { return [] }
    let oldContinuous = continuousTotals()
    var actions: [RemappingSystemInputAction] = []

    if let binding = device.binding(for: .axis(axis)), let tuning = binding.axisTuning,
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

    for direction in [RemappingAxisDirection.negative, .positive] {
      let source = RemappingSource.axisDirection(axis, direction)
      guard let binding = device.binding(for: source), let tuning = binding.axisTuning else {
        continue
      }
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

  private mutating func setSource(
    _ source: RemappingSource,
    isActive: Bool,
    for identifier: DeviceIdentifier,
    at uptimeNanoseconds: UInt64
  ) -> [RemappingSystemInputAction] {
    guard var device = devices[identifier] else { return [] }
    let wasActive = device.activeSources.contains(source)
    guard wasActive != isActive else { return [] }
    if isActive { device.activeSources.insert(source) } else { device.activeSources.remove(source) }

    if let layerActions = handleLayerActivator(source, isActive: isActive, device: &device) {
      devices[identifier] = device
      return layerActions
    }

    guard let binding = device.binding(for: source) else {
      devices[identifier] = device
      var noBindingActions: [RemappingSystemInputAction] = []
      if isActive {
        device.sequenceHistory.append(
          RemappingSequenceHistoryEntry(source: source, uptime: uptimeNanoseconds)
        )
        devices[identifier] = device
      }
      if var updated = devices[identifier] {
        noBindingActions += processChords(for: &updated)
        noBindingActions += processSequences(for: &updated, at: uptimeNanoseconds)
        devices[identifier] = updated
      }
      return noBindingActions
    }

    let hasActivation = binding.longHold != nil || binding.doubleTap != nil
    if !hasActivation {
      var immediateActions: [RemappingSystemInputAction] = []

      let suppressIndividual = isActive && sourceCompletesChord(source, in: device)
      if !suppressIndividual {
        if let turbo = binding.turbo {
          if isActive {
            device.turbos[binding.id] = RemappingTurboOutput(
              destination: binding.destination,
              configuration: turbo,
              startedAt: uptimeNanoseconds,
              outputIsDown: true
            )
            immediateActions += setBinding(
              binding.id,
              destination: binding.destination,
              isDown: true,
              device: &device
            )
          } else {
            device.turbos.removeValue(forKey: binding.id)
            immediateActions += setBinding(
              binding.id,
              destination: binding.destination,
              isDown: false,
              device: &device
            )
          }
        } else {
          immediateActions += setBinding(
            binding.id,
            destination: binding.destination,
            isDown: isActive,
            device: &device
          )
        }
      }

      if isActive {
        device.sequenceHistory.append(
          RemappingSequenceHistoryEntry(source: source, uptime: uptimeNanoseconds)
        )
      }

      devices[identifier] = device

      if var updated = devices[identifier] {
        immediateActions += processChords(for: &updated)
        immediateActions += processSequences(for: &updated, at: uptimeNanoseconds)
        devices[identifier] = updated
      }

      return immediateActions
    }

    var actions: [RemappingSystemInputAction] = []
    var tracker = device.activations[source] ?? RemappingActivationTracker()

    if isActive {
      tracker.pressUptime = uptimeNanoseconds
      tracker.releaseUptime = nil
      tracker.tapCount += 1
      tracker.pendingDefault = true
      tracker.firedBindingID = nil

      if tracker.tapCount >= 2, let doubleTap = binding.doubleTap {
        tracker.pendingDefault = false
        tracker.firedBindingID = binding.id
        actions += setBinding(
          binding.id,
          destination: doubleTap.destination,
          isDown: true,
          device: &device
        )
      }

      device.sequenceHistory.append(
        RemappingSequenceHistoryEntry(source: source, uptime: uptimeNanoseconds)
      )
    } else {
      tracker.releaseUptime = uptimeNanoseconds

      if tracker.firedBindingID != nil, tracker.pendingDefault == false {
        if let longHold = binding.longHold, tracker.firedBindingID == binding.id {
          actions += setBinding(
            binding.id,
            destination: longHold.destination,
            isDown: false,
            device: &device
          )
        } else if let doubleTap = binding.doubleTap, tracker.firedBindingID == binding.id {
          actions += setBinding(
            binding.id,
            destination: doubleTap.destination,
            isDown: false,
            device: &device
          )
        }
        tracker.firedBindingID = nil
      } else if tracker.pendingDefault {
        if binding.doubleTap == nil {
          actions += tapBinding(binding.id, destination: binding.destination, device: &device)
          tracker.pendingDefault = false
        }
      }
    }

    device.activations[source] = tracker
    devices[identifier] = device

    if var updated = devices[identifier] {
      actions += processChords(for: &updated)
      actions += processSequences(for: &updated, at: uptimeNanoseconds)
      devices[identifier] = updated
    }

    return actions
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
    case .l2Digital: .button(.auxiliary1)
    case .r2Digital: .button(.auxiliary2)
    case .genericButton1: .button(.auxiliary1)
    case .genericButton2: .button(.auxiliary2)
    case .genericButton3: .button(.auxiliary3)
    case .genericButton4: .button(.auxiliary4)
    case .genericButton5: .button(.auxiliary5)
    case .genericButton6: .button(.auxiliary6)
    case .genericButton7: .button(.auxiliary7)
    case .genericButton8: .button(.auxiliary8)
    case .dpadUp: .dpad(.up)
    case .dpadDown: .dpad(.down)
    case .dpadLeft: .dpad(.left)
    case .dpadRight: .dpad(.right)
    }
  }

  private static func cardinalDirections(for direction: DpadDirection) -> Set<
    RemappingDpadDirection
  > {
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

  private static func dpadLessThan(_ lhs: RemappingDpadDirection, _ rhs: RemappingDpadDirection)
    -> Bool
  { lhs.rawValue < rhs.rawValue }

  private mutating func handleLayerActivator(
    _ source: RemappingSource,
    isActive: Bool,
    device: inout RemappingDeviceState
  ) -> [RemappingSystemInputAction]? {
    let profile = device.profile
    var actions: [RemappingSystemInputAction] = []
    var handled = false

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
          } else {
            device.layerToggleState.insert(layer.id)
          }
        }
      }
    }

    guard handled else { return nil }

    actions += processChords(for: &device)
    return actions
  }

  private func sourceCompletesChord(_ source: RemappingSource, in device: RemappingDeviceState)
    -> Bool
  {
    let activeSources = device.activeSources
    let profile = device.profile
    for chord in profile.chords where chord.sources.contains(source) {
      if chord.sources.isSubset(of: activeSources) { return true }
    }
    for layerID in device.activeLayers {
      guard let layer = profile.layers.first(where: { $0.id == layerID }) else { continue }
      for chord in layer.chords where chord.sources.contains(source) {
        if chord.sources.isSubset(of: activeSources) { return true }
      }
    }
    return false
  }

  private mutating func processChords(for device: inout RemappingDeviceState)
    -> [RemappingSystemInputAction]
  {
    var actions: [RemappingSystemInputAction] = []
    let activeSources = device.activeSources
    let profile = device.profile

    var allChords: [(chord: RemappingChord, bindingID: UUID)] = []
    for chord in profile.chords { allChords.append((chord, chord.id)) }
    for layerID in device.activeLayers {
      guard let layer = profile.layers.first(where: { $0.id == layerID }) else { continue }
      for chord in layer.chords { allChords.append((chord, chord.id)) }
    }

    var newActiveChords: Set<UUID> = []
    for (chord, id) in allChords {
      let isFullyActive = chord.sources.isSubset(of: activeSources)
      let wasActive = device.activeChords.contains(id)
      if isFullyActive && !wasActive {
        newActiveChords.insert(id)
        device.activeChords.insert(id)
        actions += setBinding(id, destination: chord.destination, isDown: true, device: &device)
      } else if isFullyActive {
        newActiveChords.insert(id)
      } else if wasActive {
        device.activeChords.remove(id)
        actions += setBinding(id, destination: chord.destination, isDown: false, device: &device)
      }
    }
    device.activeChords = newActiveChords
    return actions
  }

  /// Checks if recent input history matches any defined sequence.
  private mutating func processSequences(
    for device: inout RemappingDeviceState,
    at uptimeNanoseconds: UInt64
  ) -> [RemappingSystemInputAction] {
    var actions: [RemappingSystemInputAction] = []
    let profile = device.profile

    var allSequences: [RemappingSequence] = profile.sequences
    for layerID in device.activeLayers {
      guard let layer = profile.layers.first(where: { $0.id == layerID }) else { continue }
      allSequences.append(contentsOf: layer.sequences)
    }

    let maxWindow = allSequences.map { UInt64($0.windowMs * nanosecondsPerMillisecond) }.max() ?? 0
    if maxWindow > 0 {
      while let first = device.sequenceHistory.first, uptimeNanoseconds > first.uptime,
        uptimeNanoseconds - first.uptime > maxWindow
      { device.sequenceHistory.removeFirst() }
    }

    for sequence in allSequences {
      let sources = sequence.sources
      guard device.sequenceHistory.count >= sources.count else { continue }
      let windowNs = UInt64(sequence.windowMs * nanosecondsPerMillisecond)
      let tail = Array(device.sequenceHistory.suffix(sources.count))

      guard tail.count == sources.count else { continue }
      let matches = zip(tail, sources).allSatisfy { $0.0.source == $0.1 }
      guard matches else { continue }

      guard let firstUptime = tail.first?.uptime else { continue }
      guard uptimeNanoseconds <= firstUptime + windowNs else { continue }

      actions += tapBinding(sequence.id, destination: sequence.destination, device: &device)

      device.sequenceHistory.removeAll()
      break
    }

    return actions
  }
}

struct RemappingDeviceState {
  let profile: RemappingProfile
  var activeSources: Set<RemappingSource> = []
  var dpadDirections: Set<RemappingDpadDirection> = []
  var heldBindings: [UUID: RemappingDestination] = [:]
  var turbos: [UUID: RemappingTurboOutput] = [:]
  var continuous: [UUID: RemappingContinuousOutput] = [:]
  var activations: [RemappingSource: RemappingActivationTracker] = [:]
  var activeChords: Set<UUID> = []
  var sequenceHistory: [RemappingSequenceHistoryEntry] = []
  var activeLayers: [UUID] = []
  var layerToggleState: Set<UUID> = []

  func binding(for source: RemappingSource) -> RemappingBinding? {
    let activeLayerIDs = Set(activeLayers).union(layerToggleState)
    for layerID in activeLayerIDs.reversed() {
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
}
