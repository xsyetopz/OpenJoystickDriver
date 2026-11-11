import Foundation

/// Chord, sequence and held-back press state of one controller.
struct RemappingChordState {
  /// Source presses held back until a simultaneous chord completes or the press resolves.
  var pendingChordPresses: [RemappingPendingChordPress] = []
  /// Sources claimed by a chord, or held back when the layers change, that other chords cannot
  /// match.
  var consumedChordSources: Set<RemappingSource> = []
  /// Sources whose held-back press was replayed as a normal press.
  var replayedChordSources: Set<RemappingSource> = []
  /// Identifiers of the chords that are active.
  var activeChords: Set<UUID> = []
  /// Recent source presses that sequences are matched against.
  var sequenceHistory: [RemappingSequenceHistoryEntry] = []
  /// Completed sequences that wait for held-back presses to resolve.
  var deferredSequences: [RemappingDeferredSequence] = []
}

/// One source press in the sequence history.
struct RemappingSequenceHistoryEntry: Equatable {
  /// Source that was pressed.
  let source: RemappingSource
  /// Uptime of the press, in nanoseconds.
  let uptime: UInt64
  /// Whether the press is held back as a possible chord member.
  var awaitingChord: Bool = false
}
