import Foundation

extension DeviceManager {
  /// Sends one output command to the one connected controller `controller` names. The command
  /// is admitted against the pipeline's (native-narrowed) capabilities, then its values are
  /// checked, then it is recorded as the manual claim and the effective output of its channel is
  /// written. A failed command withdraws only its own claim.
  public func sendControllerOutput(
    _ command: ControllerOutputCommand,
    for controller: ControllerReference
  ) async -> ControllerOutputResult {
    guard let key = await connectedIdentifier(for: controller) else {
      return ControllerOutputResult(.notFound)
    }
    return await sendControllerOutput(command, toConnected: key)
  }

  /// Sends one output command to the connected controller `key`, as
  /// ``sendControllerOutput(_:for:)`` does.
  package func sendControllerOutput(
    _ command: ControllerOutputCommand,
    toConnected key: LogicalControllerID
  ) async -> ControllerOutputResult {
    guard !isStopping, let pipeline = pipelines[key] else {
      return ControllerOutputResult(.notFound)
    }
    let admission: (command: ControllerOutputCommand, droppedRumbleChannels: [PhysicalRumbleMotor])
    do { admission = try await pipeline.physicalOutputCapabilities().admit(command) } catch {
      return ControllerOutputResult(ControllerOutputResult.Outcome(error))
    }
    switch command {
    case .setAdaptiveTrigger(_, let effect) where (try? effect.validate()) == nil:
      return ControllerOutputResult(.invalidValue)
    case .setRumble(_, .milliseconds(let durationMs))
    where !(0...maxRumbleDurationMs).contains(durationMs):
      return ControllerOutputResult(.invalidValue)
    default: break
    }
    guard !isStopping else { return ControllerOutputResult(.notFound) }
    let outcome = await applyManualOutput(
      admission.command,
      requested: command,
      for: key,
      pipeline: pipeline
    )
    return ControllerOutputResult(outcome, droppedRumbleChannels: admission.droppedRumbleChannels)
  }

  private func applyManualOutput(
    _ admitted: ControllerOutputCommand,
    requested command: ControllerOutputCommand,
    for key: LogicalControllerID,
    pipeline: DevicePipeline
  ) async -> ControllerOutputResult.Outcome {
    let output: RemappingPhysicalOutput
    switch admitted {
    case .setRumble(let intensities, let duration):
      return await applyManualRumble(
        intensities,
        duration: duration,
        // Before admission: a request whose only active channels were dropped still schedules
        // its stop.
        hasActiveMotor: command != .setRumble(.off, duration: duration),
        for: key,
        pipeline: pipeline
      )
    case .stopRumble: return await stopManualRumble(for: key, pipeline: pipeline)
    case .setPlayerIndicator(let indicator): output = .playerIndicator(indicator)
    case .setRGB(let color): output = .color(color)
    case .setLightBrightness(let brightness): output = .brightness(Double(brightness.byte) / 255)
    case .setAdaptiveTrigger(let trigger, let effect): output = .adaptiveTrigger(trigger, effect)
    }
    let claim = physicalOutputOwnership.setManual(output, for: key)
    let outcome = await applyPhysicalChannel(output.channel, for: key, pipeline: pipeline)
    await finishManualClaim(claim, on: [output.channel], outcome: outcome, for: key, pipeline)
    return outcome
  }

  /// Keeps a delivered manual claim and withdraws a failed one. When the failed claim was the
  /// newest on its channel, a write another request made meanwhile may have carried it, so the
  /// channel's effective output is written once more.
  private func finishManualClaim(
    _ claim: UInt64,
    on channels: Set<PhysicalOutputChannel>,
    outcome: ControllerOutputResult.Outcome,
    for key: LogicalControllerID,
    _ pipeline: DevicePipeline
  ) async {
    guard outcome != .delivered else {
      physicalOutputOwnership.commitManual(claim, on: channels, for: key)
      return
    }
    guard physicalOutputOwnership.withdrawManual(claim, on: channels, for: key), !isStopping,
      let channel = channels.first
    else { return }
    _ = await applyPhysicalChannel(channel, for: key, pipeline: pipeline)
  }

  /// Claims every supported motor at its intensity and sends the effective rumble. A bounded
  /// duration of 0 ms sends, then releases the manual claim and sends again; a longer one, at most
  /// `maxRumbleDurationMs`, schedules that release.
  private func applyManualRumble(
    _ intensities: RumbleIntensities,
    duration: RumbleDuration,
    hasActiveMotor: Bool,
    for key: LogicalControllerID,
    pipeline: DevicePipeline
  ) async -> ControllerOutputResult.Outcome {
    let supportedMotors = await pipeline.physicalOutputCapabilities().rumbleMotors
    let claim = physicalOutputOwnership.setManual(
      supportedMotors.map { .rumble(motor: $0, intensity: intensities[$0].unitInterval) },
      for: key
    )
    let outcome = await sendEffectiveRumble(for: key, pipeline: pipeline, duration: duration)
    await finishManualClaim(
      claim,
      on: Set(supportedMotors.map(PhysicalOutputChannel.rumble)),
      outcome: outcome,
      for: key,
      pipeline
    )
    guard outcome == .delivered else { return outcome }
    guard case .milliseconds(let durationMs) = duration else {
      scheduleRumbleStop(for: key, pipeline: pipeline, durationMs: 0, hasActiveMotor: false)
      return outcome
    }
    if durationMs == 0 {
      _ = physicalOutputOwnership.releaseManualRumble(for: key)
      return await sendEffectiveRumble(for: key, pipeline: pipeline, duration: .held)
    }
    scheduleRumbleStop(
      for: key,
      pipeline: pipeline,
      durationMs: durationMs,
      hasActiveMotor: hasActiveMotor
    )
    return outcome
  }

  /// Releases the manual rumble claim, cancels a pending scheduled stop, and writes the effective
  /// rumble once, so an active mapping claim still shows through. A failed write does not restore
  /// the claim: its scheduled stop is gone, so the restored rumble would never stop.
  private func stopManualRumble(
    for key: LogicalControllerID,
    pipeline: DevicePipeline
  ) async -> ControllerOutputResult.Outcome {
    scheduleRumbleStop(for: key, pipeline: pipeline, durationMs: 0, hasActiveMotor: false)
    _ = physicalOutputOwnership.releaseManualRumble(for: key)
    return await sendEffectiveRumble(for: key, pipeline: pipeline, duration: .held)
  }

  /// Resolves `request` to a command and writes its whole encoded plan as one operation on the
  /// interface's output queue, so a stateful encoder's reports go out in encode order. An
  /// effective request reads ownership inside the operation, when it runs, so a write never
  /// carries a claim that a later change has replaced. A command the driver cannot encode
  /// (unsupported or not ready), or one cancelled while queued, fails without writing.
  internal func sendPhysicalOutput(
    _ request: PhysicalOutputRequest,
    for identifier: LogicalControllerID,
    pipeline: DevicePipeline,
    detachedInfo: DeviceInfo? = nil
  ) async -> ControllerOutputResult.Outcome {
    guard
      await acceptsPhysicalOutput(
        identifier: identifier,
        pipeline: pipeline,
        detachedInfo: detachedInfo
      )
    else { return .notFound }
    let outcome = await physicalOutputQueue(for: identifier).perform { [weak self] operation in
      guard let self else { return ControllerOutputResult.Outcome.cancelled }
      return await self.performPhysicalOutput(
        request,
        for: identifier,
        pipeline: pipeline,
        detachedInfo: detachedInfo,
        in: operation
      )
    }
    switch outcome {
    case .completed(let outcome): return outcome
    case .cancelled: return .cancelled
    }
  }

  private func performPhysicalOutput(
    _ request: PhysicalOutputRequest,
    for identifier: LogicalControllerID,
    pipeline: DevicePipeline,
    detachedInfo: DeviceInfo?,
    in operation: PhysicalOutputQueueOperation
  ) async -> ControllerOutputResult.Outcome {
    // A command for a controller replaced or removed while it waited leaves the encoder alone.
    guard
      await acceptsPhysicalOutput(
        identifier: identifier,
        pipeline: pipeline,
        detachedInfo: detachedInfo
      )
    else { return .cancelled }
    let plan: PhysicalOutputPlan
    do {
      let command = try await resolve(request, for: identifier, pipeline: pipeline)
      plan = try await pipeline.encode(command)
    } catch { return ControllerOutputResult.Outcome(error) }
    let written = await performPhysicalOutputPlan(
      plan,
      for: identifier,
      pipeline: pipeline,
      detachedInfo: detachedInfo,
      in: operation
    )
    return written ? .delivered : .writeFailed
  }

  /// Restores the channels a failed write changed. Teardown clears claims and must not have them
  /// restored while it neutralizes the controller.
  internal func rollBackPhysicalOutputs(to state: PhysicalOutputOwnership.ChannelState) {
    guard !isStopping else { return }
    physicalOutputOwnership.restore(state)
  }
}
