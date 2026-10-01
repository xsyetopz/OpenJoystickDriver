import Foundation

extension DevicePipeline {
  enum Transport {
    /// Vendor-specific interface owned by the selected Apple USB transport backend.
    case usb(device: USBTransportDevice)
    /// Class 0x03 via IOKit
    case hid(locationID: UInt32)
  }

  /// Start pipeline: open device, handshake, begin input loop. A stopped pipeline stays stopped:
  /// admission publishes it before starting it, so a detach can stop it first, and a later start
  /// would open a session no stop closes.
  func start() {
    guard !isActive, !hasStopped else { return }
    isActive = true
    if driver.sessionPlan.inputReportLivenessTimeoutNanoseconds != nil {
      inputHealthMonitoringStartedNanoseconds = uptimeNanoseconds()
    }
    startIdleMonitor()

    switch transport {
    case .usb(let device): startUSBRun(device: device)
    case .hid:
      // HID pipeline: data fed via feedHIDData(); no separate startup loop needed
      print("[DevicePipeline] HID pipeline ready" + " for \(identifier)")
    }
  }

  /// Stop pipeline and clean up resources.
  ///
  /// Only the first stop tears down: it reports ownership, neutralizes output and ends the
  /// controller. A repeated stop, such as an admission rollback that raced a detach, only keeps
  /// the pipeline inactive, so `controllerDidStop` never fires twice.
  func stop() async {
    isActive = false
    usbRunGeneration &+= 1
    guard !hasStopped else { return }
    hasStopped = true
    let task = runTask
    runTask = nil
    task?.cancel()
    // An adapter may be inside a non-cooperative platform open call before a session exists. The
    // inactive guard closes any handle returned later; only an established session is awaited here.
    let hasPendingUSBOwnershipReport = usbOwnershipReportsInFlight > 0
    let shouldAwaitRunTask = usbHandle != nil || hasPendingUSBOwnershipReport
    driver.expireStartupRecovery()
    let idleTask = idleMonitorTask
    idleMonitorTask = nil
    idleTask?.cancel()
    if case .usb = transport, !hasPendingUSBOwnershipReport {
      await reportUSBInputOwnership(.unknown)
    }
    let handle = usbHandle
    usbHandle = nil
    await neutralizeOutput()
    await closeUSBCommandSession()
    await notifyControllerDidStop()
    await handle?.close()
    driver.resetProtocolState()
    if shouldAwaitRunTask { await task?.value }
    if case .usb = transport, hasPendingUSBOwnershipReport {
      await reportUSBInputOwnership(.unknown)
    }
    await idleTask?.value
    print("[DevicePipeline] Stopped: \(identifier)")
  }

  func startUSBRun(device: USBTransportDevice) {
    guard isActive else { return }
    usbRunGeneration &+= 1
    let generation = usbRunGeneration
    runTask = Task { await self.startUSBPipeline(device: device, generation: generation) }
  }

  /// Feed HID input report data (called by DeviceManager for class 0x03 devices).
  @discardableResult
  func feedHIDData(_ data: Data) async -> [PhysicalOutputWrite] {
    guard isActive else { return [] }
    appendToPacketLog(bytes: Array(data), direction: .received)
    do {
      let receivedAt = uptimeNanoseconds()
      let event = try parseReport(data, receivedAt: receivedAt)
      let connectionWrites = await handleInputConnectionStateChangeIfNeeded()
      guard inputConnectionActive else { return connectionWrites }
      await handleParsedEvent(event, now: receivedAt)
      return connectionWrites
    } catch {
      print("[DevicePipeline] Parse error" + " for \(identifier): \(error)")
      return []
    }
  }

  /// Whether the native startup player indicator is due, true once. The caller asks after an
  /// input report, because a USB Sixaxis ignores the LED report until it streams input.
  func takeStartupPlayerIndicatorDue() -> Bool {
    guard startupPlayerIndicatorPending else { return false }
    startupPlayerIndicatorPending = false
    return true
  }

  func sessionPlan() -> DriverSessionPlan { driver.sessionPlan }

  func consumeFeatureReply(_ data: Data, request: PhysicalHIDFeatureReadRequest) -> Bool {
    guard isActive else { return false }
    return driver.consumeFeatureReply(data, request: request)
  }

  func hidStartupWrites() -> [PhysicalOutputWrite] {
    guard isActive else { return [] }
    return driver.startupWrites()
  }

  func hidStartupRecoveryWrites() -> [PhysicalOutputWrite] {
    guard isActive else { return [] }
    return driver.startupRecoveryWrites()
  }

  /// False for an observe-only pipeline, which never sends startup output.
  func requiresSuccessfulHIDStartupOutput() -> Bool {
    !observesOnly && driver.sessionPlan.requiresStartupOutput
  }

  func hidStartupFeatureReads() -> [PhysicalHIDFeatureReadRequest] {
    guard isActive else { return [] }
    return driver.startupFeatureReads()
  }

  func hidActivationWrites() -> [PhysicalOutputWrite] {
    guard isActive else { return [] }
    return driver.activationWrites()
  }

  func hidPresenceRequestWrite() -> PhysicalOutputWrite? { driver.presenceRequestWrite() }

  func expireHIDStartupRecovery() { driver.expireStartupRecovery() }

  /// Feed one descriptor-decoded value to the Generic HID fallback.
  func feedHIDElementValue(_ value: HIDElementValue) async {
    guard isActive, inputConnectionActive else { return }
    let receivedAt = uptimeNanoseconds()
    await handleParsedEvent(parseElementValue(value, receivedAt: receivedAt), now: receivedAt)
  }

  func requiresInputConnectionBeforeOutput() -> Bool {
    driver.sessionPlan.requiresInputConnectionBeforeOutput
  }

  func hidDeactivationWrites() -> [PhysicalOutputWrite] {
    if requiresInputConnectionBeforeOutput(), !inputConnectionActive { return [] }
    return driver.deactivationWrites()
  }

  func capabilities() -> ControllerCapabilities { driver.capabilities.normalized }

  /// For an observe-only pipeline, only what its native allowance names: macOS owns the rest.
  func physicalOutputCapabilities() -> PhysicalControllerOutputCapabilities {
    macOSOwnedOutput?.narrowing(driver.outputCapabilities) ?? driver.outputCapabilities
  }

  func supportsPhysicalRumble() -> Bool { physicalOutputCapabilities().supportsRumble }

  // MARK: - Input state and packet log

  /// The latest observed state with its link and power state as of now.
  func inputState() -> ControllerState {
    var state = currentInputState
    state.connection = currentConnectionState()
    return state
  }
  func controllerSessionState() -> ControllerSessionState { sessionState }
  /// Link and power state: transport and backend from the binding, presence from this session.
  ///
  /// The controller-side link comes from evidence only: a receiver variant, a cabled variant, a
  /// Bluetooth host link (the pad itself is the Bluetooth peer), or an observed physical link. A
  /// USB host link alone can be a vendor radio dongle, so it leaves the transport unknown.
  func connectionState(
    binding: ProtocolBinding,
    interface: PhysicalInterfaceSignature?
  ) -> ControllerConnectionState {
    let transport: PhysicalTransport? =
      switch binding.variant {
      case .receiver, .dongle: .proprietaryRadioReceiver
      case .usb, .wired, .gamepad: .usb
      case .bluetoothClassic: .bluetoothClassic
      case .bluetoothLE: .bluetoothLE
      case .enhancedHID, nil:
        switch interface?.hostTransport {
        case .bluetoothClassic, .bluetoothLE: interface?.hostTransport
        default: interface?.physicalTransport
        }
      }
    return ControllerConnectionState(
      transport: transport,
      backend: binding.accessBackend,
      isConnected: inputConnectionActive,
      power: currentPower ?? .unknown
    )
  }
  func startupCommandStatus() -> String? { startupOutputStatus }
  /// Returns captured packets and renews the capture lease; reading is what enables capture.
  func getPacketLog() -> [PacketLogEntry] {
    packetLog.armCapture()
    return packetLog.entries()
  }

  func inputHealth() -> ControllerInputHealth {
    let now = uptimeNanoseconds()
    let reference = lastLiveInputReportNanoseconds ?? inputHealthMonitoringStartedNanoseconds
    let age = reference.map { now &- $0 }
    let observationAge = lastObservedInputReportNanoseconds.map { now &- $0 }
    let state: ControllerInputHealthState
    if awaitingNeutralAfterLivenessLoss {
      state = .waitingForNeutral
    } else if let timeout = driver.sessionPlan.inputReportLivenessTimeoutNanoseconds, let age,
      age >= timeout
    {
      state = .stale
    } else {
      state = .healthy
    }
    let failureReason: ControllerInputHealthFailureReason?
    if state == .healthy {
      failureReason = nil
    } else if let timeout = driver.sessionPlan.inputReportLivenessTimeoutNanoseconds,
      let observationAge, observationAge < timeout
    {
      failureReason = .freshnessNotAdvancing
    } else {
      failureReason = .missingReports
    }
    return ControllerInputHealth(
      state: state,
      reportFormat: driver.latestInputReportFormat,
      lastReportAgeNanoseconds: age,
      failureReason: failureReason,
      recoveryCount: inputHealthRecoveryCount
    )
  }

  func setExternalOutputAllowed(_ allowed: Bool) async {
    let changed = externalOutputAllowed != allowed
    guard changed else { return }
    externalOutputAllowed = allowed

    if !allowed {
      waitingForExternalNeutral = false
      foregroundMask = nil
      await neutralizeOutput()
      print("[DevicePipeline] Output gated by foreground consumer: \(identifier)")
      return
    }

    let shouldWaitForNeutral = !currentInputState.isEffectivelyNeutral
    waitingForExternalNeutral = shouldWaitForNeutral
    foregroundMask = ForegroundInputMask(hiding: currentInputState)

    if shouldWaitForNeutral {
      print(
        "[DevicePipeline] Foreground gate lifted; suppressing hidden "
          + "non-neutral state: \(identifier)"
      )
    } else {
      print("[DevicePipeline] Output ungated by foreground consumer: \(identifier)")
    }
  }

  /// Called when controller teardown starts; later writes must come from the teardown scope.
  func acceptOnlyTeardownOutput() { acceptsOnlyTeardownOutput = true }
}
