import Foundation

extension DevicePipeline {
  enum Transport {
    /// Vendor-specific interface owned by the selected Apple USB transport backend.
    case usb(device: USBTransportDevice)
    /// Class 0x03 via IOKit
    case hid(address: ControllerConnectionAddress)
  }

  /// Start pipeline: open device, handshake, begin input loop. A stopped pipeline stays stopped:
  /// admission publishes it before starting it, so a detach can stop it first, and a later start
  /// would open a session no stop closes.
  func start() {
    guard !isActive, !hasStopped else { return }
    isActive = true
    if plan.inputReportLivenessTimeoutNanoseconds != nil {
      inputHealthMonitoringStartedNanoseconds = uptimeNanoseconds()
      armStaleWatch()
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
    frameTimings.forget(identifier)
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
    staleWatchTask?.cancel()
    staleWatchTask = nil
    if case .usb = transport, !hasPendingUSBOwnershipReport {
      await reportUSBInputOwnership(.unknown)
    }
    let handle = usbHandle
    usbHandle = nil
    await neutralizeOutput()
    await closeUSBCommandSession()
    await notifyControllerDidStop()
    if let handle { await sendUSBShutdownWrites(handle: handle) }
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
  ///
  /// `laterReportQueued` tells that a later report of this controller already waits; an input
  /// that changes only analog controls is then left for that report to publish.
  @discardableResult
  func feedHIDData(_ data: Data, laterReportQueued: Bool = false) async -> [PhysicalOutputWrite] {
    guard isActive else { return [] }
    appendToPacketLog(bytes: Array(data), direction: .received)
    var connectionWrites: [PhysicalOutputWrite] = []
    do {
      let receivedAt = uptimeNanoseconds()
      let event = try parseReport(data, receivedAt: receivedAt)
      connectionWrites = await handleInputConnectionStateChangeIfNeeded()
      if inputConnectionActive {
        await handleParsedEvent(event, now: receivedAt, laterReportQueued: laterReportQueued)
      }
    } catch {
      print("[DevicePipeline] Parse error" + " for \(identifier): \(error)")
    }
    if !laterReportQueued { await dispatchCoalescedInput() }
    return connectionWrites
  }

  /// Whether the startup player indicator is due, true once. The caller asks after an input
  /// report, because a USB Sixaxis ignores the LED report until it streams input.
  func takeStartupPlayerIndicatorDue() -> Bool {
    guard startupPlayerIndicatorPending else { return false }
    startupPlayerIndicatorPending = false
    return true
  }

  func sessionPlan() -> DriverSessionPlan { plan }

  func consumeFeatureReply(_ data: Data, request: PhysicalHIDFeatureReadRequest) -> Bool {
    guard isActive else { return false }
    return driver.consumeFeatureReply(data, request: request)
  }

  /// The startup-phase writes of the record or the family's description, then the driver's own
  /// startup writes: the ones that depend on state only the driver holds.
  func hidStartupWrites() -> [PhysicalOutputWrite] {
    guard isActive else { return [] }
    let slot =
      plan.requiresInputConnectionBeforeOutput || plan.hidPlayerIndicatorFollowsFirstInput
      ? [] : assignedPlayerIndicatorWrites()
    return resolvedStartupWrites(phase: .startup) + driver.startupWrites() + slot
  }

  func hidStartupRecoveryWrites() -> [PhysicalOutputWrite] {
    guard isActive else { return [] }
    return driver.startupRecoveryWrites()
  }

  /// False for an observe-only pipeline, which never sends startup output.
  func requiresSuccessfulHIDStartupOutput() -> Bool {
    !observesOnly && plan.requiresStartupOutput
  }

  func hidStartupFeatureReads() -> [PhysicalHIDFeatureReadRequest] {
    guard isActive else { return [] }
    return driver.startupFeatureReads()
  }

  func hidActivationWrites() -> [PhysicalOutputWrite] {
    guard isActive else { return [] }
    return driver.activationWrites()
  }

  /// The activation-phase startup writes of the record or the family's description; none for an
  /// observe-only pipeline, which macOS starts.
  func activationStartupWrites() -> [PhysicalOutputWrite] {
    guard isActive, !observesOnly else { return [] }
    return resolvedStartupWrites(phase: .activation)
  }

  /// The HID startup writes of `phase` for the observed host transport. A record that carries
  /// HID startup writes replaces the family description's.
  func resolvedStartupWrites(phase: StartupPhase) -> [PhysicalOutputWrite] {
    guard let binding else { return [] }
    let recordWrites = binding.record?.startupWrites ?? []
    let writes =
      recordWrites.isEmpty
      ? binding.protocolID.protocolDescription.startupWrites(
        phase: phase,
        variant: binding.variant,
        parameters: binding.record?.parameters ?? .none
      )
      : recordWrites.filter { $0.phase == phase }
    return writes.filter { $0.applies(to: interface?.hostTransport) }.map(\.write)
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
    plan.requiresInputConnectionBeforeOutput
  }

  func hasConnectedController() -> Bool { inputConnectionActive }

  func hidDeactivationWrites() -> [PhysicalOutputWrite] {
    if requiresInputConnectionBeforeOutput(), !inputConnectionActive { return [] }
    return driver.deactivationWrites()
  }

  func capabilities() -> ControllerCapabilities { driver.capabilities }

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

  func recordStartupOutputStatus(_ status: String) { startupOutputStatus = status }
  /// Returns captured packets and renews the capture lease; reading is what enables capture.
  func getPacketLog() -> [PacketLogEntry] {
    packetLog.armCapture()
    return packetLog.entries()
  }

  /// Announces a status change once the input reports are overdue, because the stale state of
  /// ``inputHealth()`` follows time and no event announces it. One watch runs at a time; a later
  /// report arms it again after it fires.
  func armStaleWatch() {
    guard staleWatchTask == nil, let timeout = plan.inputReportLivenessTimeoutNanoseconds else {
      return
    }
    staleWatchTask = Task { [weak self] in
      while !Task.isCancelled, let self {
        guard let due = await self.staleDeadline(timeout: timeout) else { break }
        let now = self.uptimeNanoseconds()
        if now >= due {
          await self.announceStale()
          break
        }
        try? await Task.sleep(nanoseconds: due &- now)
      }
    }
  }

  private func staleDeadline(timeout: UInt64) -> UInt64? {
    (lastLiveInputReportNanoseconds ?? inputHealthMonitoringStartedNanoseconds).map {
      $0 &+ timeout
    }
  }

  private func announceStale() {
    staleWatchTask = nil
    NotificationCenter.postServiceStatusChanged(from: self)
  }

  func inputHealth() -> ControllerInputHealth {
    let now = uptimeNanoseconds()
    let reference = lastLiveInputReportNanoseconds ?? inputHealthMonitoringStartedNanoseconds
    let age = reference.map { now &- $0 }
    let observationAge = lastObservedInputReportNanoseconds.map { now &- $0 }
    let state: ControllerInputHealthState
    // A session with no input yet has nothing to return to neutral from: it is stale.
    if awaitingNeutralAfterLivenessLoss, lastLiveInputReportNanoseconds != nil {
      state = .waitingForNeutral
    } else if let timeout = plan.inputReportLivenessTimeoutNanoseconds, let age,
      age >= timeout
    {
      state = .stale
    } else {
      state = .healthy
    }
    let failureReason: ControllerInputHealthFailureReason?
    if state == .healthy {
      failureReason = nil
    } else if let timeout = plan.inputReportLivenessTimeoutNanoseconds,
      let observationAge, observationAge < timeout
    {
      failureReason = .freshnessNotAdvancing
    } else if lastLiveInputReportNanoseconds == nil, plan.inputStartAction == .pressGuide {
      failureReason = .guideNotPressed
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
