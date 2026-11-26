import Foundation

/// What one output-queue operation writes: a fixed command, or the effective output of claimed
/// channels, which is read from ownership when the operation runs.
enum PhysicalOutputRequest: Equatable, Sendable {
  /// A fixed command.
  case command(ControllerOutputCommand)
  /// Every motor's effective intensity at `duration`; all zero is a stop.
  case effectiveRumble(RumbleDuration)
  /// The winning claim of one non-rumble channel, or the channel's at-rest value (player off, the
  /// default color, brightness 0, trigger effect off) when none claims it.
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
    switch request {
    case .command(let command): return command
    case .effectiveRumble(let duration):
      return effectiveRumbleCommand(for: identifier, duration: duration)
    case .effectiveChannel(let channel):
      return try await effectiveChannelCommand(channel, for: identifier, pipeline: pipeline)
    }
  }

  /// The rumble command of the motors' effective intensities; a stop when all are zero.
  private func effectiveRumbleCommand(
    for identifier: LogicalControllerID,
    duration: RumbleDuration
  ) -> ControllerOutputCommand {
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
  }

  /// The command of the winning claim on `channel`, or of the channel's at-rest value.
  ///
  /// A color with no claim takes the pipeline's default color.
  private func effectiveChannelCommand(
    _ channel: PhysicalOutputChannel,
    for identifier: LogicalControllerID,
    pipeline: DevicePipeline
  ) async throws(ControllerOutputError) -> ControllerOutputCommand {
    let value = physicalOutputOwnership.effectiveOutput(for: channel, device: identifier)
    switch channel {
    case .rumble:
      return effectiveRumbleCommand(for: identifier, duration: .held)
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
