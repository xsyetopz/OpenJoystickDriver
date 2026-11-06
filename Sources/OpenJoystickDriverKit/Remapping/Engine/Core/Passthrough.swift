import Foundation

extension RemappingDeviceState {
  /// Rebuilds the unmapped contribution to the virtual gamepad and returns the action when it
  /// changed.
  ///
  /// It uses the same aggregate as explicit destinations and only runs for the passthrough virtual
  /// gamepad policy. Active buttons and d-pad directions, and physical axis values, are included
  /// unless the profile binds or reserves them.
  /// - Parameters:
  ///   - replayingAxis: An axis value to use in place of the recorded one, for a replayed press.
  ///   - lookup: Reports whether the right pad of a controller is its right stick.
  /// - Returns: The action that sets the unmapped contribution, or an empty array when the policy
  ///   is not passthrough or the contribution did not change.
  mutating func updatePassthrough(
    replayingAxis: (RemappingAxis, Float)? = nil,
    rightPadIsRightStick lookup: (LogicalControllerID) -> Bool =
      VirtualGamepadReportMapping.rightPadIsRightStick
  ) -> [RemappingEngineAction] {
    guard profile.outputPolicy.virtualGamepad == .passthrough else { return [] }
    var reserved = reservedPassthroughSources
    // A trigger's analog axis and its click are one physical control: a profile that binds or
    // reserves either withholds both, so a released axis cannot leak back as a full click.
    for trigger in RemappingTriggerSource.allCases
    where trigger.passthroughSources.contains(where: {
      reserved.contains($0) || binding(for: $0) != nil
    }) { reserved.formUnion(trigger.passthroughSources) }
    // The catalog record is read once per update, not once per pressed button.
    let rightPadIsRightStick = lookup(identifier)
    var buttons: Set<Control> = []
    var directions: Set<RemappingDpadDirection> = []
    for source in activeSources where !reserved.contains(source) && binding(for: source) == nil {
      switch source {
      case .button(let button):
        // A controller whose right pad is its right stick has the pad click as R3; one with a
        // real R3 keeps it as its own control, which no virtual persona carries. One rule with
        // the report mapping.
        buttons.insert(
          VirtualGamepadReportMapping.virtualControl(
            button,
            rightPadIsRightStick: rightPadIsRightStick
          )
        )
      case .dpad(let direction): directions.insert(direction)
      case .axis, .axisDirection, .triggerStage, .motionLean, .touchContact, .touchGrid,
        .touchSwipe:
        break
      }
    }
    var axes: [RemappingAxis: Double] = [:]
    var physicalValues = analog.physicalAxes
    if let (axis, value) = replayingAxis { physicalValues[axis] = value }
    for (axis, value) in physicalValues {
      let sources: [RemappingSource] = [
        .axis(axis), .axisDirection(axis, .negative), .axisDirection(axis, .positive),
      ]
      guard sources.allSatisfy({ !reserved.contains($0) && binding(for: $0) == nil }) else {
        continue
      }
      axes[axis] = Double(value)
    }
    let contribution = RemappingGamepadState(buttons: buttons, dpad: directions, axes: axes)
    guard let state = outputs.gamepad.update(contribution, for: passthroughBindingID) else {
      return []
    }
    return [.gamepad(state, identifier)]
  }

  /// Sources withheld from passthrough because a recognizer owns them.
  ///
  /// Those are layer activators, axes of stick and trigger mappings that do not pass through, gyro
  /// activation and trackball sources that the gyro consumes, held-back and consumed chord sources,
  /// modifier chord sources, and sequence sources.
  private var reservedPassthroughSources: Set<RemappingSource> {
    var sources = Set(profile.layers.map(\.activator))
    for mapping in profile.stickMappings where !mapping.passthrough {
      let axes: [RemappingAxis] =
        mapping.source == .left ? [.leftStickX, .leftStickY] : [.rightStickX, .rightStickY]
      sources.formUnion(axes.map(RemappingSource.axis))
    }
    for mapping in profile.triggerMappings where !mapping.passthrough {
      sources.insert(.axis(mapping.source.axis))
    }
    let gyro = profile.gyroOutput
    if gyro.mode != .disabled, gyro.consumesActivationSource, let source = gyro.activationSource {
      sources.insert(source)
    }
    if gyro.mode != .disabled, let trackball = gyro.trackball, trackball.consumesSource {
      sources.insert(trackball.source)
    }
    sources.formUnion(chords.pendingChordPresses.map(\.source))
    sources.formUnion(chords.consumedChordSources)
    for chord in effectiveChords where chord.mode == .modifier { sources.formUnion(chord.sources) }
    for sequence in profile.sequences { sources.formUnion(sequence.sources) }
    let layerIDs = Set(layers.activeLayers).union(layers.layerToggleState)
    for layer in profile.layers where layerIDs.contains(layer.id) {
      for sequence in layer.sequences { sources.formUnion(sequence.sources) }
    }
    return sources
  }
}

extension RemappingTriggerSource {
  /// Every source that reads this physical trigger: its analog axis and its click.
  var passthroughSources: [RemappingSource] {
    [
      .axis(axis), .axisDirection(axis, .negative), .axisDirection(axis, .positive),
      .button(self == .left ? .leftTrigger : .rightTrigger),
    ]
  }
}
