import Foundation
import SwiftUSB

extension DevicePipeline {
  // MARK: - Private USB pipeline

  func startUSBPipeline(vendorID: UInt16, productID: UInt16) async {
    guard let context = usbContext else {
      print("[DevicePipeline] Missing USBContext for \(identifier)")
      isActive = false
      return
    }

    var openAttempt: Int = 0
    while isActive {
      guard
        let handle = await openDeviceWithRetry(
          context: context,
          vendorID: vendorID,
          productID: productID
        )
      else {
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

  func performUSBHandshake(handle: USBDeviceHandle) async -> Bool {
    do {
      try await parser.performHandshake(handle: handle)
      try sendUSBStartupOutputPackets(handle: handle)
      print("[DevicePipeline] Handshake complete:" + " \(identifier)")
      return true
    } catch {
      print("[DevicePipeline] Handshake failed" + " for \(identifier): \(error)")
      try? handle.releaseInterface(0)
      usbHandle = nil
      return false
    }
  }

  func sendUSBStartupOutputPackets(handle: USBDeviceHandle) throws {
    guard let startupOutput = parser as? USBStartupOutputProvider else { return }
    for packet in startupOutput.usbStartupOutputPackets() {
      _ = try handle.interruptTransfer(
        endpoint: transportProfile.outputEndpoint,
        data: packet,
        timeout: 2000
      )
      appendToPacketLog(bytes: packet, direction: "tx")
    }
  }

  func openDeviceWithRetry(context: USBContext, vendorID: UInt16, productID: UInt16) async
    -> USBDeviceHandle?
  {
    for attempt in 0..<usbOpenRetryDelays.count {
      do {
        guard
          let device = await findDevice(
            on: context,
            vendorID: vendorID,
            productID: productID,
            attempt: attempt
          )
        else {
          try await sleepForRetry(attempt: attempt)
          continue
        }
        return try openAndClaimDevice(device)
      } catch {
        handleOpenDeviceError(error, attempt: attempt)
        if attempt < usbOpenRetryDelays.count - 1 {
          try? await Task.sleep(nanoseconds: usbOpenRetryDelays[attempt])
        }
      }
    }
    return nil
  }

  func findDevice(on context: USBContext, vendorID: UInt16, productID: UInt16, attempt: Int)
    async -> USBDevice?
  {
    guard let device = await context.findDevice(vendorId: vendorID, productId: productID) else {
      print("[DevicePipeline] Device not found (attempt \(attempt + 1)):" + " \(identifier)")
      return nil
    }
    return device
  }

  func openAndClaimDevice(_ device: USBDevice) throws -> USBDeviceHandle {
    let handle = try device.open()
    if transportProfile.needsSetConfiguration {
      let cfg = (try? handle.getConfiguration()) ?? 0
      if cfg != 1 {
        try handle.setConfiguration(1)
      }
    }
    try handle.claimInterface(0)
    return handle
  }

  func handleOpenDeviceError(_ error: Error, attempt: Int) {
    print("[DevicePipeline] Open attempt \(attempt + 1) failed" + " for \(identifier): \(error)")
  }

  func sleepForRetry(attempt: Int) async throws {
    try await Task.sleep(nanoseconds: usbOpenRetryDelays[attempt])
  }

  func runUSBInputLoop(handle: USBDeviceHandle) async {
    let inEndpoint = transportProfile.inputEndpoint
    var lastKeepAliveNs = DispatchTime.now().uptimeNanoseconds
    print("[DevicePipeline] Starting USB input loop:" + " \(identifier)"
          + " inEP=0x\(String(inEndpoint, radix: 16))")

    if transportProfile.postHandshakeSettleNanoseconds > 0 {
      try? await Task.sleep(nanoseconds: transportProfile.postHandshakeSettleNanoseconds)
    }

    while isActive {
      let loopStartNs = DispatchTime.now().uptimeNanoseconds
      if !sleepGate.isSleeping,
        shouldSendKeepAlive(lastKeepAliveNs: lastKeepAliveNs, now: loopStartNs)
      {
        lastKeepAliveNs = loopStartNs
        runKeepAlive(handle: handle)
      }
      var shouldBreak = false
      var shouldThrottleIdle = false
      do {
        let bytes = try readInterrupt(handle: handle, inEndpoint: inEndpoint)
        consecutiveUSBIOErrors = 0
        appendToPacketLog(bytes: bytes, direction: "rx")
        let events = try parseEvents(from: bytes)
        await handleParsedEvents(events, now: DispatchTime.now().uptimeNanoseconds)
      } catch let error as USBError where error.isTimeout {
        // No data in this interval; throttle below to avoid a hot timeout loop.
        shouldThrottleIdle = true
      } catch let error as USBError where error.isNoDevice {
        print("[DevicePipeline] Device disconnected:" + " \(identifier)")
        shouldBreak = true
      } catch let error as USBError where error.isIOError {
        consecutiveUSBIOErrors += 1

        let now = DispatchTime.now().uptimeNanoseconds
        if now &- lastUSBIOErrorLogNs >= usbIOErrorLogIntervalNs {
          lastUSBIOErrorLogNs = now
          print(
            "[DevicePipeline] USB I/O error (will recover)" + " for \(identifier): \(error)"
              + " (consecutive=\(consecutiveUSBIOErrors))"
          )
        }

        // Back off aggressively to avoid triggering launchd "inefficient" kills.
        let exp = min(max(0, consecutiveUSBIOErrors - 1), 4)
        let backoff = min(usbIOErrorBackoffMaxNs, usbIOErrorBackoffBaseNs << exp)
        try? await Task.sleep(nanoseconds: backoff)

        if consecutiveUSBIOErrors >= usbIOErrorReconnectThreshold {
          print("[DevicePipeline] Too many USB I/O errors — reconnecting:" + " \(identifier)")
          shouldBreak = true
        }
      } catch {
        // Unknown failures: slow down and let the outer loop reconnect.
        print("[DevicePipeline] Read error" + " for \(identifier):" + " \(error) — reconnecting")
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
    try? handle.releaseInterface(0)
    usbHandle = nil
    print("[DevicePipeline] Input loop ended:" + " \(identifier)")
  }

  func shouldSendKeepAlive(lastKeepAliveNs: UInt64, now: UInt64) -> Bool {
    now &- lastKeepAliveNs >= keepAliveIntervalNs
  }

  func runKeepAlive(handle: USBDeviceHandle) {
    do { try parser.keepAlive(handle: handle) } catch {
      print("[DevicePipeline] Keep-alive failed" + " for \(identifier): \(error)")
    }
  }

  func readInterrupt(handle: USBDeviceHandle, inEndpoint: UInt8) throws -> [UInt8] {
    try handle.readInterrupt(
      endpoint: inEndpoint,
      length: gipReadPacketLength,
      timeout: gipReadTimeoutMs
    )
  }

  func parseEvents(from bytes: [UInt8]) throws -> [ControllerEvent] {
    try parser.parse(data: Data(bytes))
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
      )
        != nil
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
    let nextState = currentInputState.applying(events: events)
    updateObservedInputState(from: events)

    switch sleepGate.handleInput(
      events: events,
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
        if !events.isEmpty {
          waitingForExternalNeutral = false
          print(
            "[DevicePipeline] Foreground gate re-armed after first post-focus change: \(identifier)"
          )
          return
        }
        return
      }
      if !events.isEmpty {
        await dispatcher.dispatch(events: events, from: identifier)
      }
      updateOutputState(from: events)
    case .consumeWhileSleeping:
      break
    case .consumeWake:
      print("[DevicePipeline] Controller woke from sleep: \(identifier)")
    }
  }
}
