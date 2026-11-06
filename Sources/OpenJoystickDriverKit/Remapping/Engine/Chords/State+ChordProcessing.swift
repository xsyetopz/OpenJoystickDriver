import Foundation

extension RemappingEngineState {

  /// Handles a source change of a layer activator.
  ///
  /// Returns `nil` when the source activates no layer, and an empty list when the active layers do
  /// not change. A hold layer is active while its activator is. A toggle layer switches on every
  /// press. A layer change that changes the motion tuning also clears the gyro and motion outputs
  /// and resets motion calibration. Every layer change releases the outputs that stopped applying,
  /// clears the sequence history and turns held-back presses into replayed ones.
  mutating func handleLayerActivator(
    _ source: RemappingSource,
    isActive: Bool,
    device: inout RemappingDeviceState
  ) -> [RemappingEngineAction]? {
    let profile = device.profile
    var actions: [RemappingEngineAction] = []
    var handled = false
    let previousTuning = device.effectiveMotionTuning
    let previousLayers = device.layers.activeLayers

    for layer in profile.layers where layer.activator == source {
      handled = true
      switch layer.activationMode {
      case .hold:
        if isActive {
          if !device.layers.activeLayers.contains(layer.id) {
            device.layers.activeLayers.append(layer.id)
          }
        } else {
          device.layers.activeLayers.removeAll { $0 == layer.id }
        }
      case .toggle:
        if isActive {
          if device.layers.layerToggleState.contains(layer.id) {
            device.layers.layerToggleState.remove(layer.id)
            device.layers.activeLayers.removeAll { $0 == layer.id }
          } else {
            device.layers.layerToggleState.insert(layer.id)
            device.layers.activeLayers.append(layer.id)
          }
        }
      }
    }

    guard handled else { return nil }
    guard previousLayers != device.layers.activeLayers else { return [] }
    if previousTuning != device.effectiveMotionTuning {
      actions += device.clearGyroStick()
      actions += device.clearMotionSteering()
      device.motion.motionStickDeadline = nil
      for direction in device.motion.activeMotionLeans {
        let source = RemappingSource.motionLean(direction)
        actions += cancelActions(for: [source], device: &device)
        device.activeSources.remove(source)
        device.sourcePressTimes.removeValue(forKey: source)
      }
      device.motion.activeMotionLeans.removeAll()
      device.motion.motion.resetCalibration()
      device.motion.gyroAwaitingBaseline = true
    }
    actions += reconcileLayerOutputs(device: &device)
    device.chords.sequenceHistory.removeAll()
    device.chords.deferredSequences.removeAll()
    device.chords.replayedChordSources.formUnion(device.chords.pendingChordPresses.map(\.source))
    device.chords.consumedChordSources.formUnion(device.chords.pendingChordPresses.map(\.source))
    device.chords.pendingChordPresses.removeAll()

    actions += processChords(for: &device)
    return actions
  }

  /// Whether a source belongs to a chord that is selected now.
  func sourceCompletesChord(_ source: RemappingSource, in device: RemappingDeviceState) -> Bool {
    device.selectedChords().contains { $0.sources.contains(source) }
  }

  /// Starts the chords that became selected and releases the chords that stopped being selected.
  ///
  /// Starting a chord cancels the actions of its sources and clears their held-back presses and
  /// sequence history.
  mutating func processChords(
    for device: inout RemappingDeviceState,
    releasing source: RemappingSource? = nil
  ) -> [RemappingEngineAction] {
    let selected = device.selectedChords(releasing: source)
    let selectedIDs = Set(selected.map(\.id))
    var actions: [RemappingEngineAction] = []
    let retiredIDs = device.chords.activeChords.subtracting(selectedIDs).sorted {
      $0.uuidString < $1.uuidString
    }
    for id in retiredIDs {
      guard let destination = device.outputs.heldBindings[id] else { continue }
      actions += setBinding(id, destination: destination, isDown: false, device: &device)
    }
    for chord in selected where !device.chords.activeChords.contains(chord.id) {
      actions += cancelActions(for: chord.sources, device: &device)
      device.chords.sequenceHistory.removeAll { chord.sources.contains($0.source) }
      device.chords.deferredSequences.removeAll {
        !$0.awaitingSources.isDisjoint(with: chord.sources)
      }
      device.chords.pendingChordPresses.removeAll { chord.sources.contains($0.source) }
      device.chords.consumedChordSources.formUnion(chord.sources)
      actions += setBinding(chord.id, destination: chord.destination, isDown: true, device: &device)
    }
    device.chords.activeChords = selectedIDs
    return actions
  }

  /// Checks recent input history against the sequences that apply and fires the first one that
  /// matches.
  ///
  /// A sequence matches when the latest history entries equal its sources in order, inside its
  /// window. It taps its destination at once, or after the held-back presses of its entries
  /// resolve.
  mutating func processSequences(
    for device: inout RemappingDeviceState,
    at uptimeNanoseconds: UInt64
  ) -> [RemappingEngineAction] {
    var actions = commitDeferredSequences(device: &device)
    let allSequences = device.effectiveSequences

    for sequence in allSequences {
      let sources = sequence.sources
      guard device.chords.sequenceHistory.count >= sources.count else { continue }
      let windowNs = UInt64(sequence.windowMs * remappingStateNanosecondsPerMillisecond)
      let tail = Array(device.chords.sequenceHistory.suffix(sources.count))

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
        device.chords.deferredSequences.append(
          RemappingDeferredSequence(sequence: sequence, awaitingSources: awaitingSources)
        )
      }
      // Each deferred match owns at least one pending press, which this clear removes
      // from history. It cannot create another match until that press resolves.
      device.chords.sequenceHistory.removeAll()
      break
    }

    device.pruneSequenceHistory(at: uptimeNanoseconds)
    return actions
  }
}
