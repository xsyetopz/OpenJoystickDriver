import Foundation

/// What one output-queue operation writes: a fixed command, or the effective output of claimed
/// channels, which is read from ownership when the operation runs.
enum PhysicalOutputRequest: Equatable, Sendable {
  /// A fixed command.
  case command(ControllerOutputCommand)
  /// Every motor's effective intensity at `duration`; all zero is a stop.
  case effectiveRumble(RumbleDuration)
  /// The winning claim of one non-rumble channel, or the channel's neutral value (player off, the
  /// default colour, brightness 0, trigger effect off) when none claims it.
  case effectiveChannel(PhysicalOutputChannel)
}

extension DeviceManager {
  /// Sends every motor's effective intensity; all zero is a stop.
  internal func sendEffectiveRumble(
    for identifier: LogicalControllerID,
    pipeline: DevicePipeline,
    duration: RumbleDuration,
    detachedInfo: DeviceInfo? = nil
  ) async -> ControllerOutputResult.Outcome {
    await sendPhysicalOutput(
      .effectiveRumble(duration),
      for: identifier,
      pipeline: pipeline,
      detachedInfo: detachedInfo
    )
  }

  /// Sends the effective output of one channel.
  ///
  /// Rumble re-encodes are held until the next command.
  internal func applyPhysicalChannel(
    _ channel: PhysicalOutputChannel,
    for identifier: LogicalControllerID,
    pipeline: DevicePipeline,
    detachedInfo: DeviceInfo? = nil
  ) async -> ControllerOutputResult.Outcome {
    let request: PhysicalOutputRequest
    if case .rumble = channel {
      request = .effectiveRumble(.held)
    } else {
      request = .effectiveChannel(channel)
    }
    return await sendPhysicalOutput(
      request,
      for: identifier,
      pipeline: pipeline,
      detachedInfo: detachedInfo
    )
  }

  /// The command that `request` resolves to at the time it is written.
  ///
  /// Called inside the queue operation that writes it.
  internal func resolve(
    _ request: PhysicalOutputRequest,
    for identifier: LogicalControllerID,
    pipeline: DevicePipeline
  ) async throws(ControllerOutputError) -> ControllerOutputCommand {
    let channel: PhysicalOutputChannel
    switch request {
    case .command(let command): return command
    case .effectiveRumble(let duration):
      var intensities = RumbleIntensities.off
      for motor in PhysicalRumbleMotor.allCases {
        guard
          case .rumble(_, let intensity) = physicalOutputOwnership.effectiveOutput(
            for: .rumble(motor),
            device: identifier
          )
        else { continue }
        intensities[motor] = UnipolarValue(unitInterval: intensity)
      }
      return intensities == .off ? .stopRumble : .setRumble(intensities, duration: duration)
    case .effectiveChannel(let effectiveChannel): channel = effectiveChannel
    }
    let value = physicalOutputOwnership.effectiveOutput(for: channel, device: identifier)
    switch channel {
    case .rumble:
      return try await resolve(.effectiveRumble(.held), for: identifier, pipeline: pipeline)
    case .playerIndicator:
      guard case .playerIndicator(let indicator) = value else { return .setPlayerIndicator(.off) }
      return .setPlayerIndicator(indicator)
    case .color:
      if case .color(let color) = value { return .setRGB(color) }
      guard let defaultColor = await pipeline.defaultColor() else {
        throw .unsupportedCapability(.rgb)
      }
      return .setRGB(defaultColor)
    case .brightness:
      guard case .brightness(let intensity) = value else { return .setLightBrightness(.min) }
      return .setLightBrightness(UnipolarValue(unitInterval: intensity))
    case .adaptiveTrigger(let trigger):
      guard case .adaptiveTrigger(_, let effect) = value else {
        return .setAdaptiveTrigger(trigger, .off)
      }
      return .setAdaptiveTrigger(trigger, effect)
    }
  }
}
