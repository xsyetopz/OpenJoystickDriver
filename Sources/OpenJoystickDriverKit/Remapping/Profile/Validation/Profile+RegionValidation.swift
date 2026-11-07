import Foundation

extension RemappingProfile {
  /// Rejects two different regions of one stick, or two different bands of one trigger, that share
  /// a position.
  ///
  /// Every scope counts, so the active region of an input is the same whichever layer is on.
  func validateRegionOverlap() throws {
    var regions: [RemappingStickRegionSource] = []
    var bands: [RemappingTriggerBandSource] = []
    for source in allSources {
      switch source {
      case .stickRegion(let region): regions.append(region)
      case .triggerBand(let band): bands.append(band)
      case .button, .dpad, .axis, .axisDirection, .triggerStage, .motionLean, .touchContact,
        .touchGrid, .touchSwipe, .touchArea:
        break
      }
    }
    let overlap =
      regions.enumerated().contains { index, region in
        regions[(index + 1)...].contains { region.overlaps($0) }
      }
      || bands.enumerated().contains { index, band in
        bands[(index + 1)...].contains { band.overlaps($0) }
      }
    if overlap { throw RemappingValidationError.overlappingRegions }
  }
}
