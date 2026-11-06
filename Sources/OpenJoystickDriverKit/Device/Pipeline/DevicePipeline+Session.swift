import Foundation

extension DevicePipeline {
  /// Suspends the controller session: releases the output, drops the held input and tells the
  /// dispatcher that the controller stopped.
  ///
  /// - Returns: False when the pipeline is inactive or its session is not active.
  func suspendControllerSession() async -> Bool {
    guard isActive, sessionState == .active else { return false }
    sessionState = .suspended
    lastLiveInputReportNanoseconds = nil
    inputHealthMonitoringStartedNanoseconds = nil
    awaitingNeutralAfterLivenessLoss = false
    waitingForExternalNeutral = false
    await neutralizeOutput()
    currentInputState = .neutral
    foregroundMask = nil
    await notifyControllerDidStop()
    return true
  }

  /// Resumes a suspended session with neutral input and restarted liveness monitoring, then
  /// activates the output.
  ///
  /// - Returns: False when the pipeline is inactive or its session is not suspended.
  func resumeControllerSession() async -> Bool {
    guard isActive, sessionState == .suspended else { return false }
    currentInputState = .neutral
    foregroundMask = nil
    lastLiveInputReportNanoseconds = nil
    inputHealthMonitoringStartedNanoseconds = uptimeNanoseconds()
    armStaleWatch()
    awaitingNeutralAfterLivenessLoss = false
    sessionState = .active
    await activateOutput()
    return true
  }

  /// Starts the resumed session from a reset driver, so input the controller changed while the
  /// session was suspended is not replayed from before, then repeats USB startup output.
  func restartUSBStartupOutputForResume() async -> Bool {
    driver.resetProtocolState()
    guard case .usb = transport, let handle = usbHandle else { return true }
    return await performUSBHandshake(handle: handle)
  }

  /// Reads the power state of the driver into ``currentPower``.
  func snapshotPower() { currentPower = driver.power }

  /// Dispatches the exact neutral state, releasing every control, stick, trigger and touch at
  /// once, unless it was the last state dispatched.
  func neutralizeOutput() async {
    guard lastDispatchedState != .neutral else { return }
    lastDispatchedState = .neutral
    await dispatch(
      ControllerEvent(
        timestamp: MonotonicTimestamp(nanoseconds: uptimeNanoseconds()),
        state: .neutral
      )
    )
  }

  /// Tells a lifecycle listener the controller stopped; the listener then holds no state for it.
  func notifyControllerDidStop() async {
    if let listener = dispatcher as? any ControllerLifecycleListener {
      await listener.controllerDidStop(identifier)
    }
    lastDispatchedState = .neutral
  }

  /// Releases the output after the input reports went overdue, and keeps it released until a fresh
  /// neutral report arrives.
  ///
  /// Does nothing while the pipeline already waits for that report.
  func retireOutputAfterLivenessLoss() async {
    guard !awaitingNeutralAfterLivenessLoss else { return }
    currentInputState = .neutral
    await neutralizeOutput()
    livenessLossFollowedInput = lastLiveInputReportNanoseconds != nil
    awaitingNeutralAfterLivenessLoss = true
    await notifyControllerDidStop()
  }

  /// Handles a pending logical connection change.
  ///
  /// USB writes for it are performed here; the HID writes are returned for the caller to perform on
  /// the HID device.
  func handleInputConnectionStateChangeIfNeeded() async -> [PhysicalOutputWrite] {
    guard let state = driver.consumeInputConnectionStateChange() else { return [] }
    var hidWrites: [PhysicalOutputWrite] = []
    let slotWrites = state == .connected ? assignedPlayerIndicatorWrites() : []
    switch transport {
    case .hid: hidWrites = driver.inputConnectionWrites(for: state) + slotWrites
    case .usb:
      // A handle change stops the writes but not the state change, which is already consumed.
      guard let handle = usbHandle else { break }
      for write in driver.inputConnectionWrites(for: state) + slotWrites {
        guard usbHandle === handle else { break }
        do {
          try await performUSBWrite(write, handle: handle, runGeneration: usbRunGeneration)
        } catch {
          print("[DevicePipeline] USB lifecycle output failed for \(identifier): \(error)")
        }
      }
    }

    switch state {
    case .connected:
      guard !inputConnectionActive else { return [] }
      inputConnectionActive = true
      if sessionState == .active { await activateOutput() }
      print("[DevicePipeline] Input controller connected: \(identifier)")
      return hidWrites
    case .disconnected:
      await endInputConnection()
      return hidWrites
    }
  }

  /// Releases the logical controller: neutral output, then a stop for a connected one.
  func endInputConnection() async {
    currentInputState = .neutral
    foregroundMask = nil
    await neutralizeOutput()
    if inputConnectionActive { await notifyControllerDidStop() }
    inputConnectionActive = false
    waitingForExternalNeutral = false
    print("[DevicePipeline] Input controller disconnected: \(identifier)")
  }

  /// Appends `bytes` to the packet log in `direction`.
  func appendToPacketLog(bytes: [UInt8], direction: PacketLogDirection) {
    packetLog.append(bytes: bytes, direction: direction)
  }

  /// Performs one driver-produced write on the USB session.
  func performUSBWrite(
    _ write: PhysicalOutputWrite,
    handle: any USBTransportSession,
    runGeneration: UInt64?
  ) async throws {
    switch write {
    case .usb(let packet, _):
      _ = try await writeUSBPacket(
        handle: handle,
        endpoint: packet.endpoint,
        data: packet.bytes,
        timeout: packet.timeoutMilliseconds,
        runGeneration: runGeneration
      )
    case .hidOutput, .hidFeature: throw USBTransportError.notSupported
    }
  }

  /// Writes one packet through ``usbOutputWriteQueue`` and returns the number of bytes written.
  ///
  /// - Throws: ``CancellationError`` when the session or run changed, or the error of the transport
  ///   write.
  func writeUSBPacket(
    handle: any USBTransportSession,
    endpoint: UInt8,
    data: [UInt8],
    timeout: UInt32,
    runGeneration: UInt64? = nil
  ) async throws -> Int {
    try await usbOutputWriteQueue.perform { [weak self] in
      guard let self else { throw CancellationError() }
      return try await self.writeUSBPacketInQueue(
        handle: handle,
        endpoint: endpoint,
        data: data,
        timeout: timeout,
        runGeneration: runGeneration
      )
    }
  }

  /// The write itself, for a caller already running inside ``usbOutputWriteQueue``.
  func writeUSBPacketInQueue(
    handle: any USBTransportSession,
    endpoint: UInt8,
    data: [UInt8],
    timeout: UInt32,
    runGeneration: UInt64?
  ) async throws -> Int {
    guard isCurrentUSBWrite(handle: handle, runGeneration: runGeneration) else {
      throw CancellationError()
    }
    let written = try await handle.write(endpoint: endpoint, data: data, timeout: timeout)
    appendToPacketLog(bytes: data, direction: .transmitted)
    guard isCurrentUSBWrite(handle: handle, runGeneration: runGeneration) else {
      throw CancellationError()
    }
    return written
  }

  /// Whether a write on `handle` may still go out: the pipeline is active, `handle` is the current
  /// session, the teardown rule allows the write, and `runGeneration`, when given, is the current
  /// run.
  func isCurrentUSBWrite(handle: any USBTransportSession, runGeneration: UInt64?) -> Bool {
    guard isActive, usbHandle === handle,
      !acceptsOnlyTeardownOutput || ControllerTeardownOutput.isActive
    else { return false }
    if let runGeneration, usbRunGeneration != runGeneration { return false }
    return true
  }
}

extension DevicePipeline {
  /// Parses one report and records the power state it left behind, even for a non-input frame.
  func parseReport(_ data: Data, receivedAt: UInt64) throws -> ControllerEvent? {
    let event = try driver.parse(
      report: data,
      receivedAt: MonotonicTimestamp(nanoseconds: receivedAt)
    )
    snapshotPower()
    if event != nil {
      frameTimings.parsed(for: identifier, read: receivedAt, parse: uptimeNanoseconds())
    }
    return event
  }

  /// Parses one descriptor-decoded HID element value into an event; nil when it carries no input.
  func parseElementValue(_ value: HIDElementValue, receivedAt: UInt64) -> ControllerEvent? {
    let event = driver.parse(
      elementValue: value,
      receivedAt: MonotonicTimestamp(nanoseconds: receivedAt)
    )
    if event != nil {
      frameTimings.parsed(for: identifier, read: receivedAt, parse: uptimeNanoseconds())
    }
    return event
  }
}
