import Foundation

extension DevicePipeline {

  /// Takes the snapshot of one parsed input, or nil for a frame that carried no input, normalizes
  /// it, and dispatches it when output may see it and it differs from the last dispatched state.
  func handleParsedEvent(_ parsed: ControllerEvent?, now: UInt64) async {
    guard sessionState == .active else { return }
    let event = parsed.map(normalized)
    if event != nil { lastObservedInputReportNanoseconds = now }
    if let timeout = plan.inputReportLivenessTimeoutNanoseconds {
      if let last = lastLiveInputReportNanoseconds ?? inputHealthMonitoringStartedNanoseconds,
        now - last >= timeout
      {
        await retireOutputAfterLivenessLoss()
      }
      if event?.isFresh == true { lastLiveInputReportNanoseconds = now }
      if awaitingNeutralAfterLivenessLoss {
        guard let event, event.isFresh, event.state.isEffectivelyNeutral else { return }
        currentInputState = .neutral
        foregroundMask = nil
        awaitingNeutralAfterLivenessLoss = false
        inputHealthRecoveryCount += 1
        await activateOutput()
        return
      }
    }
    guard let event else { return }
    let previousInput = currentInputState
    currentInputState = event.state

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
    guard visible != lastDispatchedState || !event.motion.isEmpty || !event.touchFrames.isEmpty
    else { return }
    lastDispatchedState = visible
    await dispatch(
      ControllerEvent(
        timestamp: event.timestamp,
        state: visible,
        motion: event.motion,
        touchFrames: event.touchFrames,
        isFresh: event.isFresh
      )
    )
  }

  /// Applies the normalization a driver leaves to the pipeline: each trigger button the driver's
  /// protocol has no digital signal for is derived from its analog trigger, with hysteresis
  /// against the last normalized state.
  func normalized(_ event: ControllerEvent) -> ControllerEvent {
    let state = TriggerButtonDerivation.applying(
      to: event.state,
      previous: currentInputState,
      capabilities: driver.capabilities
    )
    guard state != event.state else { return event }
    return ControllerEvent(
      timestamp: event.timestamp,
      state: state,
      motion: event.motion,
      touchFrames: event.touchFrames,
      isFresh: event.isFresh
    )
  }

  /// Asks the dispatcher to activate output for the controller, with no new input.
  func activateOutput() async { await dispatcher.activateOutput(for: identifier) }

  /// Stamps the link and power state, the one source `ControllerState.connection` reads, and
  /// dispatches.
  func dispatch(_ event: ControllerEvent) async {
    var state = event.state
    state.connection = currentConnectionState()
    await dispatcher.dispatch(
      ControllerEvent(
        timestamp: event.timestamp,
        state: state,
        motion: event.motion,
        touchFrames: event.touchFrames,
        isFresh: event.isFresh
      ),
      labels: buttonLabels,
      from: identifier
    )
  }

  /// The link and power state now; nil for a pipeline built without a binding.
  func currentConnectionState() -> ControllerConnectionState? {
    binding.map { connectionState(binding: $0, interface: interface) }
  }
}
