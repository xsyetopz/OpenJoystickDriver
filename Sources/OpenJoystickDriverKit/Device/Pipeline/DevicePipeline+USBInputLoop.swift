import Foundation

extension DevicePipeline {
  // An idle pass lasts at least the loop cadence, so a transport that completes timeouts at once
  // cannot spin. Repeated I/O errors back off and then end the session. The armed read is the one
  // started before the startup writes; the first pass takes its result in place of a new read.
  func runUSBInputLoop(
    handle: any USBTransportSession,
    generation: UInt64,
    armedRead: Task<[UInt8], any Error>? = nil
  ) async -> USBInputLoopRecovery {
    let inEndpoint = transportProfile.inputEndpoint
    print(
      "[DevicePipeline] Starting USB input loop:" + " \(identifier)"
        + " inEP=0x\(String(inEndpoint, radix: 16))"
    )

    if transportProfile.postHandshakeSettleNanoseconds > 0 {
      try? await Task.sleep(nanoseconds: transportProfile.postHandshakeSettleNanoseconds)
    }
    guard isCurrentUSBRun(generation) else { return .reconnect }
    startUSBKeepAlive(handle: handle, generation: generation)

    // A silent pad gets its toggles reset and its startup resent, a bounded number of times, and
    // then its firmware restarted.
    var state = USBInputLoopState(
      firstRead: armedRead,
      silentSince: plan.silentUSBStartupRecoveryNanoseconds == nil ? nil : uptimeNanoseconds()
    )
    while isCurrentUSBRun(generation) {
      let loopStartNs = uptimeNanoseconds()
      state.recovery = .reconnect
      let step = await runUSBInputPass(
        handle: handle,
        generation: generation,
        inEndpoint: inEndpoint,
        state: &state
      )
      if step == .stop { break }
      guard isCurrentUSBRun(generation) else { break }
      await pauseBeforeNextUSBPass(idle: step == .idle, loopStartNs: loopStartNs)
    }

    await finishUSBInputLoop(handle: handle, generation: generation, recovery: state.recovery)
    return state.recovery
  }

  /// The mutable state one input loop carries from pass to pass.
  private struct USBInputLoopState {
    var recovery = USBInputLoopRecovery.reconnect
    var firstRead: Task<[UInt8], any Error>?
    var silentSince: UInt64?
    var silentRecoveries = 0
  }

  /// What the loop does after one pass.
  private enum USBInputLoopStep {
    case dispatched
    case idle
    case stop
  }

  /// Reads, parses, and dispatches one packet, or handles the failure of that attempt.
  private func runUSBInputPass(
    handle: any USBTransportSession,
    generation: UInt64,
    inEndpoint: UInt8,
    state: inout USBInputLoopState
  ) async -> USBInputLoopStep {
    do {
      let bytes = try await nextUSBInputBytes(
        handle: handle,
        inEndpoint: inEndpoint,
        state: &state
      )
      guard isCurrentUSBRun(generation) else { return .stop }
      consecutiveUSBIOErrors = 0
      if !bytes.isEmpty { state.silentSince = nil }
      appendToPacketLog(bytes: bytes, direction: .received)
      let receivedAt = uptimeNanoseconds()
      let event = try parseReport(Data(bytes), receivedAt: receivedAt)
      await sendPendingUSBWrites(handle: handle, generation: generation)
      guard isCurrentUSBRun(generation) else { return .stop }
      _ = await handleInputConnectionStateChangeIfNeeded()
      guard isCurrentUSBRun(generation) else { return .stop }
      if inputConnectionActive { await handleParsedEvent(event, now: receivedAt) }
      guard isCurrentUSBRun(generation) else { return .stop }
      return .dispatched
    } catch {
      guard isCurrentUSBRun(generation) else { return .stop }
      return await recoverFromUSBReadFailure(
        error,
        handle: handle,
        generation: generation,
        state: &state
      )
    }
  }

  /// Takes the armed read's result once, then reads a new packet.
  private func nextUSBInputBytes(
    handle: any USBTransportSession,
    inEndpoint: UInt8,
    state: inout USBInputLoopState
  ) async throws -> [UInt8] {
    if let armed = state.firstRead {
      state.firstRead = nil
      return try await armed.value
    }
    return try await readInterrupt(
      handle: handle,
      inEndpoint: inEndpoint,
      timeout: Self.usbInputReadTimeoutMilliseconds(
        window: plan.silentUSBStartupRecoveryNanoseconds,
        silentSince: state.silentSince,
        now: uptimeNanoseconds()
      )
    )
  }

  /// Maps a failed pass to the recovery the loop applies and the step it takes next.
  private func recoverFromUSBReadFailure(
    _ error: any Error,
    handle: any USBTransportSession,
    generation: UInt64,
    state: inout USBInputLoopState
  ) async -> USBInputLoopStep {
    switch error {
    case let error as USBTransportError where error.isTimeout:
      // No data in this interval; the loop throttles to avoid a hot timeout loop.
      await recoverFromSilentUSBStartupIfDue(handle: handle, generation: generation, state: &state)
      return .idle
    case let error as USBTransportError where error.isDisconnected:
      print("[DevicePipeline] Device disconnected:" + " \(identifier)")
      await invalidateUSBHandle(handle)
      return .stop
    case let error as USBTransportError where error == .accessDenied:
      print("[DevicePipeline] USB read access denied; waiting before retry: \(identifier)")
      await invalidateUSBHandle(handle)
      state.recovery = .accessDenied
      return .stop
    case let error as USBTransportError where error.isInputOutput:
      return await backOffAfterUSBIOError(error, handle: handle, generation: generation)
    default:
      // Slow down after an unknown failure, then reconnect.
      print("[DevicePipeline] Read error" + " for \(identifier):" + " \(error). Reconnecting")
      await invalidateUSBHandle(handle)
      return .stop
    }
  }

  /// Resends the startup of a pad that stayed silent for the plan's window, and restarts its
  /// firmware once the resend limit is spent.
  private func recoverFromSilentUSBStartupIfDue(
    handle: any USBTransportSession,
    generation: UInt64,
    state: inout USBInputLoopState
  ) async {
    guard let since = state.silentSince, let window = plan.silentUSBStartupRecoveryNanoseconds,
      uptimeNanoseconds() &- since >= window
    else { return }
    state.silentRecoveries += 1
    if state.silentRecoveries <= usbSilentStartupRecoveryLimit {
      state.firstRead = await recoverSilentUSBStartup(handle: handle, generation: generation)
    }
    if state.firstRead != nil {
      state.silentSince = uptimeNanoseconds()
    } else {
      await restartSilentFirmware(handle: handle, generation: generation)
      state.silentSince = nil
    }
  }

  /// Counts an I/O error, logs it at a bounded rate, backs off, and ends the session once the
  /// errors reach the reconnect threshold.
  private func backOffAfterUSBIOError(
    _ error: USBTransportError,
    handle: any USBTransportSession,
    generation: UInt64
  ) async -> USBInputLoopStep {
    consecutiveUSBIOErrors += 1

    let now = uptimeNanoseconds()
    if now &- lastUSBIOErrorLogNs >= usbIOErrorLogIntervalNs {
      lastUSBIOErrorLogNs = now
      print(
        "[DevicePipeline] USB I/O error (will recover)" + " for \(identifier): \(error)"
          + " (consecutive=\(consecutiveUSBIOErrors))"
      )
    }

    // Back off to avoid a launchd "inefficient" kill.
    let exp = min(max(0, consecutiveUSBIOErrors - 1), 4)
    let backoff = min(usbIOErrorBackoffMaxNs, usbIOErrorBackoffBaseNs << exp)
    try? await Task.sleep(nanoseconds: backoff)
    guard isCurrentUSBRun(generation) else { return .stop }

    guard consecutiveUSBIOErrors >= usbIOErrorReconnectThreshold else { return .dispatched }
    print("[DevicePipeline] Too many USB I/O errors. Reconnecting:" + " \(identifier)")
    await invalidateUSBHandle(handle)
    return .stop
  }

  /// Throttles idle timeouts only.
  ///
  /// Successful packets dispatch at device cadence.
  private func pauseBeforeNextUSBPass(idle: Bool, loopStartNs: UInt64) async {
    let loopElapsedNs = uptimeNanoseconds() &- loopStartNs
    if idle, loopElapsedNs < usbIdleLoopCadenceNs {
      try? await Task.sleep(nanoseconds: usbIdleLoopCadenceNs &- loopElapsedNs)
    } else {
      await Task.yield()
    }
  }

  /// Stops the keep-alive, closes the session, and releases the output when the run is current.
  private func finishUSBInputLoop(
    handle: any USBTransportSession,
    generation: UInt64,
    recovery: USBInputLoopRecovery
  ) async {
    stopUSBKeepAlive()
    await invalidateUSBHandle(handle)
    if isCurrentUSBRun(generation) {
      await reportUSBInputOwnership(recovery == .accessDenied ? .accessDenied : .unknown)
      await neutralizeOutput()
    }
    print("[DevicePipeline] Input loop ended:" + " \(identifier)")
  }

  /// Sends keep-alives on their own timer, because an interrupt IN read can block until the
  /// controller reports, which an idle controller may not do for many seconds.
  func startUSBKeepAlive(handle: any USBTransportSession, generation: UInt64) {
    stopUSBKeepAlive()
    guard let interval = plan.usbKeepAliveIntervalNanoseconds ?? sessionKeepAliveIntervalNanoseconds
    else { return }
    usbKeepAliveTask = Task {
      while true {
        do { try await Task.sleep(nanoseconds: interval) } catch { return }
        guard isCurrentUSBRun(generation), usbHandle === handle else { return }
        await runKeepAlive(handle: handle, generation: generation)
      }
    }
  }

  /// Cancels the keep-alive timer.
  func stopUSBKeepAlive() {
    usbKeepAliveTask?.cancel()
    usbKeepAliveTask = nil
  }

  /// Sends one keep-alive run unless the run or session changed or the controller session is
  /// suspended.
  ///
  /// The timer keeps running while the session is suspended, so keep-alives return on resume.
  func runKeepAlive(handle: any USBTransportSession, generation: UInt64) async {
    guard isCurrentUSBRun(generation), usbHandle === handle, sessionState != .suspended else {
      return
    }
    // The run's writes are produced inside the write queue, after any command queued before it,
    // so a rumble stop encoded earlier is not followed by a resend of the state it ended.
    do {
      try await usbOutputWriteQueue.perform { [weak self] in
        await self?.sendKeepAliveWrites(handle: handle, generation: generation)
      }
    } catch {
      print("[DevicePipeline] Keep-alive failed" + " for \(identifier): \(error)")
    }
  }

  /// Produces and sends one keep-alive run.
  ///
  /// Runs inside ``usbOutputWriteQueue``.
  private func sendKeepAliveWrites(handle: any USBTransportSession, generation: UInt64) async {
    guard isCurrentUSBRun(generation), usbHandle === handle, sessionState != .suspended else {
      return
    }
    for write in driver.keepAliveWrites() + sessionKeepAliveWrites() {
      guard isCurrentUSBRun(generation), usbHandle === handle else { return }
      do {
        guard case .usb(let packet, _) = write else { throw USBTransportError.notSupported }
        _ = try await writeUSBPacketInQueue(
          handle: handle,
          endpoint: packet.endpoint,
          data: packet.bytes,
          timeout: packet.timeoutMilliseconds,
          runGeneration: generation
        )
      } catch { print("[DevicePipeline] Keep-alive failed" + " for \(identifier): \(error)") }
    }
  }

  /// Reads one interrupt packet from `inEndpoint`, waiting at most `timeout` milliseconds, or with
  /// no deadline when `timeout` is 0.
  func readInterrupt(
    handle: any USBTransportSession,
    inEndpoint: UInt8,
    timeout: UInt32 = 0
  ) async throws -> [UInt8] {
    try await handle.read(endpoint: inEndpoint, length: gipReadPacketLength, timeout: timeout)
  }

  // Ending a pending interrupt read can lose the report the pad sends in it, and a pad that reports
  // only on a change, such as a GIP or XUSB pad, sends a lost button release no second time, so the
  // button stays down. Linux xpad and XPadMac never cancel a read. A read here gets a deadline only
  // while the silent-startup window runs, so the recovery that needs a timeout to run can (#59).
  /// The timeout of the next interrupt IN read in milliseconds, where 0 waits with no deadline.
  ///
  /// - Parameters:
  ///   - window: The plan's silent-startup recovery window in nanoseconds, or nil when the plan has
  ///     no recovery.
  ///   - silentSince: When the current silent window started, or nil once the pad reported or the
  ///     recovery gave up.
  ///   - now: The current uptime in nanoseconds.
  /// - Returns: The time left in the window, at least 1 ms, while a window runs; otherwise 0.
  static func usbInputReadTimeoutMilliseconds(
    window: UInt64?,
    silentSince: UInt64?,
    now: UInt64
  ) -> UInt32 {
    guard let window, let silentSince else { return 0 }
    let remaining = window &- min(now &- silentSince, window)
    let milliseconds = (remaining + 999_999) / 1_000_000
    return UInt32(clamping: max(1, milliseconds))
  }

  /// Sends the writes that the driver deferred while it parsed; stops when the run or session
  /// changes.
  func sendPendingUSBWrites(handle: any USBTransportSession, generation: UInt64) async {
    guard isCurrentUSBRun(generation), usbHandle === handle else { return }
    for write in driver.drainPendingWrites() {
      guard isCurrentUSBRun(generation), usbHandle === handle else { return }
      do { try await performUSBWrite(write, handle: handle, runGeneration: generation) } catch {
        print("[DevicePipeline] Deferred USB output failed for \(identifier): \(error)")
      }
    }
  }

  /// Starts the task that checks input liveness at the monitor interval, replacing the earlier one.
  func startIdleMonitor() {
    idleMonitorTask?.cancel()
    idleMonitorTask = Task {
      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: idleMonitorIntervalNanoseconds)
        await self.evaluateIdleSleep()
      }
    }
  }

  /// Releases the output when no fresh input report arrived within the liveness timeout of the
  /// plan.
  func evaluateIdleSleep() async {
    guard isActive else { return }
    if let timeout = plan.inputReportLivenessTimeoutNanoseconds,
      let last = lastLiveInputReportNanoseconds ?? inputHealthMonitoringStartedNanoseconds,
      uptimeNanoseconds() - last >= timeout
    {
      await retireOutputAfterLivenessLoss()
    }
  }

  /// Closes `handle` after its shutdown writes when it is still the current session, and resets the
  /// driver.
  ///
  /// A plan that needs a presence reply before output also ends the input connection, so the next
  /// session connects it again.
  func invalidateUSBHandle(_ handle: any USBTransportSession) async {
    guard let current = usbHandle, ObjectIdentifier(current) == ObjectIdentifier(handle) else {
      return
    }
    usbHandle = nil
    stopUSBKeepAlive()
    await sendUSBShutdownWrites(handle: handle)
    await handle.close()
    driver.resetProtocolState()
    // The driver forgot presence with the session, so the next session's presence reply must
    // connect the controller again here too.
    if requiresInputConnectionBeforeOutput(), inputConnectionActive { await endInputConnection() }
  }
}
