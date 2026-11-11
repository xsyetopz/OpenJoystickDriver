import Foundation

extension DevicePipeline {
  /// Reads the interrupt IN endpoint of `handle` and dispatches the parsed input until the run
  /// ends.
  ///
  /// An idle pass lasts at least the loop cadence, so a transport that completes timeouts at once
  /// cannot spin. Repeated I/O errors back off and then end the session.
  ///
  /// - Parameter armedRead: The read started before the startup writes; the first pass takes its
  ///   result in place of a new read.
  /// - Returns: How the caller goes on: reconnect, or wait before opening again after an access
  ///   denial.
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

    var recovery = USBInputLoopRecovery.reconnect
    var firstRead = armedRead
    while isCurrentUSBRun(generation) {
      let loopStartNs = uptimeNanoseconds()
      var shouldBreak = false
      var shouldThrottleIdle = false
      recovery = .reconnect
      do {
        let bytes: [UInt8]
        if let armed = firstRead {
          firstRead = nil
          bytes = try await armed.value
        } else {
          bytes = try await readInterrupt(handle: handle, inEndpoint: inEndpoint)
        }
        guard isCurrentUSBRun(generation) else { break }
        consecutiveUSBIOErrors = 0
        appendToPacketLog(bytes: bytes, direction: .received)
        let receivedAt = uptimeNanoseconds()
        let event = try parseReport(Data(bytes), receivedAt: receivedAt)
        await sendPendingUSBWrites(handle: handle, generation: generation)
        guard isCurrentUSBRun(generation) else { break }
        _ = await handleInputConnectionStateChangeIfNeeded()
        guard isCurrentUSBRun(generation) else { break }
        if inputConnectionActive { await handleParsedEvent(event, now: receivedAt) }
        guard isCurrentUSBRun(generation) else { break }
      } catch let error as USBTransportError where error.isTimeout {
        guard isCurrentUSBRun(generation) else { break }
        // No data in this interval; throttle below to avoid a hot timeout loop.
        shouldThrottleIdle = true
      } catch let error as USBTransportError where error.isDisconnected {
        guard isCurrentUSBRun(generation) else { break }
        print("[DevicePipeline] Device disconnected:" + " \(identifier)")
        await invalidateUSBHandle(handle)
        shouldBreak = true
      } catch let error as USBTransportError where error == .accessDenied {
        guard isCurrentUSBRun(generation) else { break }
        print("[DevicePipeline] USB read access denied; waiting before retry: \(identifier)")
        await invalidateUSBHandle(handle)
        recovery = .accessDenied
        shouldBreak = true
      } catch let error as USBTransportError where error.isInputOutput {
        guard isCurrentUSBRun(generation) else { break }
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
        guard isCurrentUSBRun(generation) else { break }

        if consecutiveUSBIOErrors >= usbIOErrorReconnectThreshold {
          print("[DevicePipeline] Too many USB I/O errors. Reconnecting:" + " \(identifier)")
          await invalidateUSBHandle(handle)
          shouldBreak = true
        }
      } catch {
        guard isCurrentUSBRun(generation) else { break }
        // Slow down after an unknown failure, then reconnect.
        print("[DevicePipeline] Read error" + " for \(identifier):" + " \(error). Reconnecting")
        await invalidateUSBHandle(handle)
        shouldBreak = true
      }

      if shouldBreak { break }
      guard isCurrentUSBRun(generation) else { break }

      // Throttle idle timeouts only. Successful packets should dispatch at device cadence.
      let loopElapsedNs = uptimeNanoseconds() &- loopStartNs
      if shouldThrottleIdle && loopElapsedNs < usbIdleLoopCadenceNs {
        try? await Task.sleep(nanoseconds: usbIdleLoopCadenceNs &- loopElapsedNs)
      } else {
        await Task.yield()
      }
    }

    stopUSBKeepAlive()
    await invalidateUSBHandle(handle)
    if isCurrentUSBRun(generation) {
      await reportUSBInputOwnership(recovery == .accessDenied ? .accessDenied : .unknown)
      await neutralizeOutput()
    }
    print("[DevicePipeline] Input loop ended:" + " \(identifier)")
    return recovery
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

  /// Reads one interrupt packet from `inEndpoint`.
  func readInterrupt(handle: any USBTransportSession, inEndpoint: UInt8) async throws -> [UInt8] {
    try await handle.read(
      endpoint: inEndpoint,
      length: gipReadPacketLength,
      timeout: gipReadTimeoutMs
    )
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
