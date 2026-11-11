import Foundation

extension RemappingEngineState {
  /// Releases the outputs whose owner stops applying after the active layers change.
  ///
  /// The owners that stay are the actions of the bindings that apply now, the profile chords and
  /// the chords of active layers. Held bindings and virtual axis contributions of other owners are
  /// released, and their timers, repeats and active chord state are dropped.
  mutating func reconcileLayerOutputs(device: inout RemappingDeviceState) -> [RemappingEngineAction]
  {
    let profile = device.profile
    let sources = Set(profile.bindings.map(\.source)).union(
      profile.layers.flatMap { $0.bindings.map(\.source) }
    )
    var retained = Set(sources.flatMap { device.binding(for: $0)?.expandedActions.map(\.id) ?? [] })
    retained.formUnion(profile.chords.map(\.id))
    let activeIDs = Set(device.layers.activeLayers)
    for layer in profile.layers where activeIDs.contains(layer.id) {
      retained.formUnion(layer.chords.map(\.id))
    }
    var actions: [RemappingEngineAction] = []
    for id in device.outputs.heldBindings.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
      guard !retained.contains(id), let destination = device.outputs.heldBindings[id] else {
        continue
      }
      actions += setBinding(id, destination: destination, isDown: false, device: &device)
    }
    for id in device.analog.virtualAxisBindings.sorted(by: { $0.uuidString < $1.uuidString })
    where !retained.contains(id) {
      if let state = device.outputs.gamepad.release(id) {
        actions.append(.gamepad(state, device.identifier))
      }
      device.analog.virtualAxisBindings.remove(id)
    }
    device.outputs.activations = device.outputs.activations.filter { retained.contains($0.key) }
    device.outputs.turbos = device.outputs.turbos.filter { retained.contains($0.key) }
    device.outputs.continuous = device.outputs.continuous.filter { retained.contains($0.key) }
    device.chords.activeChords.formIntersection(retained)
    device.outputs.armedReleaseBindings.formIntersection(retained)
    device.outputs.pulseDeadlines = device.outputs.pulseDeadlines.filter {
      retained.contains($0.key)
    }
    return actions
  }
}

extension RemappingDeviceState {
  /// Motion tuning that applies now.
  ///
  /// It is the tuning of the most recently activated layer that has one, otherwise the profile's
  /// tuning.
  var effectiveMotionTuning: RemappingMotionTuning {
    for id in layers.activeLayers.reversed() {
      if let tuning = profile.layers.first(where: { $0.id == id })?.motionTuning { return tuning }
    }
    return profile.motionTuning
  }
}
