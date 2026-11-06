import Foundation

extension RemappingEngineState {
  /// Releases the held bindings and turbo repeats of this controller that drive a destination.
  ///
  /// Pulse deadlines of those bindings are cleared with them.
  mutating func releaseDestination(
    _ destination: RemappingDestination,
    device: inout RemappingDeviceState
  ) -> [RemappingEngineAction] {
    let held = device.outputs.heldBindings.filter { $0.value == destination }.keys
    let repeating = device.outputs.turbos.filter { $0.value.destination == destination }.keys
    let identifiers = Set(held).union(repeating)
    var actions: [RemappingEngineAction] = []
    for id in identifiers.sorted(by: { $0.uuidString < $1.uuidString }) {
      device.outputs.turbos.removeValue(forKey: id)
      device.outputs.pulseDeadlines.removeValue(forKey: id)
      actions += setBinding(id, destination: destination, isDown: false, device: &device)
    }
    return actions
  }
}
