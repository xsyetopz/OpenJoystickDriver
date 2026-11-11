import Foundation

/// Whether USB startup may go on after the device rejected `write`.
///
/// Only a write that tolerates rejection is ignorable, and only for an I/O error, a missing
/// endpoint, an unsupported transfer or a timeout.
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
  /// How the USB run goes on after its input loop ended.
  enum USBInputLoopRecovery: Equatable {
    /// Open the device again after the reconnect wait.
    case reconnect
    /// Open the device again after the access-contention wait.
    case accessDenied
  }

  /// The outcome of opening the USB device.
  enum USBOpenResult {
    /// The session that opened.
    case opened(any USBTransportSession)
    /// The transport error that ended the open attempts.
    case unavailable(USBTransportError)
  }

  // MARK: - Private USB pipeline

  /// Runs the USB session loop of one run: opens the device, performs the handshake, reads input,
  /// and opens again after a failure for as long as the run is current.
  ///
  /// An interface that another client holds is waited for, not seized. The waits between attempts
  /// grow with the reconnect policy.
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
        var holder: USBExclusiveOwner?
        switch openResult {
        case .unavailable(.accessDenied): ownership = .accessDenied
        case .unavailable(.ownedByAnotherClient(let owner)):
          ownership = .ownedByAnotherClient
          holder = owner.flatMap(USBExclusiveOwner.init(registryValue:))
        default: ownership = .acquisitionFailed
        }
        let wasHeld = usbOwnedByAnotherClient
        usbExclusiveOwner = holder
        usbOwnedByAnotherClient = ownership == .ownedByAnotherClient
        await reportUSBInputOwnership(ownership)
        guard isCurrentUSBRun(generation) else { return }
        usbSessionStartFailed = true
        openAttempt += 1
        if ownership == .ownedByAnotherClient {
          // Another client reading the pad directly is a valid state: the pipeline does not
          // request or seize the interface, and opens it when the owner lets go.
          if !wasHeld {
            print(
              "[DevicePipeline] USB interface is used by \(holder?.name ?? "another client"); "
                + "opening it when it is released: \(identifier)"
            )
          }
          if await waitForUSBRelease(provider: provider, device: device) {
            guard isCurrentUSBRun(generation) else { return }
            print("[DevicePipeline] USB interface was released; opening it: \(identifier)")
            continue
          }
        }
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
      usbOwnedByAnotherClient = false
      usbExclusiveOwner = nil
      consecutiveUSBIOErrors = 0
      driver.resetProtocolState()

      // Linux reads the IN endpoint before it writes the first startup packet; a pad that sends
      // its first report once, without an announce, sends it to that read.
      let armedRead = plan.armsInputBeforeStartup ? armInputRead(handle: handle) : nil

      guard
        await performUSBHandshake(handle: handle, device: device, runGeneration: generation)
      else {
        armedRead?.cancel()
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

      let recovery = await runUSBInputLoop(
        handle: handle,
        generation: generation,
        armedRead: armedRead
      )

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

  /// Starts the interrupt IN read that the input loop takes as its first read.
  func armInputRead(handle: any USBTransportSession) -> Task<[UInt8], any Error> {
    let endpoint = transportProfile.inputEndpoint
    return Task {
      try await handle.read(endpoint: endpoint, length: gipReadPacketLength, timeout: gipReadTimeoutMs)
    }
  }

  /// Waits for the platform to announce that the exclusive owner let go of the interface.
  ///
  /// Returns false when the wait failed, so the caller retries after its backoff.
  func waitForUSBRelease(
    provider: any USBTransportProvider,
    device: USBTransportDevice
  ) async -> Bool {
    do {
      try await provider.waitForRelease(
        of: device,
        interfaceNumber: transportProfile.interfaceNumber
      )
      return true
    } catch {
      print(
        "[DevicePipeline] Waiting for the USB owner to release failed for \(identifier): \(error)"
      )
      return false
    }
  }

  /// Whether the run `generation` is the current run: the pipeline is active, the generation
  /// matches and the task is not cancelled.
  func isCurrentUSBRun(_ generation: UInt64) -> Bool {
    isActive && usbRunGeneration == generation && !Task.isCancelled
  }

  /// Whether a USB operation may go on: its task is not cancelled and, when it names a run, that
  /// run is current.
  func isCurrentUSBOperation(_ generation: UInt64?) -> Bool {
    guard !Task.isCancelled else { return false }
    if let generation { return isActive && usbRunGeneration == generation }
    return true
  }

  /// Tells the dispatcher who owns the USB input of the controller, when it listens for that.
  ///
  /// The report in flight is counted, so ``stop()`` waits for it.
  func reportUSBInputOwnership(_ ownership: HIDInputOwnership) async {
    if let listener = dispatcher as? any ControllerInputOwnershipListener {
      usbOwnershipReportsInFlight += 1
      defer { usbOwnershipReportsInFlight -= 1 }
      await listener.controllerInputOwnershipChanged(ownership, for: identifier)
    }
  }

  /// Runs the control transfers and the startup output of a USB session, retrying after the delays
  /// of the session plan.
  ///
  /// The result is kept as the startup output status. After the last failed attempt it closes
  /// `handle`.
  ///
  /// - Returns: Whether startup succeeded.
  func performUSBHandshake(
    handle: any USBTransportSession,
    device: USBTransportDevice? = nil,
    runGeneration: UInt64? = nil
  ) async -> Bool {
    let retryDelays = plan.usbStartupRetryDelays
    lastUSBStartupError = nil
    for attempt in 0...retryDelays.count {
      guard isCurrentUSBOperation(runGeneration) else { return false }
      do {
        try await performControlTransfers(
          handle: handle,
          device: device,
          runGeneration: runGeneration
        )
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

  /// Resets the USB port of the device once when its startup failed as disconnected.
  ///
  /// A controller that stayed attached through system sleep can open again but fail every write as
  /// disconnected until its port is reset. The reset enumerates the device again, as a replug does,
  /// and the device manager starts a new pipeline for the returned device.
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

  /// The write lighting the manager-assigned player slot.
  ///
  /// A pad that rejects only its ring LED still starts, so the write tolerates rejection.
  func assignedPlayerIndicatorWrites() -> [PhysicalOutputWrite] {
    guard let indicator = startupPlayerIndicator,
      let plan = try? driver.encode(.setPlayerIndicator(indicator))
    else { return [] }
    return plan.writes.map { write in
      guard case .usb(let packet, _) = write else { return write }
      return .usb(packet, toleratesRejection: true)
    }
  }

  /// Sends the startup writes in order, spaced by the startup interval of the plan, or by the delay
  /// that a write names for itself.
  ///
  /// A rejected write that tolerates rejection is logged and skipped.
  ///
  /// - Throws: ``CancellationError`` when the run or session changes, or the ``USBTransportError``
  ///   of a write that must succeed.
  func sendUSBStartupOutputPackets(
    handle: any USBTransportSession,
    runGeneration: UInt64? = nil
  ) async throws {
    let writes = usbStartupWrites()
    let interval = plan.usbStartupIntervalNanoseconds
    for (index, write) in writes.enumerated() {
      // A write that names its own delay waits that long, even first; the rest wait the interval.
      let wait =
        write.startupDelayMilliseconds.map {
          UInt64($0) * DeviceTransportProfile.nanosecondsPerMillisecond
        } ?? (index > 0 ? interval : 0)
      if wait > 0 {
        try await Task.sleep(nanoseconds: wait)
        guard isCurrentUSBOperation(runGeneration) else { throw CancellationError() }
      }
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
    }
  }

  /// Opens `device`, retrying after the open waits of the recovery policy.
  ///
  /// An access denial or an exclusive owner ends the retries at once.
  ///
  /// - Returns: The opened session, or the last error.
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
        if case .ownedByAnotherClient = error { return .unavailable(error) }
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

  /// Logs the failed open attempt `attempt`, counted from zero.
  func handleOpenDeviceError(_ error: Error, attempt: Int) {
    print("[DevicePipeline] Open attempt \(attempt + 1) failed" + " for \(identifier): \(error)")
  }
}
