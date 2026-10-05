import Foundation

extension DevicePipeline {
  func runUSBInputLoop(
    handle: any USBTransportSession,
    generation: UInt64
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
    while isCurrentUSBRun(generation) {
      let loopStartNs = uptimeNanoseconds()
      var shouldBreak = false
      var shouldThrottleIdle = false
      recovery = .reconnect
      do {
        let bytes = try await readInterrupt(handle: handle, inEndpoint: inEndpoint)
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
    guard let interval = driver.sessionPlan.usbKeepAliveIntervalNanoseconds else { return }
    usbKeepAliveTask = Task {
      while true {
        do { try await Task.sleep(nanoseconds: interval) } catch { return }
        guard isCurrentUSBRun(generation), usbHandle === handle else { return }
        await runKeepAlive(handle: handle, generation: generation)
      }
    }
  }

  func stopUSBKeepAlive() {
    usbKeepAliveTask?.cancel()
    usbKeepAliveTask = nil
  }

  /// Skips the writes while the session is suspended; the timer keeps running, so keep-alives
  /// return on resume. Linux xpad sends no periodic GIP keep-alive at all.
  func runKeepAlive(handle: any USBTransportSession, generation: UInt64) async {
    guard isCurrentUSBRun(generation), usbHandle === handle, sessionState != .suspended else {
      return
    }
    for write in driver.keepAliveWrites() {
      guard isCurrentUSBRun(generation), usbHandle === handle else { return }
      do { try await performUSBWrite(write, handle: handle, runGeneration: generation) } catch {
        print("[DevicePipeline] Keep-alive failed" + " for \(identifier): \(error)")
      }
    }
  }

  func readInterrupt(handle: any USBTransportSession, inEndpoint: UInt8) async throws -> [UInt8] {
    try await handle.read(
      endpoint: inEndpoint,
      length: gipReadPacketLength,
      timeout: gipReadTimeoutMs
    )
  }

  func sendPendingUSBWrites(handle: any USBTransportSession, generation: UInt64) async {
    guard isCurrentUSBRun(generation), usbHandle === handle else { return }
    for write in driver.drainPendingWrites() {
      guard isCurrentUSBRun(generation), usbHandle === handle else { return }
      do { try await performUSBWrite(write, handle: handle, runGeneration: generation) } catch {
        print("[DevicePipeline] Deferred USB output failed for \(identifier): \(error)")
      }
    }
  }

  func startIdleMonitor() {
    idleMonitorTask?.cancel()
    idleMonitorTask = Task {
      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: idleMonitorIntervalNanoseconds)
        await self.evaluateIdleSleep()
      }
    }
  }

  func evaluateIdleSleep() async {
    guard isActive else { return }
    if let timeout = driver.sessionPlan.inputReportLivenessTimeoutNanoseconds,
      let last = lastLiveInputReportNanoseconds ?? inputHealthMonitoringStartedNanoseconds,
      uptimeNanoseconds() - last >= timeout
    {
      await retireOutputAfterLivenessLoss()
    }
  }

  func invalidateUSBHandle(_ handle: any USBTransportSession) async {
    guard let current = usbHandle, ObjectIdentifier(current) == ObjectIdentifier(handle) else {
      return
    }
    usbHandle = nil
    stopUSBKeepAlive()
    await handle.close()
    driver.resetProtocolState()
    // The driver forgot presence with the session, so the next session's presence reply must
    // connect the controller again here too.
    if requiresInputConnectionBeforeOutput(), inputConnectionActive { await endInputConnection() }
  }
}
