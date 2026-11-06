import Foundation

/// Layers that a controller has switched on.
struct RemappingLayerState {
  /// Active layers in activation order.
  var activeLayers: [UUID] = []
  /// Toggle-mode layers that are switched on.
  var layerToggleState: Set<UUID> = []
}
