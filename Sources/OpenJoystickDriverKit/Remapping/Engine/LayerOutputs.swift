import Foundation

extension RemappingEngineState {
  /// Releases contributions that no longer belong to the selected layer bindings.
  mutating func reconcileLayerOutputs(device: inout RemappingDeviceState)
    -> [RemappingEngineAction]
  {
    let profile = device.profile
    let sources = Set(profile.bindings.map(\.source))
      .union(profile.layers.flatMap { $0.bindings.map(\.source) })
    var retained = Set(sources.flatMap { device.binding(for: $0)?.expandedActions.map(\.id) ?? [] })
    retained.formUnion(profile.chords.map(\.id))
    let activeIDs = Set(device.activeLayers)
    for layer in profile.layers where activeIDs.contains(layer.id) {
      retained.formUnion(layer.chords.map(\.id))
    }
    var actions: [RemappingEngineAction] = []
    for id in device.heldBindings.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
      guard !retained.contains(id), let destination = device.heldBindings[id] else { continue }
      actions += setBinding(id, destination: destination, isDown: false, device: &device)
    }
    for id in device.virtualAxisBindings.sorted(by: { $0.uuidString < $1.uuidString }) {
      guard !retained.contains(id) else { continue }
      if let state = device.gamepad.release(id) {
        actions.append(.gamepad(state, device.identifier))
      }
      device.virtualAxisBindings.remove(id)
    }
    device.activations = device.activations.filter { retained.contains($0.key) }
    device.turbos = device.turbos.filter { retained.contains($0.key) }
    device.continuous = device.continuous.filter { retained.contains($0.key) }
    device.activeChords.formIntersection(retained)
    device.armedReleaseBindings.formIntersection(retained)
    device.pulseDeadlines = device.pulseDeadlines.filter { retained.contains($0.key) }
    return actions
  }
}

extension RemappingDeviceState {
  var effectiveMotionTuning: RemappingMotionTuning {
    for id in activeLayers.reversed() {
      if let tuning = profile.layers.first(where: { $0.id == id })?.motionTuning {
        return tuning
      }
    }
    return profile.motionTuning
  }
}
