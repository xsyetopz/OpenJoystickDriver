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

extension RemappingEngineState {
  /// The product of the pointer scales of every controller whose profile sets a pointer speed.
  ///
  /// A system action names no controller and continuous totals add up across controllers, so the
  /// scales apply together to the one pointer.
  var pointerScale: Double {
    devices.values.reduce(1) { product, device in
      guard let speed = device.profile.pointerSpeed else { return product }
      let axes = device.analog.physicalAxes
      return product * speed.scale { axes[$0] ?? 0 }
    }
  }
}
