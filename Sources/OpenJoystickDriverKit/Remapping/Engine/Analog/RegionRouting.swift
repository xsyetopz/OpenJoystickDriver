import Foundation

extension RemappingEngineState {
  /// Moves the active region of a stick to the one that contains the stick position.
  ///
  /// The position is the calibrated one of the stick mapping, or of the default tuning without a
  /// mapping, so the dead zone applies as for every other stick output.
  mutating func processStickRegions(
    _ stick: RemappingStickSource,
    x: Float,
    y: Float,
    for identifier: LogicalControllerID,
    at uptime: UInt64
  ) -> [RemappingEngineAction] {
    guard let profile = devices[identifier]?.profile else { return [] }
    let tuning = profile.stickMappings.first { $0.source == stick }?.tuning ?? .default
    let position = RemappingStickTransform.value(x: Double(x), y: Double(y), tuning: tuning)
    let regions = profile.allSources.compactMap { source -> RemappingStickRegionSource? in
      guard case .stickRegion(let region) = source, region.stick == stick else { return nil }
      return region
    }
    return moveRegion(among: regions, as: RemappingSource.stickRegion, for: identifier, at: uptime)
    {
      guard let position else { return false }
      return $0.contains(x: position.x, y: position.y, wasActive: $1)
    }
  }

  /// Moves the active band of a trigger to the one that contains the pull.
  mutating func processTriggerBands(
    _ trigger: RemappingTriggerSource,
    value: Float,
    for identifier: LogicalControllerID,
    at uptime: UInt64
  ) -> [RemappingEngineAction] {
    guard let profile = devices[identifier]?.profile else { return [] }
    let bands = profile.allSources.compactMap { source -> RemappingTriggerBandSource? in
      guard case .triggerBand(let band) = source, band.trigger == trigger else { return nil }
      return band
    }
    return moveRegion(among: bands, as: RemappingSource.triggerBand, for: identifier, at: uptime) {
      value.isFinite && $0.contains(min(1, max(0, Double(value))), wasActive: $1)
    }
  }

  /// Releases the active region when it no longer contains the input, and then presses the one
  /// that does.
  ///
  /// Regions of one input do not overlap, so at most one is active. An active region keeps the
  /// input while it still contains it with hysteresis, so a neighbor cannot take over before it
  /// lets go.
  private mutating func moveRegion<Region: Hashable>(
    among regions: [Region],
    as source: (Region) -> RemappingSource,
    for identifier: LogicalControllerID,
    at uptime: UInt64,
    contains: (Region, Bool) -> Bool
  ) -> [RemappingEngineAction] {
    guard let active = devices[identifier]?.activeSources else { return [] }
    let current = regions.first { active.contains(source($0)) }
    let next =
      current.flatMap { contains($0, true) ? $0 : nil } ?? regions.first { contains($0, false) }
    guard next != current else { return [] }
    var actions: [RemappingEngineAction] = []
    if let current {
      actions += setSource(source(current), isActive: false, for: identifier, at: uptime)
    }
    if let next { actions += setSource(source(next), isActive: true, for: identifier, at: uptime) }
    return actions
  }
}

extension RemappingProfile {
  /// Every source that any part of the profile uses.
  var allSources: Set<RemappingSource> {
    var sources = Set(bindings.map(\.source))
    sources.formUnion(chords.flatMap(\.sources))
    sources.formUnion(sequences.flatMap(\.sources))
    for layer in layers {
      sources.insert(layer.activator)
      sources.formUnion(layer.bindings.map(\.source))
      sources.formUnion(layer.chords.flatMap(\.sources))
      sources.formUnion(layer.sequences.flatMap(\.sources))
    }
    return sources
  }
}
