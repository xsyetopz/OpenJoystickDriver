import Foundation

/// A completed sequence that waits for chord presses to resolve before it fires.
struct RemappingDeferredSequence {
  /// Sequence that matched.
  let sequence: RemappingSequence
  /// Sources whose held-back chord press has not resolved yet.
  var awaitingSources: Set<RemappingSource>
}

extension RemappingEngineState {
  /// Taps the destination of each deferred sequence that stopped awaiting a source, and drops it.
  mutating func commitDeferredSequences(
    device: inout RemappingDeviceState
  ) -> [RemappingEngineAction] {
    let ready = device.chords.deferredSequences.filter { $0.awaitingSources.isEmpty }
    device.chords.deferredSequences.removeAll { $0.awaitingSources.isEmpty }
    return ready.flatMap {
      tapBinding($0.sequence.id, destination: $0.sequence.destination, device: &device)
    }
  }
}
