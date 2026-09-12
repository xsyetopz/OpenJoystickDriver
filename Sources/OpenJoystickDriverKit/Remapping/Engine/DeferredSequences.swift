import Foundation

struct RemappingDeferredSequence {
  let sequence: RemappingSequence
  var awaitingSources: Set<RemappingSource>
}

extension RemappingEngineState {
  mutating func commitDeferredSequences(device: inout RemappingDeviceState)
    -> [RemappingEngineAction]
  {
    let ready = device.deferredSequences.filter { $0.awaitingSources.isEmpty }
    device.deferredSequences.removeAll { $0.awaitingSources.isEmpty }
    return ready.flatMap {
      tapBinding($0.sequence.id, destination: $0.sequence.destination, device: &device)
    }
  }
}
