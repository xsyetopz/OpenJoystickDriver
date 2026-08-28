import Foundation

/// Checks whether USB startup can continue after an Xbox 360 ring LED rejection.
public func isIgnorableUSBStartupOutputError(
  parser: any InputParser,
  packet: [UInt8],
  error: USBTransportError
) -> Bool {
  guard parser is Xbox360Parser, packet == [0x01, 0x03, 0x06] else { return false }
  switch error {
  case .inputOutput, .notFound, .notSupported: return true
  default: return false
  }
}

extension DevicePipeline {
  // MARK: - Private USB pipeline

  func startUSBPipeline(device: USBTransportDevice) async {
    guard let provider = usbTransportProvider else {
      print("[DevicePipeline] Missing USB transport provider for \(identifier)")
      isActive = false
      return
    }

    var openAttempt: Int = 0
    while isActive {
      guard let handle = await openDeviceWithRetry(provider: provider, device: device) else {
        print("[DevicePipeline] Could not open USB device" + " \(identifier) after retries")
        isActive = false
        return
      }
      usbHandle = handle
      consecutiveUSBIOErrors = 0

      guard await performUSBHandshake(handle: handle) else {
        // Try again while active, but slow down to avoid hot loops that launchd may kill
        // as "inefficient".
        openAttempt += 1
        let delay = min(UInt64(4_000_000_000), UInt64(250_000_000) << min(openAttempt, 4))
        try? await Task.sleep(nanoseconds: delay)
        continue
      }

      await runUSBInputLoop(handle: handle)

      if !isActive { return }

      // Prevent immediate reopen loops.
      openAttempt += 1
      let delay = min(UInt64(4_000_000_000), UInt64(250_000_000) << min(openAttempt, 4))
      try? await Task.sleep(nanoseconds: delay)
    }
  }

  func performUSBHandshake(handle: any USBTransportSession) async -> Bool {
    do {
      try await parser.performHandshake(handle: handle)
      try await sendUSBStartupOutputPackets(handle: handle)
      print("[DevicePipeline] Handshake complete:" + " \(identifier)")
      return true
    } catch {
      print("[DevicePipeline] Handshake failed" + " for \(identifier): \(error)")
      await handle.close()
      usbHandle = nil
      return false
    }
  }

  func sendUSBStartupOutputPackets(handle: any USBTransportSession) async throws {
    guard let startupOutput = parser as? USBStartupOutputProvider else { return }
    for packet in startupOutput.usbStartupOutputPackets() {
      do {
        _ = try await handle.writeInterruptPacket(
          endpoint: transportProfile.outputEndpoint,
          data: packet,
          timeout: 2000
        )
        appendToPacketLog(bytes: packet, direction: "tx")
      } catch let error as USBTransportError
        where isIgnorableUSBStartupOutputError(parser: parser, packet: packet, error: error)
      {
        print(
          "[DevicePipeline] Optional USB startup output rejected for \(identifier):" + " \(error)"
        )
      }
    }
  }

  func openDeviceWithRetry(provider: any USBTransportProvider, device: USBTransportDevice) async
    -> (any USBTransportSession)?
  {
    for attempt in 0..<usbOpenRetryDelays.count {
      do {
        return try await provider.open(
          device,
          options: USBTransportOpenOptions(transportProfile: transportProfile)
        )
      } catch {
        handleOpenDeviceError(error, attempt: attempt)
        if attempt < usbOpenRetryDelays.count - 1 {
          try? await Task.sleep(nanoseconds: usbOpenRetryDelays[attempt])
        }
      }
    }
    return nil
  }

  func handleOpenDeviceError(_ error: Error, attempt: Int) {
    print("[DevicePipeline] Open attempt \(attempt + 1) failed" + " for \(identifier): \(error)")
  }

  func runUSBInputLoop(handle: any USBTransportSession) async {
    let inEndpoint = transportProfile.inputEndpoint
    var lastKeepAliveNs = DispatchTime.now().uptimeNanoseconds
    print(
      "[DevicePipeline] Starting USB input loop:" + " \(identifier)"
        + " inEP=0x\(String(inEndpoint, radix: 16))"
    )

    if transportProfile.postHandshakeSettleNanoseconds > 0 {
      try? await Task.sleep(nanoseconds: transportProfile.postHandshakeSettleNanoseconds)
    }

    while isActive {
      let loopStartNs = DispatchTime.now().uptimeNanoseconds
      if !sleepGate.isSleeping,
        shouldSendKeepAlive(lastKeepAliveNs: lastKeepAliveNs, now: loopStartNs)
      {
        lastKeepAliveNs = loopStartNs
        await runKeepAlive(handle: handle)
      }
      var shouldBreak = false
      var shouldThrottleIdle = false
      do {
        let bytes = try await readInterrupt(handle: handle, inEndpoint: inEndpoint)
        consecutiveUSBIOErrors = 0
        appendToPacketLog(bytes: bytes, direction: "rx")
        let events = try parseEvents(from: bytes)
        await sendDeferredUSBOutputPackets(handle: handle)
        _ = await handleInputConnectionStateChangeIfNeeded()
        if inputConnectionActive {
          await handleParsedEvents(events, now: DispatchTime.now().uptimeNanoseconds)
        }
      } catch let error as USBTransportError where error.isTimeout {
        // No data in this interval; throttle below to avoid a hot timeout loop.
        shouldThrottleIdle = true
      } catch let error as USBTransportError where error.isDisconnected {
        print("[DevicePipeline] Device disconnected:" + " \(identifier)")
        shouldBreak = true
      } catch let error as USBTransportError where error.isInputOutput {
        consecutiveUSBIOErrors += 1

        let now = DispatchTime.now().uptimeNanoseconds
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

        if consecutiveUSBIOErrors >= usbIOErrorReconnectThreshold {
          print("[DevicePipeline] Too many USB I/O errors. Reconnecting:" + " \(identifier)")
          shouldBreak = true
        }
      } catch {
        // Slow down after an unknown failure, then reconnect.
        print("[DevicePipeline] Read error" + " for \(identifier):" + " \(error). Reconnecting")
        try? await Task.sleep(nanoseconds: 250_000_000)
        shouldBreak = true
      }

      if shouldBreak { break }

      // Throttle idle timeouts only. Successful packets should dispatch at device cadence.
      let loopElapsedNs = DispatchTime.now().uptimeNanoseconds &- loopStartNs
      if shouldThrottleIdle && loopElapsedNs < usbIdleLoopCadenceNs {
        try? await Task.sleep(nanoseconds: usbIdleLoopCadenceNs &- loopElapsedNs)
      } else {
        await Task.yield()
      }
    }

    await neutralizeOutput()
    await handle.close()
    usbHandle = nil
    print("[DevicePipeline] Input loop ended:" + " \(identifier)")
  }

  func shouldSendKeepAlive(lastKeepAliveNs: UInt64, now: UInt64) -> Bool {
    now &- lastKeepAliveNs >= keepAliveIntervalNs
  }

  func runKeepAlive(handle: any USBTransportSession) async {
    do { try await parser.keepAlive(handle: handle) } catch {
      print("[DevicePipeline] Keep-alive failed" + " for \(identifier): \(error)")
    }
  }

  func readInterrupt(handle: any USBTransportSession, inEndpoint: UInt8) async throws -> [UInt8] {
    try await handle.readInterruptPacket(
      endpoint: inEndpoint,
      length: gipReadPacketLength,
      timeout: gipReadTimeoutMs
    )
  }

  func parseEvents(from bytes: [UInt8]) throws -> [ControllerEvent] {
    try parser.parse(data: Data(bytes))
  }

  func sendDeferredUSBOutputPackets(handle: any USBTransportSession) async {
    guard let output = parser as? any USBDeferredOutputProvider else { return }
    for packet in output.consumeUSBOutputPackets() {
      do {
        _ = try await handle.writeInterruptPacket(
          endpoint: transportProfile.outputEndpoint,
          data: packet,
          timeout: 2_000
        )
        appendToPacketLog(bytes: packet, direction: "tx")
      } catch {
        print("[DevicePipeline] Deferred USB output failed for \(identifier): \(error)")
        break
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
    guard
      sleepGate.idleTransition(
        currentState: currentInputState,
        now: DispatchTime.now().uptimeNanoseconds
      ) != nil
    else { return }

    let neutralizingEvents = outputState.neutralizingEvents()
    print("[DevicePipeline] Controller sleeping after idle: \(identifier)")
    if !neutralizingEvents.isEmpty {
      await dispatcher.dispatch(events: neutralizingEvents, from: identifier)
      updateOutputState(from: neutralizingEvents)
    }
  }

  func handleParsedEvents(_ events: [ControllerEvent], now: UInt64) async {
    let previousState = currentInputState
    let normalizedEvents = ControllerEventNormalizer.normalize(events, from: previousState).events
    let nextState = previousState.applying(events: normalizedEvents)
    updateObservedInputState(from: normalizedEvents)

    switch sleepGate.handleInput(
      events: normalizedEvents,
      previousState: previousState,
      nextState: nextState,
      now: now
    ) {
    case .forward:
      if !externalOutputAllowed { return }
      if waitingForExternalNeutral {
        if nextState.isEffectivelyNeutral {
          waitingForExternalNeutral = false
          print("[DevicePipeline] Foreground gate re-armed after neutral: \(identifier)")
          return
        }
        if !normalizedEvents.isEmpty {
          waitingForExternalNeutral = false
          print(
            "[DevicePipeline] Foreground gate re-armed after first post-focus change: \(identifier)"
          )
          return
        }
        return
      }
      if !normalizedEvents.isEmpty {
        await dispatcher.dispatch(events: normalizedEvents, from: identifier)
      }
      updateOutputState(from: normalizedEvents)
    case .consumeWhileSleeping: break
    case .consumeWake: print("[DevicePipeline] Controller woke from sleep: \(identifier)")
    }
  }
}
