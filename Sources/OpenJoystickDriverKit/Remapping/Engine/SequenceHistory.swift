import Foundation

extension RemappingDeviceState {
  var effectiveSequences: [RemappingSequence] {
    profile.sequences + activeLayers.flatMap { id in
      profile.layers.first { $0.id == id }?.sequences ?? []
    }
  }

  var sequenceHistoryDeadline: UInt64? {
    guard !sequenceHistory.contains(where: \.awaitingChord),
      let first = sequenceHistory.first,
      let window = effectiveSequences.map(\.windowMs).max()
    else { return nil }
    let (end, overflow) = first.uptime.addingReportingOverflow(UInt64(window * 1_000_000))
    guard !overflow, end < UInt64.max else { return UInt64.max }
    // The configured window includes its last nanosecond.
    return end + 1
  }

  mutating func pruneSequenceHistory(at uptime: UInt64) {
    let sequences = effectiveSequences
    let capacity = (sequences.map { $0.sources.count }.max() ?? 0)
      + (sequences.isEmpty ? 0 : pendingChordPresses.count)
    if sequenceHistory.count > capacity {
      sequenceHistory.removeFirst(sequenceHistory.count - capacity)
    }
    guard let window = sequences.map(\.windowMs).max() else { return }
    let duration = UInt64(window * 1_000_000)
    let retentionUptime = min(
      uptime, sequenceHistory.first(where: \.awaitingChord)?.uptime ?? uptime
    )
    sequenceHistory.removeAll {
      retentionUptime >= $0.uptime
        && (retentionUptime - $0.uptime > duration || retentionUptime == UInt64.max)
    }
  }
}
