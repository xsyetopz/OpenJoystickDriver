import Foundation

extension DevicePipeline {

  /// Takes the snapshot of one parsed input, or nil for a frame that carried no input, puts it
  /// in the standard form, and sends it when output may see it and it differs from the last
  /// sent state.
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
    let event = recordParsedInput(parsed, now: now)
    if let timeout = plan.inputReportLivenessTimeoutNanoseconds {
      guard await trackInputLiveness(event, now: now, timeout: timeout) else { return }
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
      rearmForegroundGate(for: event, previousInput: previousInput)
      return
    }
    let visible = visibleInputState(of: event)
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
      changesOnlyAnalogInput(visible)
    {
      coalescedInput = output
      return
    }
    lastDispatchedState = visible
    await dispatch(output)
  }

  /// Stores the raw input of `parsed` and returns its standard form, or nil for a frame that
  /// carried no input.
  private func recordParsedInput(_ parsed: ControllerEvent?, now: UInt64) -> ControllerEvent? {
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
    return event
  }

  /// Retires the output after a liveness loss, notes a fresh report, and ends the loss once a
  /// fresh neutral report arrives.
  ///
  /// - Returns: Whether the report goes on to dispatch; false while the pipeline waits for a
  ///   neutral report after a liveness loss.
  private func trackInputLiveness(
    _ event: ControllerEvent?,
    now: UInt64,
    timeout: UInt64
  ) async -> Bool {
    if let last = lastLiveInputReportNanoseconds ?? inputHealthMonitoringStartedNanoseconds,
      now - last >= timeout
    {
      await retireOutputAfterLivenessLoss()
    }
    if event?.isFresh == true {
      lastLiveInputReportNanoseconds = now
      armStaleWatch()
    }
    guard awaitingNeutralAfterLivenessLoss else { return true }
    guard let event, event.isFresh, event.state.isEffectivelyNeutral else { return false }
    currentInputState = .neutral
    foregroundMask = nil
    if livenessLossFollowedInput { inputHealthRecoveryCount += 1 }
    awaitingNeutralAfterLivenessLoss = false
    await activateOutput()
    return false
  }

  /// Ends the wait for external neutral once the input is neutral or has changed since the
  /// previous report, and hides the held input until it changes.
  private func rearmForegroundGate(for event: ControllerEvent, previousInput: ControllerState) {
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
  }

  /// Whether `visible` differs from the last dispatched state in no button, hat, or touch.
  private func changesOnlyAnalogInput(_ visible: ControllerState) -> Bool {
    visible.pressed == lastDispatchedState.pressed && visible.hat == lastDispatchedState.hat
      && visible.touch == lastDispatchedState.touch
  }

  /// The state of `event` with the foreground mask applied and the connection cleared.
  private func visibleInputState(of event: ControllerEvent) -> ControllerState {
    var visible = event.state
    if var mask = foregroundMask {
      visible = mask.visible(event.state, shown: lastDispatchedState)
      foregroundMask = visible == event.state ? nil : mask
    }
    visible.connection = nil
    return visible
  }

  /// Whether a remapping route consumes this controller's input.
  ///
  /// Its bindings derive button edges from analog thresholds, so it must see every report, and no
  /// report is merged for it.
  var inputFeedsRemapping: Bool {
    (dispatcher as? any ObservedInputDemand)?.wantsObservedInput(from: identifier) == true
  }

  /// Sends the input an earlier report left for a later one that published nothing, such as
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
  /// trigger with hysteresis against the last standard state.
  func normalized(_ event: ControllerEvent) -> ControllerEvent {
    let stored = calibration()
    let state = TriggerButtonDerivation.applying(
      to: stored.applying(to: event.state),
      previous: currentInputState,
      sides: derivedTriggerSides
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
  /// sends.
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
    // A failed or paused publish stamps nothing; the pipeline still ignores the failure.
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
