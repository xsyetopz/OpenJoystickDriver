import Foundation

extension DevicePipeline {
  /// The route by which the pipeline reaches its controller.
  enum Transport {
    /// Vendor-specific interface owned by the selected Apple USB transport backend.
    case usb(device: USBTransportDevice)
    /// A class 0x03 HID connection, which the device manager feeds with reports.
    case hid(address: ControllerConnectionAddress)
  }

  /// Starts the USB run, or readies the HID route, of a pipeline that never stopped.
  ///
  /// A stopped pipeline stays stopped: admission publishes it before starting it, so a detach can
  /// stop it first, and a later start would open a session that no stop closes.
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

  /// Stops the pipeline and releases its resources.
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
    if let handle {
      await sendUSBPowerOffWrites(handle: handle)
      await sendUSBShutdownWrites(handle: handle)
    }
    await handle?.close()
    driver.resetProtocolState()
    if shouldAwaitRunTask { await task?.value }
    if case .usb = transport, hasPendingUSBOwnershipReport {
      await reportUSBInputOwnership(.unknown)
    }
    await idleTask?.value
    print("[DevicePipeline] Stopped: \(identifier)")
  }

  /// Starts the task of a new USB run for `device`; does nothing while the pipeline is inactive.
  func startUSBRun(device: USBTransportDevice) {
    guard isActive else { return }
    usbRunGeneration &+= 1
    let generation = usbRunGeneration
    runTask = Task { await self.startUSBPipeline(device: device, generation: generation) }
  }

  /// Feeds one HID input report to the pipeline, as the device manager does for a class 0x03
  /// controller.
  ///
  /// `laterReportQueued` tells that a later report of this controller already waits; an input that
  /// changes only analog controls is then left for that report to publish.
  ///
  /// - Returns: The HID writes that a change of the input connection asks for, then the writes
  ///   the driver deferred while it parsed (the Wii Remote's memory exchanges, IR setup included).
  @discardableResult
  func feedHIDData(_ data: Data, laterReportQueued: Bool = false) async -> [PhysicalOutputWrite] {
    guard isActive else { return [] }
    appendToPacketLog(bytes: Array(data), direction: .received)
    var connectionWrites: [PhysicalOutputWrite] = []
    driver.setPointerInputWanted(
      (dispatcher as? any PointerInputDemand)?.wantsPointerInput(from: identifier) == true
    )
    do {
      let receivedAt = uptimeNanoseconds()
      let event = try parseReport(data, receivedAt: receivedAt)
      connectionWrites =
        await handleInputConnectionStateChangeIfNeeded() + driver.drainPendingWrites()
      if inputConnectionActive {
        await handleParsedEvent(event, now: receivedAt, laterReportQueued: laterReportQueued)
      }
    } catch {
      print("[DevicePipeline] Parse error" + " for \(identifier): \(error)")
    }
    if !laterReportQueued { await dispatchCoalescedInput() }
    return connectionWrites
  }

  /// Whether the startup player indicator is due, true once.
  ///
  /// The caller asks after an input report, because a USB Sixaxis ignores the LED report until it
  /// streams input.
  func takeStartupPlayerIndicatorDue() -> Bool {
    guard startupPlayerIndicatorPending else { return false }
    startupPlayerIndicatorPending = false
    return true
  }

  /// The driver's session plan with the bound record's tuning applied.
  func sessionPlan() -> DriverSessionPlan { plan }

  /// Hands a feature read reply to the driver.
  ///
  /// - Returns: False when the pipeline is inactive or the driver rejects the reply.
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

  /// The startup recovery writes of the driver; none while the pipeline is inactive.
  func hidStartupRecoveryWrites() -> [PhysicalOutputWrite] {
    guard isActive else { return [] }
    return driver.startupRecoveryWrites()
  }

  /// False for an observe-only pipeline, which never sends startup output.
  func requiresSuccessfulHIDStartupOutput() -> Bool {
    !observesOnly && plan.requiresStartupOutput
  }

  /// The feature reads that the driver makes at startup; none while the pipeline is inactive.
  func hidStartupFeatureReads() -> [PhysicalHIDFeatureReadRequest] {
    guard isActive else { return [] }
    return driver.startupFeatureReads()
  }

  /// The activation writes of the driver; none while the pipeline is inactive.
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

  /// The HID startup writes of `phase` for the observed host transport.
  ///
  /// A record that carries HID startup writes replaces the family description's.
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

  /// The write that asks the controller whether its input connection is up; nil when the driver has
  /// none.
  func hidPresenceRequestWrite() -> PhysicalOutputWrite? { driver.presenceRequestWrite() }

  /// Ends the startup recovery of the driver.
  func expireHIDStartupRecovery() { driver.expireStartupRecovery() }

  /// Feeds one descriptor-decoded value to the Generic HID fallback.
  func feedHIDElementValue(_ value: HIDElementValue) async {
    guard isActive, inputConnectionActive else { return }
    let receivedAt = uptimeNanoseconds()
    await handleParsedEvent(parseElementValue(value, receivedAt: receivedAt), now: receivedAt)
  }

  /// Whether the session plan holds output until the input connection is up.
  func requiresInputConnectionBeforeOutput() -> Bool {
    plan.requiresInputConnectionBeforeOutput
  }

  /// The deactivation writes of the driver; none while the plan waits for an input connection that
  /// is not up.
  func hidDeactivationWrites() -> [PhysicalOutputWrite] {
    if requiresInputConnectionBeforeOutput(), !inputConnectionActive { return [] }
    return driver.deactivationWrites()
  }

  /// The capabilities of the controller as the driver reports them.
  func capabilities() -> ControllerCapabilities { driver.capabilities }

  /// For an observe-only pipeline, only what its native allowance names: macOS owns the rest.
  func physicalOutputCapabilities() -> PhysicalControllerOutputCapabilities {
    macOSOwnedOutput?.narrowing(driver.outputCapabilities) ?? driver.outputCapabilities
  }

  /// Whether the controller has a rumble output that OJD may drive.
  func supportsPhysicalRumble() -> Bool { physicalOutputCapabilities().supportsRumble }

  // MARK: - Input state and packet log

  /// The latest observed state with its link and power state as of now.
  func inputState() -> ControllerState {
    var state = currentInputState
    state.connection = currentConnectionState()
    return state
  }
  /// The state of the controller session.
  func controllerSessionState() -> ControllerSessionState { sessionState }
  /// The link and power state of the controller.
  ///
  /// The transport and backend come from `binding`, the presence from this session. The
  /// controller-side link comes from evidence only: a receiver variant, a cabled variant, a
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
      power: currentPower ?? .unknown,
      wiiRemote: currentWiiRemote
    )
  }
  /// The result of the latest startup output; nil before any.
  func startupCommandStatus() -> String? { startupOutputStatus }

  /// Whether a controller is attached: a receiver slot with none stays open for pairing only.
  func hasConnectedController() -> Bool { inputConnectionActive }

  /// Records `status` as the result of the startup output.
  func recordStartupOutputStatus(_ status: String) { startupOutputStatus = status }
  /// Returns captured packets and renews the capture lease; reading is what enables capture.
  func getPacketLog() -> [PacketLogEntry] {
    packetLog.armCapture()
    return packetLog.entries()
  }

  /// Announces a status change once the input reports are overdue, because the stale state of
  /// ``inputHealth()`` follows time and no event announces it.
  ///
  /// One watch runs at a time; a later report arms it again after it fires.
  func armStaleWatch() {
    guard staleWatchTask == nil, let timeout = plan.inputReportLivenessTimeoutNanoseconds else {
      return
    }
    staleWatchTask = Task { [weak self] in
      while !Task.isCancelled, let self {
        guard let due = await staleDeadline(timeout: timeout) else { break }
        let now = uptimeNanoseconds()
        if now >= due {
          await announceStale()
          break
        }
        try? await Task.sleep(nanoseconds: due &- now)
      }
    }
  }

  /// The uptime at which the input reports become overdue by `timeout`; nil when monitoring has not
  /// begun.
  private func staleDeadline(timeout: UInt64) -> UInt64? {
    (lastLiveInputReportNanoseconds ?? inputHealthMonitoringStartedNanoseconds).map {
      $0 &+ timeout
    }
  }

  /// Posts a service status change for the overdue input reports and clears the watch.
  private func announceStale() {
    staleWatchTask = nil
    NotificationCenter.postServiceStatusChanged(from: self)
  }

  /// The freshness and recovery state of the controller's input reports.
  ///
  /// A session that has read no input yet is awaiting input, and stale once the liveness timeout
  /// passes. A stale or waiting session has a failure reason that tells the likely cause: reports
  /// arrive but their freshness does not advance, the guide button was not pressed, or no reports
  /// arrive.
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
    } else if lastObservedInputReportNanoseconds == nil {
      state = .awaitingInput
    } else {
      state = .healthy
    }
    let failureReason: ControllerInputHealthFailureReason?
    if state == .healthy || state == .awaitingInput {
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

  /// Sets the foreground gate: closing it neutralizes the output, and opening it hides input held
  /// at that moment until the controller returns to neutral or changes it.
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

  /// Limits output to what the teardown scope writes once controller teardown starts.
  func acceptOnlyTeardownOutput() { acceptsOnlyTeardownOutput = true }
}
