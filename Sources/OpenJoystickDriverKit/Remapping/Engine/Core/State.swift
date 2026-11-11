import Foundation

/// Nanoseconds in a millisecond.
let remappingStateNanosecondsPerMillisecond: Double = 1_000_000

/// State of the remapping engine across controllers.
struct RemappingEngineState {
  /// Mapping session of each controller that has a profile.
  var devices: [LogicalControllerID: RemappingDeviceState] = [:]
  /// Number of holders of each key that is down.
  var keyReferences: [RemappingKeyboardKey: Int] = [:]
  /// Number of holders of each modifier that is down.
  var modifierReferences: [RemappingKeyModifier: Int] = [:]
  /// Number of holders of each pointer button that is down.
  var mouseButtonReferences: [RemappingMouseButton: Int] = [:]
  /// The last snapshot each physical source delivered, which its next snapshot is diffed against.
  var sourceBaselines: [LogicalControllerID: ControllerState] = [:]
}
