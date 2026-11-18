import Foundation

extension DevicePipeline {

  /// Takes the snapshot of one parsed input, or nil for a frame that carried no input, normalizes
  /// it, and dispatches it when output may see it and it differs from the last dispatched state.
  ///
  /// With `laterReportQueued`, an input that changes no button, hat, or touch frame is kept in
  /// `coalescedInput` for the later report instead.
  func handleParsedEvent(
    _ parsed: ControllerEvent?,
    now: UInt64,
    laterReportQueued: Bool = false
  ) async {
    guard sessionState == .active else { return }
    // This report's state supersedes the input an earlier report left; that input's motion
    // samples still go out with this one.
    let held = coalescedInput
    coalescedInput = nil
    if let parsed {
      currentRawInputState = parsed.state
      if let latest = parsed.motion.last { currentRawAngularVelocity = latest.angularVelocity }
    }
    let event = parsed.map(normalized)
    if event != nil {
      if lastObservedInputReportNanoseconds == nil {
        NotificationCenter.postServiceStatusChanged(from: self)
      }
      lastObservedInputReportNanoseconds = now
    }
    if let timeout = plan.inputReportLivenessTimeoutNanoseconds {
      if let last = lastLiveInputReportNanoseconds ?? inputHealthMonitoringStartedNanoseconds,
        now - last >= timeout
      {
        await retireOutputAfterLivenessLoss()
      }
      if event?.isFresh == true {
        lastLiveInputReportNanoseconds = now
        armStaleWatch()
      }
      if awaitingNeutralAfterLivenessLoss {
        guard let event, event.isFresh, event.state.isEffectivelyNeutral else { return }
        currentInputState = .neutral
        foregroundMask = nil
        if livenessLossFollowedInput { inputHealthRecoveryCount += 1 }
        awaitingNeutralAfterLivenessLoss = false
        await activateOutput()
        return
      }
    }
    guard let event else {
      // A report with no input leaves the held input for `dispatchCoalescedInput()`.
      coalescedInput = held
      return
    }
    let previousInput = currentInputState
    currentInputState = event.state
    idleInput.observe(event.state, at: now)

    if !externalOutputAllowed { return }
    if waitingForExternalNeutral {
      if event.state.isEffectivelyNeutral {
        waitingForExternalNeutral = false
        foregroundMask = ForegroundInputMask(hiding: event.state)
        print("[DevicePipeline] Foreground gate re-armed after neutral: \(identifier)")
        return
      }
      if event.state != previousInput || !event.motion.isEmpty || !event.touchFrames.isEmpty {
        waitingForExternalNeutral = false
        foregroundMask = ForegroundInputMask(hiding: event.state)
        print(
          "[DevicePipeline] Foreground gate re-armed after first post-focus change: \(identifier)"
        )
      }
      return
    }
    var visible = event.state
    if var mask = foregroundMask {
      visible = mask.visible(event.state, shown: lastDispatchedState)
      foregroundMask = visible == event.state ? nil : mask
    }
    visible.connection = nil
    // A native controller with no remapping route is only listed: no per-report dispatch. Nothing
    // then reaches output, so the first report after a route appears delivers the held state.
    guard observedInputDemand?.wantsObservedInput(from: identifier) ?? true else {
      lastDispatchedState = .neutral
      return
    }
    let motion = (held?.motion ?? []) + event.motion
    guard visible != lastDispatchedState || !motion.isEmpty || !event.touchFrames.isEmpty else {
      return
    }
    let output = ControllerEvent(
      timestamp: event.timestamp,
      state: visible,
      motion: motion,
      touchFrames: event.touchFrames,
      isFresh: event.isFresh
    )
    // A slow publication must not replay stale stick positions from the reports queued behind
    // it, but every button, hat, and touch change still reaches output in order.
    if laterReportQueued, !inputFeedsRemapping, event.touchFrames.isEmpty,
      visible.pressed == lastDispatchedState.pressed, visible.hat == lastDispatchedState.hat,
      visible.touch == lastDispatchedState.touch
    {
      coalescedInput = output
      return
    }
    lastDispatchedState = visible
    await dispatch(output)
  }

  /// Whether a remapping route consumes this controller's input.
  ///
  /// Its bindings derive button edges from analog thresholds, so it must see every report, and no
  /// report is merged for it.
  var inputFeedsRemapping: Bool {
    (dispatcher as? any ObservedInputDemand)?.wantsObservedInput(from: identifier) == true
  }

  /// Dispatches the input an earlier report left for a later one that published nothing, such as
  /// a last queued report that carried no input.
  func dispatchCoalescedInput() async {
    guard let pending = coalescedInput else { return }
    coalescedInput = nil
    guard sessionState == .active, inputConnectionActive, externalOutputAllowed,
      !waitingForExternalNeutral, !awaitingNeutralAfterLivenessLoss,
      pending.state != lastDispatchedState || !pending.motion.isEmpty
    else { return }
    lastDispatchedState = pending.state
    await dispatch(pending)
  }

  /// Applies the normalization a driver leaves to the pipeline: the stored calibration, which also
  /// removes the gyro offset from each motion sample, then each
  /// trigger button the driver's protocol has no digital signal for, derived from its analog
  /// trigger with hysteresis against the last normalized state.
  func normalized(_ event: ControllerEvent) -> ControllerEvent {
    let stored = calibration()
    let state = TriggerButtonDerivation.applying(
      to: stored.applying(to: event.state),
      previous: currentInputState,
      capabilities: driver.capabilities
    )
    let motion = event.motion.map(stored.applying)
    guard state != event.state || motion != event.motion else { return event }
    return ControllerEvent(
      timestamp: event.timestamp,
      state: state,
      motion: motion,
      touchFrames: event.touchFrames,
      isFresh: event.isFresh
    )
  }

  /// Asks the dispatcher to activate output for the controller, with no new input.
  func activateOutput() async { try? await produce(.activation(identifier)) }

  /// Stamps the link and power state, the one source `ControllerState.connection` reads, and
  /// dispatches.
  func dispatch(_ event: ControllerEvent) async {
    var state = event.state
    state.connection = currentConnectionState()
    let sequence = frameTimings.dispatched(for: identifier, at: uptimeNanoseconds())
    let frameTimings = frameTimings
    let identifier = identifier
    let uptimeNanoseconds = uptimeNanoseconds
    let stampDelivery: @Sendable () -> Void = {
      guard let sequence else { return }
      frameTimings.virtualDeviceDelivered(
        sequence: sequence,
        for: identifier,
        at: uptimeNanoseconds()
      )
    }
    // A failed or suppressed publish stamps nothing; the pipeline still ignores the failure.
    try? await produce(
      .controller(
        ControllerEvent(
          timestamp: event.timestamp,
          state: state,
          motion: event.motion,
          touchFrames: event.touchFrames,
          isFresh: event.isFresh
        ),
        from: identifier
      ),
      onDelivered: stampDelivery
    )
  }

  /// The link and power state now; nil for a pipeline built without a binding.
  func currentConnectionState() -> ControllerConnectionState? {
    binding.map { connectionState(binding: $0, interface: interface) }
  }
}

extension DevicePipeline {
  /// Whether the controller is on Bluetooth and its input state has not changed for `minutes`.
  func isIdleDisconnectDue(afterMinutes minutes: Int) -> Bool {
    IdleDisconnectPolicy.isDue(
      transport: currentConnectionState()?.transport,
      idleNanoseconds: idleInput.idleNanoseconds(at: uptimeNanoseconds()),
      afterMinutes: minutes
    )
  }

  /// Starts the idle time again, so a failed disconnect is retried after a full period.
  func restartIdleWindow() { idleInput.restart(at: uptimeNanoseconds()) }
}
