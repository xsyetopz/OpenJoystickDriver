import Foundation

extension RemappingEngineState {
  /// Runs a `ProfileSwitch`, `LayerSet` or `Pause` destination on its press.
  mutating func runProfileControl(
    _ destination: RemappingDestination,
    device: inout RemappingDeviceState
  ) -> [RemappingEngineAction] {
    switch destination {
    case .profileSwitch(let target):
      [.profileSwitch(target, from: device.profile.id, device.identifier)]
    case .layerSet(let layer, let mode): setLayer(layer, mode: mode, device: &device)
    case .pause(let mode): setPause(mode, device: &device)
    default: []
    }
  }

  /// Stops the speech of a controller that is speaking.
  mutating func stopSpeech(device: inout RemappingDeviceState) -> [RemappingEngineAction] {
    guard device.outputs.isSpeaking else { return [] }
    device.outputs.isSpeaking = false
    return [.stopSpeech(device.identifier)]
  }

  /// Turns a layer on, off or flips it, and releases the outputs of bindings that stop applying.
  private mutating func setLayer(
    _ layer: UUID,
    mode: RemappingSwitchMode,
    device: inout RemappingDeviceState
  ) -> [RemappingEngineAction] {
    let isOn = device.layers.activeLayers.contains(layer)
    guard mode.apply(to: isOn) != isOn else { return [] }
    if isOn {
      device.layers.activeLayers.removeAll { $0 == layer }
      device.layers.layerToggleState.remove(layer)
    } else {
      device.layers.activeLayers.append(layer)
      device.layers.layerToggleState.insert(layer)
    }
    return reconcileLayerOutputs(device: &device)
  }

  /// Pauses or resumes a controller.
  ///
  /// A pause releases every output the profile holds, macros included, and drops its layers and
  /// chord state; the unmapped controller then passes through.
  private mutating func setPause(
    _ mode: RemappingSwitchMode,
    device: inout RemappingDeviceState
  ) -> [RemappingEngineAction] {
    guard mode.apply(to: device.isPaused) != device.isPaused else { return [] }
    device.isPaused.toggle()
    guard device.isPaused else { return [] }
    var actions = stopMacros(device: &device) + stopSpeech(device: &device)
    for id in device.outputs.heldBindings.keys.sorted(by: Self.uuidLessThan) {
      guard let destination = device.outputs.heldBindings[id], !destination.isPause else {
        continue
      }
      actions += setBinding(id, destination: destination, isDown: false, device: &device)
    }
    if let state = device.outputs.gamepad.drain() {
      actions.append(.gamepad(state, device.identifier))
    }
    device.analog.virtualAxisBindings.removeAll()
    device.outputs.turbos.removeAll()
    device.outputs.continuous.removeAll()
    device.outputs.activations.removeAll()
    device.outputs.pulseDeadlines.removeAll()
    device.outputs.armedReleaseBindings.removeAll()
    device.layers = RemappingLayerState()
    device.chords = RemappingChordState()
    return actions
  }
}
