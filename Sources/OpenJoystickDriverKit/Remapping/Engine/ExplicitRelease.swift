import Foundation

extension RemappingEngineState {
  /// Cancels matching contributions owned by this exact controller.
  mutating func releaseDestination(
    _ destination: RemappingDestination, device: inout RemappingDeviceState
  ) -> [RemappingEngineAction] {
    let held = device.heldBindings.filter { $0.value == destination }.keys
    let repeating = device.turbos.filter { $0.value.destination == destination }.keys
    let identifiers = Set(held).union(repeating)
    var actions: [RemappingEngineAction] = []
    for id in identifiers.sorted(by: { $0.uuidString < $1.uuidString }) {
      device.turbos.removeValue(forKey: id)
      device.pulseDeadlines.removeValue(forKey: id)
      actions += setBinding(id, destination: destination, isDown: false, device: &device)
    }
    return actions
  }
}
