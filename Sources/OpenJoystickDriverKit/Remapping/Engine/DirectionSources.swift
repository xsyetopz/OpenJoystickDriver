import Foundation

extension RemappingDeviceState {
  /// Combination-only directions use the same default threshold and hysteresis as bindings.
  func directionTuning(for source: RemappingSource) -> RemappingAxisTuning? {
    if let tuning = binding(for: source)?.axisTuning { return tuning }
    if profile.gyroOutput.activationSource == source
      || profile.gyroOutput.trackball?.source == source
    { return .default }
    if profile.chords.contains(where: { $0.sources.contains(source) })
      || profile.sequences.contains(where: { $0.sources.contains(source) })
    {
      return .default
    }
    for layer in profile.layers {
      if layer.activator == source
        || layer.chords.contains(where: { $0.sources.contains(source) })
        || layer.sequences.contains(where: { $0.sources.contains(source) })
      {
        return .default
      }
    }
    return nil
  }
}
