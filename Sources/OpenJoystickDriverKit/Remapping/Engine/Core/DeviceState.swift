import Foundation

/// State of one controller's mapping session.
struct RemappingDeviceState {
  /// Identifies this mapping session; a profile change or a release ends it.
  let sessionID = UUID()
  /// Profile that the session follows.
  let profile: RemappingProfile
  /// Controller that the session maps to.
  let identifier: LogicalControllerID
  /// Owner identity of the passthrough contribution to the virtual gamepad.
  let passthroughBindingID = UUID()
  /// Motion processing and motion-driven output state.
  var motion = RemappingMotionState()
  /// Stick, trigger and touch state.
  var analog = RemappingAnalogState()
  /// Chord, sequence and held-back press state.
  var chords = RemappingChordState()
  /// Outputs that the controller holds.
  var outputs = RemappingOutputState()
  /// Layers that the controller has switched on.
  var layers = RemappingLayerState()
  /// Whether a `Pause` has the controller pass through unmapped.
  var isPaused = false
  /// Sources that are active.
  var activeSources: Set<RemappingSource> = []
  /// Uptime at which each active source was pressed, in nanoseconds.
  var sourcePressTimes: [RemappingSource: UInt64] = [:]
  /// Latest uptime seen, in nanoseconds.
  var lastUptime: UInt64 = 0
  /// D-pad directions that are held.
  var dpadDirections: Set<RemappingDpadDirection> = []

  /// Returns the binding for a source, or `nil` when none applies.
  ///
  /// The most recently activated layer that binds the source wins, then the profile. While
  /// paused, only a `Pause` binding of the profile applies.
  func binding(for source: RemappingSource) -> RemappingBinding? {
    if isPaused {
      return profile.bindings.first { $0.source == source && $0.destination.isPause }
    }
    for layerID in layers.activeLayers.reversed() {
      guard let layer = profile.layers.first(where: { $0.id == layerID }) else { continue }
      if let binding = layer.bindings.first(where: { $0.source == source }) { return binding }
    }
    return profile.bindings.first { $0.source == source }
  }
}
