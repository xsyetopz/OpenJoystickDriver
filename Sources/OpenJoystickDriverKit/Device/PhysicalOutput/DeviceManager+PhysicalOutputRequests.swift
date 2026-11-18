public import Foundation

extension DeviceManager {
  /// Schedules the end of a timed rumble after `durationMs` and cancels the earlier stop of the
  /// controller.
  ///
  /// No stop is scheduled for a zero duration, an inactive motor, or while the manager stops.
  internal func scheduleRumbleStop(
    for identifier: LogicalControllerID,
    pipeline: DevicePipeline,
    durationMs: Int,
    hasActiveMotor: Bool
  ) {
    rumbleStopTasks.removeValue(forKey: identifier)?.cancel()
    let generation = rumbleStopTokens.replace(for: identifier)
    guard durationMs > 0, hasActiveMotor, !isStopping else {
      rumbleStopTokens.remove(identifier)
      return
    }
    rumbleStopTasks[identifier] = Task { [weak self] in
      do {
        try await Task.sleep(
          nanoseconds: UInt64(durationMs) * deviceDiscoveryNanosecondsPerMillisecond
        )
      } catch { return }
      await self?.finishScheduledRumbleStop(
        for: identifier,
        pipeline: pipeline,
        generation: generation
      )
    }
  }

  /// Ends a timed rumble: drops the manual rumble claims and writes the effective rumble.
  ///
  /// Does nothing when a later request replaced `generation` or the pipeline changed.
  internal func finishScheduledRumbleStop(
    for identifier: LogicalControllerID,
    pipeline: DevicePipeline,
    generation: UInt64
  ) async {
    guard rumbleStopTokens.isCurrent(generation, for: identifier),
      pipelines[identifier] === pipeline
    else { return }
    _ = physicalOutputOwnership.releaseManualRumble(for: identifier)
    _ = await sendEffectiveRumble(for: identifier, pipeline: pipeline, duration: .held)
    guard rumbleStopTokens.isCurrent(generation, for: identifier) else { return }
    rumbleStopTasks.removeValue(forKey: identifier)
    rumbleStopTokens.remove(identifier)
  }

  /// Previews a color on the controller until ``releasePhysicalColorPreview(for:token:)``.
  ///
  /// The preview wins over every other color claim. A failed write rolls the claims back.
  ///
  /// - Returns: Whether the controller supports a programmable color and the write was delivered.
  public func previewPhysicalColor(
    for controller: ControllerReference,
    token: UUID,
    red: UInt8,
    green: UInt8,
    blue: UInt8
  ) async -> Bool {
    guard let key = await connectedIdentifier(for: controller),
      let pipeline = pipelines[key],
      await pipeline.physicalOutputCapabilities().lightingFeatures.contains(.programmableColor)
    else { return false }
    guard !isStopping else { return false }
    let previousOwnership = physicalOutputOwnership.state(of: [.color], for: key)
    physicalOutputOwnership.setTemporaryColor(
      .color(ControllerColor(red: red, green: green, blue: blue)),
      token: token,
      for: key
    )
    let delivered = await applyPhysicalChannel(.color, for: key, pipeline: pipeline) == .delivered
    if !delivered { rollBackPhysicalOutputs(to: previousOwnership) }
    return delivered
  }

  /// Ends the color preview of `token` and writes the effective color.
  ///
  /// - Returns: True when no controller matches, or when the write was delivered.
  public func releasePhysicalColorPreview(
    for controller: ControllerReference,
    token: UUID
  ) async -> Bool {
    guard let key = await connectedIdentifier(for: controller)
    else { return true }
    physicalOutputOwnership.releaseTemporaryColor(token: token, for: key)
    guard let pipeline = pipelines[key] else { return true }
    return await applyPhysicalChannel(.color, for: key, pipeline: pipeline) == .delivered
  }

  /// Sets the profile color of `identifier` that the color channel falls back to; nil removes it.
  ///
  /// - Returns: False while the manager stops. True when no pipeline runs or the controller has no
  ///   programmable color, and otherwise whether the write was delivered.
  public func setProfilePhysicalColor(
    _ color: ControllerColor?,
    for identifier: LogicalControllerID
  ) async -> Bool {
    let output = color.map { RemappingPhysicalOutput.color($0) }
    guard !isStopping else { return false }
    physicalOutputOwnership.setProfileColor(output, for: identifier)
    guard let pipeline = pipelines[identifier],
      await pipeline.physicalOutputCapabilities().lightingFeatures.contains(.programmableColor)
    else { return true }
    return await applyPhysicalChannel(.color, for: identifier, pipeline: pipeline) == .delivered
  }

  /// Applies or releases one remapping claim for an exact connected controller.
  public func setMappingPhysicalOutput(
    _ output: RemappingPhysicalOutput,
    active: Bool,
    owner: UUID,
    for identifier: LogicalControllerID
  ) async -> Bool {
    do { try output.validate() } catch { return false }
    guard let pipeline = pipelines[identifier] else {
      if !active {
        _ = physicalOutputOwnership.setMapping(output, active: false, owner: owner, for: identifier)
        return true
      }
      return false
    }
    guard supports(output, capabilities: await pipeline.physicalOutputCapabilities()), !isStopping
    else { return false }
    let previousOwnership = physicalOutputOwnership.state(of: [output.channel], for: identifier)
    let channel = physicalOutputOwnership.setMapping(
      output,
      active: active,
      owner: owner,
      for: identifier
    )
    let delivered =
      await applyPhysicalChannel(channel, for: identifier, pipeline: pipeline) == .delivered
    if !delivered { rollBackPhysicalOutputs(to: previousOwnership) }
    return delivered
  }

  /// Releases every remapping claim for an exact controller without targeting a replacement.
  public func releaseMappingPhysicalOutputs(for identifier: LogicalControllerID) async -> Bool {
    let channels = physicalOutputOwnership.releaseMappings(for: identifier)
    guard let pipeline = pipelines[identifier] else { return true }
    var delivered = true
    for channel in channels.sorted(by: { $0.sortKey < $1.sortKey }) {
      guard await applyPhysicalChannel(channel, for: identifier, pipeline: pipeline) == .delivered
      else {
        delivered = false
        continue
      }
    }
    return delivered
  }

  /// Whether `capabilities` include the channel that `output` drives.
  internal func supports(
    _ output: RemappingPhysicalOutput,
    capabilities: PhysicalControllerOutputCapabilities
  ) -> Bool {
    switch output {
    case .rumble(let motor, _): capabilities.rumbleMotors.contains(motor)
    case .playerIndicator: capabilities.lightingFeatures.contains(.playerIndicator)
    case .color: capabilities.lightingFeatures.contains(.programmableColor)
    case .brightness: capabilities.lightingFeatures.contains(.programmableBrightness)
    case .adaptiveTrigger(let trigger, _): capabilities.adaptiveTriggers.contains(trigger)
    }
  }
}
