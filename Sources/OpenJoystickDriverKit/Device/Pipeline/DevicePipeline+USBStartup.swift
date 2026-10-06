import Foundation

/// Checks whether USB startup can continue after the device rejects one startup write.
public func isIgnorableUSBStartupOutputError(
  _ write: PhysicalOutputWrite,
  error: USBTransportError
) -> Bool {
  guard case .usb(_, toleratesRejection: true) = write else { return false }
  switch error {
  case .inputOutput, .notFound, .notSupported, .timeout: return true
  default: return false
  }
}

extension DevicePipeline {
  enum USBInputLoopRecovery: Equatable {
    case reconnect
    case accessDenied
  }

  enum USBOpenResult {
    case opened(any USBTransportSession)
    case unavailable(USBTransportError)
  }

  // MARK: - Private USB pipeline

  func startUSBPipeline(device: USBTransportDevice, generation: UInt64) async {
    guard let provider = usbTransportProvider else {
      print("[DevicePipeline] Missing USB transport provider for \(identifier)")
      isActive = false
      return
    }

    var openAttempt: Int = 0
    while isCurrentUSBRun(generation) {
      let openResult = await openDeviceWithRetry(
        provider: provider,
        device: device,
        runGeneration: generation
      )
      guard isCurrentUSBRun(generation) else {
        if case .opened(let handle) = openResult { await handle.close() }
        return
      }
      guard case .opened(let handle) = openResult else {
        let ownership: HIDInputOwnership
        if case .unavailable(.accessDenied) = openResult {
          ownership = .accessDenied
        } else {
          ownership = .acquisitionFailed
        }
        await reportUSBInputOwnership(ownership)
        guard isCurrentUSBRun(generation) else { return }
        usbSessionStartFailed = true
        openAttempt += 1
        let delay: UInt64
        if case .unavailable(.accessDenied) = openResult {
          if openAttempt == 1 {
            print(
              "[DevicePipeline] USB device is exclusively owned by another process; waiting:"
                + " \(identifier)"
            )
          }
          delay = usbRecoveryPolicy.accessContentionDelayNanoseconds
        } else {
          print("[DevicePipeline] USB device unavailable; retrying: \(identifier)")
          delay = usbRecoveryPolicy.reconnectDelayNanoseconds(after: openAttempt)
        }
        try? await Task.sleep(nanoseconds: delay)
        continue
      }
      usbHandle = handle
      consecutiveUSBIOErrors = 0
      driver.resetProtocolState()

      guard await performUSBHandshake(handle: handle, runGeneration: generation) else {
        guard isCurrentUSBRun(generation) else { return }
        usbSessionStartFailed = true
        await resetUSBDeviceIfUnresponsive(device, provider: provider)
        // Try again while active, but slow down to avoid hot loops that launchd may kill
        // as "inefficient".
        openAttempt += 1
        let delay = usbRecoveryPolicy.reconnectDelayNanoseconds(after: openAttempt)
        try? await Task.sleep(nanoseconds: delay)
        continue
      }

      guard isCurrentUSBRun(generation) else {
        await handle.close()
        if let current = usbHandle, ObjectIdentifier(current) == ObjectIdentifier(handle) {
          usbHandle = nil
        }
        return
      }

      usbSessionStartFailed = false
      let ownership = await handle.inputOwnership
      guard isCurrentUSBRun(generation) else { return }
      await reportUSBInputOwnership(ownership)
      guard isCurrentUSBRun(generation) else { return }
      openAttempt = 0
      if !requiresInputConnectionBeforeOutput(), sessionState == .active { await activateOutput() }

      let recovery = await runUSBInputLoop(handle: handle, generation: generation)

      guard isCurrentUSBRun(generation) else { return }

      // Prevent immediate reopen loops.
      openAttempt += 1
      let delay: UInt64
      switch recovery {
      case .reconnect: delay = usbRecoveryPolicy.reconnectDelayNanoseconds(after: openAttempt)
      case .accessDenied: delay = usbRecoveryPolicy.accessContentionDelayNanoseconds
      }
      try? await Task.sleep(nanoseconds: delay)
    }
  }

  func isCurrentUSBRun(_ generation: UInt64) -> Bool {
    isActive && usbRunGeneration == generation && !Task.isCancelled
  }

  func isCurrentUSBOperation(_ generation: UInt64?) -> Bool {
    guard !Task.isCancelled else { return false }
    if let generation { return isActive && usbRunGeneration == generation }
    return true
  }

  func reportUSBInputOwnership(_ ownership: HIDInputOwnership) async {
    if let listener = dispatcher as? any ControllerInputOwnershipListener {
      usbOwnershipReportsInFlight += 1
      defer { usbOwnershipReportsInFlight -= 1 }
      await listener.controllerInputOwnershipChanged(ownership, for: identifier)
    }
  }

  func performUSBHandshake(
    handle: any USBTransportSession,
    runGeneration: UInt64? = nil
  ) async -> Bool {
    let retryDelays = plan.usbStartupRetryDelays
    lastUSBStartupError = nil
    for attempt in 0...retryDelays.count {
      guard isCurrentUSBOperation(runGeneration) else { return false }
      do {
        try await sendUSBStartupOutputPackets(handle: handle, runGeneration: runGeneration)
        guard isCurrentUSBOperation(runGeneration) else { return false }
        startupOutputStatus = "succeeded"
        print("[DevicePipeline] Handshake complete:" + " \(identifier)")
        return true
      } catch {
        startupOutputStatus = "failed: \(error)"
        lastUSBStartupError = error as? USBTransportError
        print(
          "[DevicePipeline] Handshake attempt \(attempt + 1) failed for \(identifier): \(error)"
        )
        guard attempt < retryDelays.count else { break }
        do { try await Task.sleep(nanoseconds: retryDelays[attempt]) } catch { break }
        guard isCurrentUSBOperation(runGeneration) else { return false }
      }
    }
    guard isCurrentUSBOperation(runGeneration) else { return false }
    if let current = usbHandle, ObjectIdentifier(current) == ObjectIdentifier(handle) {
      usbHandle = nil
    }
    await handle.close()
    return false
  }

  /// A controller that stayed attached through system sleep can open again but fail every write
  /// as disconnected until its port is reset. A Razer Wolverine Tournament Edition (1532:0A15) did
  /// this after wake. The reset enumerates the device again, as a replug does, and the device
  /// manager starts a new pipeline for the returned device.
  func resetUSBDeviceIfUnresponsive(
    _ device: USBTransportDevice,
    provider: any USBTransportProvider
  ) async {
    guard !usbDeviceResetAttempted, lastUSBStartupError == .disconnected else { return }
    usbDeviceResetAttempted = true
    do {
      try await provider.resetDevice(device)
      print("[DevicePipeline] Reset USB device after its startup failed: \(identifier)")
    } catch { print("[DevicePipeline] USB device reset failed for \(identifier): \(error)") }
  }

  /// The driver's startup writes, then the assigned player slot unless the slot waits for an
  /// input connection.
  func usbStartupWrites() -> [PhysicalOutputWrite] {
    guard !plan.requiresInputConnectionBeforeOutput else {
      return driver.startupWrites()
    }
    return driver.startupWrites() + assignedPlayerIndicatorWrites()
  }

  /// The write lighting the manager-assigned player slot. A pad that rejects only its ring LED
  /// still starts, so the write tolerates rejection.
  func assignedPlayerIndicatorWrites() -> [PhysicalOutputWrite] {
    guard let indicator = usbStartupPlayerIndicator,
      let plan = try? driver.encode(.setPlayerIndicator(indicator))
    else { return [] }
    return plan.writes.map { write in
      guard case .usb(let packet, _) = write else { return write }
      return .usb(packet, toleratesRejection: true)
    }
  }

  func sendUSBStartupOutputPackets(
    handle: any USBTransportSession,
    runGeneration: UInt64? = nil
  ) async throws {
    let writes = usbStartupWrites()
    let interval = plan.usbStartupIntervalNanoseconds
    for (index, write) in writes.enumerated() {
      let handleIsCurrent: Bool
      if let currentHandle = usbHandle {
        handleIsCurrent = ObjectIdentifier(currentHandle) == ObjectIdentifier(handle)
      } else {
        handleIsCurrent = true
      }
      guard isCurrentUSBOperation(runGeneration), handleIsCurrent else { throw CancellationError() }
      do {
        try await performUSBWrite(write, handle: handle, runGeneration: runGeneration)
        guard isCurrentUSBOperation(runGeneration) else { throw CancellationError() }
      } catch let error as USBTransportError
        where isIgnorableUSBStartupOutputError(write, error: error)
      {
        print(
          "[DevicePipeline] Optional USB startup output rejected for \(identifier):" + " \(error)"
        )
      }
      if index < writes.count - 1, interval > 0 {
        try await Task.sleep(nanoseconds: interval)
        guard isCurrentUSBOperation(runGeneration) else { throw CancellationError() }
      }
    }
  }

  func openDeviceWithRetry(
    provider: any USBTransportProvider,
    device: USBTransportDevice,
    runGeneration: UInt64? = nil
  ) async -> USBOpenResult {
    var lastError = USBTransportError.notFound
    for attempt in 0..<usbRecoveryPolicy.openRetryDelays.count {
      guard isCurrentUSBOperation(runGeneration) else { return .unavailable(.notFound) }
      do {
        let handle = try await provider.open(
          device,
          options: USBTransportOpenOptions(transportProfile: transportProfile)
        )
        guard isCurrentUSBOperation(runGeneration) else {
          await handle.close()
          return .unavailable(.notFound)
        }
        return .opened(handle)
      } catch let error as USBTransportError {
        lastError = error
        if error == .accessDenied { return .unavailable(error) }
        handleOpenDeviceError(error, attempt: attempt)
        if attempt < usbRecoveryPolicy.openRetryDelays.count - 1 {
          try? await Task.sleep(nanoseconds: usbRecoveryPolicy.openRetryDelays[attempt])
          guard isCurrentUSBOperation(runGeneration) else { return .unavailable(.notFound) }
        }
      } catch {
        let transportError = USBTransportError.platform(code: 0, message: String(describing: error))
        lastError = transportError
        handleOpenDeviceError(transportError, attempt: attempt)
        if attempt < usbRecoveryPolicy.openRetryDelays.count - 1 {
          try? await Task.sleep(nanoseconds: usbRecoveryPolicy.openRetryDelays[attempt])
          guard isCurrentUSBOperation(runGeneration) else { return .unavailable(.notFound) }
        }
      }
    }
    return .unavailable(lastError)
  }

  func handleOpenDeviceError(_ error: Error, attempt: Int) {
    print("[DevicePipeline] Open attempt \(attempt + 1) failed" + " for \(identifier): \(error)")
  }
}
