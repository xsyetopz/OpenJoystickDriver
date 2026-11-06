import Foundation

/// Analog runtimes and values of one controller.
struct RemappingAnalogState {
  /// Stick runtimes by stick.
  var sticks: [RemappingStickSource: RemappingStickRuntime] = [:]
  /// Dual-stage trigger runtimes by trigger.
  var triggers: [RemappingTriggerSource: RemappingDualStageTriggerRuntime] = [:]
  /// Contacts of each touch surface.
  var touchSurfaces: [RemappingTouchSurface: RemappingTouchSurfaceState] = [:]
  /// Last raw value of each physical axis.
  var physicalAxes: [RemappingAxis: Float] = [:]
  /// Binding identifiers that hold a virtual gamepad axis contribution.
  var virtualAxisBindings: Set<UUID> = []
}
