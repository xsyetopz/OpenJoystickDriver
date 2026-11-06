import Foundation

extension RemappingEventEngine {

  /// Discards all mapping state, marks the engine faulted, and tries to release every output that
  /// may still be held.
  ///
  /// Gamepad and physical output that was held becomes uncertain. A failed release leaves the
  /// output in the uncertain sets for ``recover()``.
  func failClosed(potentiallyHeld: Set<RemappingHeldOutput>) async {
    state = RemappingEngineState()
    faulted = true
    uncertainHeldOutputs = potentiallyHeld
    uncertainGamepadDevices.formUnion(heldGamepadDevices)
    heldGamepadDevices.removeAll()
    uncertainPhysicalDevices.formUnion(heldPhysicalOwners.keys)
    heldPhysicalOwners.removeAll()
    try? await releaseUncertainOutputs()
  }

  /// Updates held outputs for an action that the sink accepted.
  static func accountForDelivered(
    _ action: RemappingSystemInputAction,
    in heldOutputs: inout Set<RemappingHeldOutput>
  ) {
    switch action {
    case .modifierDown(let modifier): heldOutputs.insert(.modifier(modifier))
    case .modifierUp(let modifier): heldOutputs.remove(.modifier(modifier))
    case .keyDown(let key): heldOutputs.insert(.key(key))
    case .keyUp(let key): heldOutputs.remove(.key(key))
    case .mouseButtonDown(let button): heldOutputs.insert(.mouseButton(button))
    case .mouseButtonUp(let button): heldOutputs.remove(.mouseButton(button))
    case .mouseMoved, .pointerDelta, .scrolled, .scrollDelta: break
    }
  }

  /// Adds the output of an action whose delivery is uncertain to the held outputs.
  ///
  /// The action may or may not have taken effect, so its key, modifier or pointer button counts as
  /// held.
  static func accountForUncertain(
    _ action: RemappingSystemInputAction,
    in heldOutputs: inout Set<RemappingHeldOutput>
  ) {
    switch action {
    case .modifierDown(let modifier), .modifierUp(let modifier):
      heldOutputs.insert(.modifier(modifier))
    case .keyDown(let key), .keyUp(let key): heldOutputs.insert(.key(key))
    case .mouseButtonDown(let button), .mouseButtonUp(let button):
      heldOutputs.insert(.mouseButton(button))
    case .mouseMoved, .pointerDelta, .scrolled, .scrollDelta: break
    }
  }

  /// Orders held outputs for release: keys, then pointer buttons, then modifiers.
  ///
  /// Modifiers are released in reverse stable-name order.
  static func releaseOrder(_ outputs: Set<RemappingHeldOutput>) -> [RemappingHeldOutput] {
    outputs.sorted { lhs, rhs in
      if lhs.releaseOrder != rhs.releaseOrder { return lhs.releaseOrder < rhs.releaseOrder }
      if lhs.releaseOrder == 2 { return lhs.stableName > rhs.stableName }
      return lhs.stableName < rhs.stableName
    }
  }
}
