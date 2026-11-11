import Foundation

extension RemappingDeviceState {
  /// Chords that apply now.
  ///
  /// A chord of an active layer replaces the profile chord with the same sources, and is added when
  /// no profile chord has them.
  var effectiveChords: [RemappingChord] {
    guard !isPaused else { return [] }
    var chords = profile.chords
    for layerID in layers.activeLayers {
      guard let layer = profile.layers.first(where: { $0.id == layerID }) else { continue }
      for chord in layer.chords {
        if let index = chords.firstIndex(where: { $0.sources == chord.sources }) {
          chords[index] = chord
        } else {
          chords.append(chord)
        }
      }
    }
    return chords
  }

  /// Effective chords ordered by source count, largest first, then by profile order.
  private var prioritizedChords: [RemappingChord] {
    effectiveChords.enumerated().sorted {
      if $0.element.sources.count != $1.element.sources.count {
        return $0.element.sources.count > $1.element.sources.count
      }
      return $0.offset < $1.offset
    }.map(\.element)
  }

  /// Returns the chords that are selected now, largest first.
  ///
  /// A chord is selected when it matches, shares no source with a chord already selected, and no
  /// earlier chord that shares a source can still complete. A chord that contains the `source`
  /// being released skips the last condition.
  func selectedChords(releasing source: RemappingSource? = nil) -> [RemappingChord] {
    let candidates = prioritizedChords
    var consumed: Set<RemappingSource> = []
    return candidates.enumerated().compactMap { index, chord in
      guard matches(chord), consumed.isDisjoint(with: chord.sources) else { return nil }
      let isClosing = source.map { chord.sources.contains($0) } ?? false
      guard
        isClosing
          || !candidates.prefix(index).contains(where: {
            !$0.sources.isDisjoint(with: chord.sources) && completionDeadline($0) != nil
          })
      else { return nil }
      consumed.formUnion(chord.sources)
      return chord
    }
  }

  /// Returns the latest time at which a larger chord that shares a source with a matching chord of
  /// `source` may still complete, or `nil` when none can.
  func deferredChordDeadline(for source: RemappingSource) -> UInt64? {
    let candidates = prioritizedChords
    var deadline: UInt64?
    for (index, chord) in candidates.enumerated() where chord.sources.contains(source) {
      guard matches(chord) else { continue }
      for higher in candidates.prefix(index) where !higher.sources.isDisjoint(with: chord.sources) {
        guard let end = completionDeadline(higher) else { continue }
        deadline = max(deadline ?? end, end)
      }
    }
    return deadline
  }

  /// Returns the end of the window in which a simultaneous chord can still complete, or `nil` when
  /// it cannot.
  ///
  /// A chord cannot complete when it is not simultaneous, already matches, has a replayed source,
  /// has all sources active, has no pressed source, or its window has ended.
  private func completionDeadline(_ chord: RemappingChord) -> UInt64? {
    guard chord.mode == .simultaneous, !matches(chord),
      chord.sources.isDisjoint(with: chords.replayedChordSources),
      !chord.sources.isSubset(of: activeSources),
      let first = chord.sources.compactMap({ sourcePressTimes[$0] }).min()
    else { return nil }
    let (end, overflow) = first.addingReportingOverflow(UInt64(chord.windowMs * 1_000_000) + 1)
    let deadline: UInt64 = overflow ? .max : end
    return lastUptime < deadline ? deadline : nil
  }

  /// Whether a chord is satisfied.
  ///
  /// All sources are active and none is claimed by another recognizer. A simultaneous chord also
  /// needs no replayed source and all its presses inside its window.
  func matches(_ chord: RemappingChord) -> Bool {
    guard chord.sources.isSubset(of: activeSources) else { return false }
    let activeChordSources = effectiveChords.filter { chords.activeChords.contains($0.id) }.reduce(
      into: Set<RemappingSource>()
    ) { $0.formUnion($1.sources) }
    let consumedByOtherRecognizers = chords.consumedChordSources.subtracting(activeChordSources)
    guard
      chords.activeChords.contains(chord.id)
        || chord.sources.isDisjoint(with: consumedByOtherRecognizers)
    else { return false }
    guard chord.mode == .simultaneous else { return true }
    guard chord.sources.isDisjoint(with: chords.replayedChordSources) else { return false }
    let times = chord.sources.compactMap { sourcePressTimes[$0] }
    guard times.count == chord.sources.count, let first = times.min(), let last = times.max() else {
      return false
    }
    return last - first <= UInt64(chord.windowMs * 1_000_000)
  }
}
