import OpenJoystickDriverKit

/// Works out what the controller of a profile can do.
enum ProfileCapabilityResolver {
  /// Returns the capabilities of the controller that `profile` is scoped to, or nil when they are
  /// not known.
  ///
  /// Several connected controllers of the model share what all of them have; with none connected,
  /// the registry's record of the model answers. A Joy-Con pair profile also takes the input of the
  /// other half.
  static func resolve(
    profile: RemappingProfile,
    connectedDevices: [ApplicationServiceDeviceDescription],
    registry: ProtocolDriverRegistry
  ) -> ControllerProfileCapabilities? {
    let resolved = deviceCapabilities(
      profile: profile,
      connectedDevices: connectedDevices,
      registry: registry
    )
    // A Joy-Con pair profile is scoped to the left half but maps controls from both halves.
    guard profile.joyConPair != nil, let resolved else { return resolved }
    let halves = JoyConHalf.generationProductIDs(forLeft: profile.device.productID).compactMap {
      registry.profileCapabilities(
        for: ControllerModelID(vendorID: profile.device.vendorID, productID: $0)
      )
    }
    let pairInput = halves.map(\.physicalInput).reduce(resolved.physicalInput) { $0.union($1) }
    return ControllerProfileCapabilities(
      physicalInput: pairInput,
      physicalOutput: resolved.physicalOutput
    )
  }

  /// Returns the capabilities of the profile's controller from the connected controllers, else
  /// from the registry.
  private static func deviceCapabilities(
    profile: RemappingProfile,
    connectedDevices: [ApplicationServiceDeviceDescription],
    registry: ProtocolDriverRegistry
  ) -> ControllerProfileCapabilities? {
    let matchingDevices = connectedDevices.filter {
      $0.vendorID == profile.device.vendorID && $0.productID == profile.device.productID
    }
    if let first = matchingDevices.first {
      return matchingDevices.dropFirst().reduce(capabilities(for: first)) {
        $0.intersecting(capabilities(for: $1))
      }
    }
    return registry.profileCapabilities(
      for: ControllerModelID(vendorID: profile.device.vendorID, productID: profile.device.productID)
    )
  }

  /// Returns the capabilities that `device` reports.
  private static func capabilities(
    for device: ApplicationServiceDeviceDescription
  ) -> ControllerProfileCapabilities {
    ControllerProfileCapabilities(
      physicalInput: device.capabilities,
      physicalOutput: device.physicalOutputCapabilities
    )
  }
}

/// Decides whether a controller supports a source or a destination.
enum ProfileCapabilityPolicy {
  /// Returns whether the controller has the control behind `source`.
  ///
  /// Unknown capabilities mean it does.
  static func supports(
    _ source: RemappingSource,
    capabilities: ControllerProfileCapabilities?
  ) -> Bool {
    guard let input = capabilities?.physicalInput else { return true }
    switch source {
    case .dpad: return !input.controls.isDisjoint(with: Control.dpad)
    case .button(let button):
      return input.controls.contains(button)
    case .axis(let axis), .axisDirection(let axis, _):
      return input.controls.contains(axis.control)
    case .triggerStage(let trigger, _):
      return input.controls.contains(trigger == .left ? .leftTrigger : .rightTrigger)
    case .motionLean: return input.motion
    case .touchContact(let surface): return supports(surface, input: input)
    case .touchGrid(let source): return supports(source.surface, input: input)
    case .touchSwipe(let source): return supports(source.surface, input: input)
    case .stickRegion(let region):
      return input.controls.contains(region.stick == .left ? .leftStickX : .rightStickX)
    case .triggerBand(let band):
      return input.controls.contains(band.trigger == .left ? .leftTrigger : .rightTrigger)
    case .touchArea(let area): return supports(area.surface, input: input)
    }
  }

  /// Returns whether the controller can play `destination`.
  ///
  /// Only a physical output depends on the capabilities; unknown capabilities support everything.
  static func supports(
    _ destination: RemappingDestination,
    capabilities: ControllerProfileCapabilities?
  ) -> Bool {
    guard capabilities != nil else { return true }
    guard case .physical(let output) = destination else { return true }
    guard let physical = capabilities?.physicalOutput else { return false }
    switch output {
    case .rumble(let motor, _): return physical.rumbleMotors.contains(motor)
    case .playerIndicator: return physical.lightingFeatures.contains(.playerIndicator)
    case .color: return physical.lightingFeatures.contains(.programmableColor)
    case .brightness: return physical.lightingFeatures.contains(.programmableBrightness)
    case .adaptiveTrigger(let trigger, _): return physical.adaptiveTriggers.contains(trigger)
    }
  }

  /// Returns whether the controller has the touch surface.
  private static func supports(
    _ surface: RemappingTouchSurface,
    input: ControllerCapabilities
  ) -> Bool {
    let physicalSurface: ControllerTouchSurface
    switch surface {
    case .primary: physicalSurface = .primary
    case .left: physicalSurface = .left
    case .right: physicalSurface = .right
    }
    return input.touchSurfaces.contains(physicalSurface)
  }
}
