import Foundation

extension RemappingDeviceState {
  /// Sequences that apply now: the profile's sequences, then those of each active layer.
  var effectiveSequences: [RemappingSequence] {
    profile.sequences
      + layers.activeLayers.flatMap { id in profile.layers.first { $0.id == id }?.sequences ?? [] }
  }

  /// Time at which the oldest history entry falls out of every sequence window, or `nil` when there
  /// is nothing to expire.
  ///
  /// There is nothing to expire when the history is empty, an entry awaits a chord, or no sequence
  /// applies.
  var sequenceHistoryDeadline: UInt64? {
    guard !chords.sequenceHistory.contains(where: \.awaitingChord),
      let first = chords.sequenceHistory.first,
      let window = effectiveSequences.map(\.windowMs).max()
    else { return nil }
    let (end, overflow) = first.uptime.addingReportingOverflow(UInt64(window * 1_000_000))
    guard !overflow, end < UInt64.max else { return UInt64.max }
    // The configured window includes its last nanosecond.
    return end + 1
  }

  /// Drops history entries that no sequence can use any more.
  ///
  /// The history keeps at most as many entries as the longest sequence has sources, plus one for
  /// each held-back press. Entries expire after the longest window, measured from the oldest entry
  /// that awaits a chord when there is one.
  mutating func pruneSequenceHistory(at uptime: UInt64) {
    let sequences = effectiveSequences
    let capacity =
      (sequences.map { $0.sources.count }.max() ?? 0)
      + (sequences.isEmpty ? 0 : chords.pendingChordPresses.count)
    if chords.sequenceHistory.count > capacity {
      chords.sequenceHistory.removeFirst(chords.sequenceHistory.count - capacity)
    }
    guard let window = sequences.map(\.windowMs).max() else { return }
    let duration = UInt64(window * 1_000_000)
    let retentionUptime = min(
      uptime,
      chords.sequenceHistory.first(where: \.awaitingChord)?.uptime ?? uptime
    )
    chords.sequenceHistory.removeAll {
      retentionUptime >= $0.uptime
        && (retentionUptime - $0.uptime > duration || retentionUptime == UInt64.max)
    }
  }
}
