import Foundation

/// A source press held back while a chord may still complete.
struct RemappingPendingChordPress {
  /// Source that was pressed.
  let source: RemappingSource
  /// Uptime of the press, in nanoseconds.
  let uptime: UInt64
  /// Uptime at which the press is replayed if no chord completes.
  let deadline: UInt64
  /// Raw axis value when the source is an axis direction, so the replay can restore it.
  let axisValue: Float?
}

extension RemappingDeviceState {
  /// Earliest time at which a held-back press resolves, or `nil` when none is held back.
  var pendingChordDeadline: UInt64? {
    chords.pendingChordPresses.map { resolvedDeadline($0) }.min()
  }

  /// Returns the time at which a held-back press resolves.
  ///
  /// It is the deadline of a chord that may still complete with the press source, otherwise the
  /// deadline of the press.
  func resolvedDeadline(_ press: RemappingPendingChordPress) -> UInt64 {
    deferredChordDeadline(for: press.source) ?? press.deadline
  }

  /// Holds back a press when a simultaneous chord contains the source, and reports whether it did.
  ///
  /// The press waits for the longest window among those chords.
  mutating func bufferChordPress(_ source: RemappingSource, at uptime: UInt64) -> Bool {
    let windows = effectiveChords.filter { $0.mode == .simultaneous && $0.sources.contains(source) }
      .map(\.windowMs)
    guard let window = windows.max() else { return false }
    let (end, overflow) = uptime.addingReportingOverflow(UInt64(window * 1_000_000) + 1)
    let axisValue: Float?
    if case .axisDirection(let axis, _) = source {
      axisValue = analog.physicalAxes[axis]
    } else {
      axisValue = nil
    }
    chords.pendingChordPresses.append(
      RemappingPendingChordPress(
        source: source,
        uptime: uptime,
        deadline: overflow ? .max : end,
        axisValue: axisValue
      )
    )
    return true
  }
}

extension RemappingEngineState {
  /// Replays the held-back presses that are due, or that belong to the `source` being released, as
  /// normal presses.
  mutating func replayPendingChordPresses(
    device: inout RemappingDeviceState,
    at uptime: UInt64,
    releasing source: RemappingSource? = nil
  ) -> [RemappingEngineAction] {
    let ready = device.chords.pendingChordPresses.filter {
      device.resolvedDeadline($0) <= uptime || $0.source == source
    }
    let readySources = Set(ready.map(\.source))
    device.chords.pendingChordPresses.removeAll { readySources.contains($0.source) }
    var actions: [RemappingEngineAction] = []
    for press in ready {
      device.chords.replayedChordSources.insert(press.source)
      for binding in device.binding(for: press.source)?.expandedActions ?? [] {
        actions += processAction(
          binding,
          isActive: true,
          suppressed: false,
          device: &device,
          at: press.uptime
        )
      }
      for index in device.chords.sequenceHistory.indices {
        if device.chords.sequenceHistory[index].source == press.source,
          device.chords.sequenceHistory[index].uptime == press.uptime
        {
          device.chords.sequenceHistory[index].awaitingChord = false
        }
      }
      for index in device.chords.deferredSequences.indices {
        device.chords.deferredSequences[index].awaitingSources.remove(press.source)
      }
      actions += processSequences(for: &device, at: uptime)
      let replayAxis: (RemappingAxis, Float)?
      if press.source == source, case .axisDirection(let axis, _) = press.source,
        let value = press.axisValue
      {
        replayAxis = (axis, value)
      } else {
        replayAxis = nil
      }
      actions += device.updatePassthrough(replayingAxis: replayAxis)
    }
    return actions
  }
}
