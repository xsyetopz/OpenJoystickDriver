import Foundation

extension RemappingDeviceState {
  /// Returns the tuning that applies to the direction of a source, or `nil` when nothing uses the
  /// source.
  ///
  /// A binding supplies its own tuning. A source used only as the gyro activation source, a
  /// trackball source, a chord or sequence member, or a layer activator gets the default tuning.
  func directionTuning(for source: RemappingSource) -> RemappingAxisTuning? {
    if let tuning = binding(for: source)?.axisTuning { return tuning }
    if profile.gyroOutput.activationSource == source
      || profile.gyroOutput.trackball?.source == source
    {
      return .default
    }
    if profile.chords.contains(where: { $0.sources.contains(source) })
      || profile.sequences.contains(where: { $0.sources.contains(source) })
    {
      return .default
    }
    for layer in profile.layers
    where layer.activator == source || layer.chords.contains(where: { $0.sources.contains(source) })
      || layer.sequences.contains(where: { $0.sources.contains(source) })
    { return .default }
    return nil
  }
}
