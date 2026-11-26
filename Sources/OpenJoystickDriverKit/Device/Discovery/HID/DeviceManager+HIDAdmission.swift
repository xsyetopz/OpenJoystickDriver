import Foundation

extension DeviceManager {
  /// Admits one HID connection: binds it to a driver, starts its device pipeline and runs its
  /// startup output.
  ///
  /// A native pass-through connection binds observe-only and leaves every other interface at its
  /// location to macOS. A connection that no driver binds, or that a raw-USB pipeline of the same
  /// controller serves, is recorded as unbound. Every await checks that this initialization is
  /// still current, because a later connection can replace it.
  ///
  /// A controller whose user suspended it is left with its HID handles closed until
  /// ``resumeController(_:)``, however the HID backend opened the connection.
  func handleHIDDeviceConnected(connection: HIDDeviceConnection, ownership: HIDInputOwnership) async
  {
    await admitHIDConnection(connection: connection, ownership: ownership)
    let suspended = deviceInfos.contains {
      $0.value.hidConnectionID == connection.connectionID
        && suspendedControllerIdentities.contains($0.key)
    }
    if suspended { _ = await hidManager.closeDeviceHandles(address: connection.routingAddress) }
  }

  /// Binds and starts `connection`, leaving the handles of a suspended controller as they are.
  private func admitHIDConnection(
    connection: HIDDeviceConnection,
    ownership: HIDInputOwnership
  )
    async
  {
    let physicalDevice = connection.physicalDevice
    let routingAddress = connection.routingAddress
    guard !Task.isCancelled, !isStopping else { return }
    guard let vendorID = physicalDevice.vendorID else {
      print(
        "[DeviceManager] Skipping HID device without an observed vendor ID"
          + " at route route=\(routingAddress)"
      )
      return
    }
    guard let productID = physicalDevice.productID else {
      print(
        "[DeviceManager] Skipping HID device without an observed product ID"
          + " at route route=\(routingAddress)"
      )
      return
    }
    let role = protocolDriverRegistry.hidConnectionRole(of: physicalDevice)
    guard let identifier = hidIdentifier(for: connection, role: role) else { return }
    // An adapter's ports are keyed by location and port, so one without a location cannot tell
    // them apart and fails closed.
    if case .ports = role, routingAddress.locationID == nil {
      await rejectHIDDevice(
        connection,
        identifier: identifier,
        reason: .interfaceContractMismatch,
        rejectedCandidates: []
      )
      return
    }
    // macOS serves a native controller: OJD binds only its native interface, observe-only, and
    // leaves every other HID interface at its location to macOS.
    if physicalDevice.nativePassThrough {
      await yieldRawUSBPipelines(toNative: identifier)
      await prepareNativeHIDLocation(connection)
    } else {
      // A native holder that this connection re-enumerated is gone, not a sibling to leave alone.
      if hasNativeHIDDevice(at: routingAddress) {
        await retireSupersededHIDConnections(by: connection)
      }
      if hasNativeHIDDevice(at: routingAddress) {
        guard isCurrentHIDInitialization(connection) else { return }
        recordPassThroughDevice(connection, vendorID: vendorID, productID: productID)
        _ = await hidManager.releaseInputClaim(address: routingAddress)
        return
      }
    }
    // A family's non-role interface carries no controller; its claim is held while a sibling
    // role is bound, through the unbound-claim reconciliation.
    guard role != .notRole else {
      await rejectHIDDevice(
        connection,
        identifier: identifier,
        reason: .interfaceContractMismatch,
        rejectedCandidates: []
      )
      return
    }
    guard case .ports(let count) = role else {
      await admitHIDController(identifier, connection: connection, ownership: ownership, role: role)
      return
    }
    // One rumble report drives every port's motor, so the ports share one bank.
    let rumbleBank = GameCubeAdapterRumbleBank()
    for port in 0..<count {
      guard isCurrentHIDInitialization(connection),
        let portIdentifier = hidIdentifier(for: connection, role: role, port: UInt8(port))
      else { return }
      await admitHIDController(
        portIdentifier,
        connection: connection,
        ownership: ownership,
        role: role,
        port: port,
        rumbleBank: rumbleBank
      )
    }
  }

  /// Binds and starts one logical controller of `connection`: the connection's own controller,
  /// one HID role, or adapter port `port`, whose driver shares `rumbleBank` with its siblings.
  private func admitHIDController(
    _ identifier: LogicalControllerID,
    connection: HIDDeviceConnection,
    ownership: HIDInputOwnership,
    role: HIDConnectionRole,
    port: Int = 0,
    rumbleBank: GameCubeAdapterRumbleBank? = nil
  ) async {
    let physicalDevice = connection.physicalDevice
    let routingAddress = connection.routingAddress
    guard physicalDevice.vendorID != nil, physicalDevice.productID != nil else { return }
    guard
      await retireStaleHIDPipeline(for: identifier, connection: connection, ownership: ownership)
    else { return }
    guard
      let resolved = await resolveHIDDriver(
        for: identifier,
        connection: connection,
        port: port,
        rumbleBank: rumbleBank
      )
    else { return }
    let (binding, driver) = resolved
    clearUnboundDevice(.hid(connection.connectionID))

    let name = controllerDisplayName(
      productName: physicalDevice.productName,
      vendorID: identifier.model.vendorID,
      productID: identifier.model.productID
    )
    deviceInfos[identifier] = DeviceInfo(
      name: name,
      connection: physicalDevice.transportProperty ?? "HID",
      serialNumber: identifier.hardware.serialNumber,
      discoverySource: .hid,
      binding: binding,
      hidInputOwnership: ownership,
      physicalDevice: physicalDevice,
      hidConnectionID: connection.connectionID
    )
    if case .interface = role { hidRoleConnections[connection.connectionID] = identifier }
    guard !Task.isCancelled else {
      deviceInfos.removeValue(forKey: identifier)
      return
    }
    await updateHIDOwnership(ownership, address: routingAddress)
    guard !Task.isCancelled, deviceInfos[identifier]?.hidConnectionID == connection.connectionID,
      pipelines[identifier] == nil
    else { return }
    print("[DeviceManager] HID device connected:" + " \(name) (\(identifier))")
    let plan = driver.sessionPlan
    let pipeline = DevicePipeline(
      identifier: identifier,
      transport: .hid(address: routingAddress),
      driver: driver,
      dispatcher: dispatcher,
      binding: binding,
      interface: physicalDevice.interfaces?.first,
      macOSOwnedOutput: physicalDevice.nativePassThrough
        ? MacOSOwnedOutput.allowance(for: binding.protocolID, record: binding.record) : nil,
      startupPlayerIndicator: plan.assignsStartupPlayerIndicator
        && !physicalDevice.nativePassThrough
        ? claimStartupPlayerSlot(for: identifier) : nil,
      usbTransportProvider: usbTransportProvider,
      externalOutputAllowed: false,
      frameTimings: frameTimings,
      sessionState: suspendedControllerIdentities.contains(identifier) ? .suspended : .active,
      unit: ControllerPortKey.of(identifier, installationKey: installationKey)
    )
    let requiresSuccessfulStartupOutput = await pipeline.requiresSuccessfulHIDStartupOutput()
    if !requiresSuccessfulStartupOutput {
      await pipeline.setExternalOutputAllowed(externalOutputAllowed)
    }
    guard !Task.isCancelled, !isStopping, isCurrentHIDInitialization(connection),
      deviceInfos[identifier]?.hidConnectionID == connection.connectionID,
      deviceInfos[identifier]?.physicalDevice == physicalDevice, pipelines[identifier] == nil
    else { return }
    pipelines[identifier] = pipeline
    notifyServiceStatusChanged()
    guard ownership != .ownedByAnotherClient else { return }
    await runHIDStartup(
      pipeline,
      for: identifier,
      connection: connection,
      plan: plan,
      requiresSuccessfulStartupOutput: requiresSuccessfulStartupOutput
    )
  }

  /// Stops the pipeline of an earlier HID connection that `identifier` still names, so
  /// `connection` can replace it.
  ///
  /// Returns `false` when admission ends here: `connection` already runs `identifier` (its
  /// ownership is updated instead), the snapshot has no device info, or a later change superseded
  /// this initialization while the stale pipeline stopped. A raw-USB pipeline is left running.
  private func retireStaleHIDPipeline(
    for identifier: LogicalControllerID,
    connection: HIDDeviceConnection,
    ownership: HIDInputOwnership
  ) async -> Bool {
    guard let existingPipeline = pipelines[identifier] else { return true }
    guard let existingInfo = deviceInfos[identifier] else {
      await updateHIDOwnership(ownership, address: connection.routingAddress)
      return false
    }
    guard case .hid = existingInfo.discoverySource else { return true }
    guard existingInfo.hidConnectionID != connection.connectionID else {
      await updateHIDOwnership(ownership, address: connection.routingAddress)
      return false
    }
    let existingOutputQueue = hidOutputQueues[identifier]
    pipelines.removeValue(forKey: identifier)
    hidPeriodicOutputTasks.removeValue(forKey: identifier)?.cancel()
    // The stale connection's pending output is dropped; its neutralization queues after.
    existingOutputQueue?.cancelAll()
    await neutralizePhysicalOutputs(
      for: identifier,
      pipeline: existingPipeline,
      detachedInfo: existingInfo
    )
    guard isCurrentHIDInitialization(connection),
      deviceInfos[identifier]?.hidConnectionID == existingInfo.hidConnectionID,
      deviceInfos[identifier]?.physicalDevice == existingInfo.physicalDevice,
      pipelines[identifier] == nil
    else {
      await existingPipeline.stop()
      return false
    }
    deviceInfos.removeValue(forKey: identifier)
    lastPhysicalHIDOutputNanoseconds.removeValue(forKey: identifier)
    await existingPipeline.stop()
    guard !Task.isCancelled, isCurrentHIDInitialization(connection),
      deviceInfos[identifier] == nil, pipelines[identifier] == nil
    else { return false }
    if let existingOutputQueue {
      retireOutputQueue(for: identifier, expected: existingOutputQueue)
    }
    print("[DeviceManager] Replacing stale HID connection snapshot: \(identifier)")
    return true
  }

  /// Classifies `connection` in its selected mode and makes the driver of its binding.
  ///
  /// Returns `nil` after recording `connection` as unbound when no driver binds it, candidates
  /// conflict, the driver cannot be made, or a raw-USB pipeline already serves the same controller,
  /// and also when a later initialization supersedes this one.
  private func resolveHIDDriver(
    for identifier: LogicalControllerID,
    connection: HIDDeviceConnection,
    port: Int,
    rumbleBank: GameCubeAdapterRumbleBank?
  ) async -> sending (ProtocolBinding, any PhysicalProtocolDriver)? {
    let physicalDevice = connection.physicalDevice
    guard let vendorID = physicalDevice.vendorID, let productID = physicalDevice.productID else {
      return nil
    }
    let modeSelection = await selectedHIDMode(
      for: connection,
      device: physicalDevice,
      vendorID: vendorID,
      productID: productID
    )
    guard !Task.isCancelled, isCurrentHIDInitialization(connection) else { return nil }
    let bound: ProtocolBinding
    switch protocolDriverRegistry.classify(
      physicalDevice,
      backend: connection.accessBackend,
      modeID: modeSelection.modeID
    ) {
    case .unsupported(let reason, let rejected):
      await rejectHIDDevice(
        connection,
        identifier: identifier,
        reason: reason,
        rejectedCandidates: rejected.map { [$0] } ?? []
      )
      return nil
    case .conflict(let reason, let candidates):
      await rejectHIDDevice(
        connection,
        identifier: identifier,
        reason: reason,
        rejectedCandidates: candidates.map {
          ProtocolBindingResult.RejectedCandidate(protocolID: $0, reason: reason)
        }
      )
      return nil
    case .bound(let binding):
      bound = binding
    }
    // No row names an assembly policy yet (the vocabulary is empty), so each role is its own
    // logical controller; the first policy must assemble its roles here.
    if let policy = protocolDriverRegistry.assemblyPolicy(for: bound) { switch policy {} }
    let reportDescriptor = physicalDevice.interfaces?.first {
      $0.interfaceNumber == bound.interfaceNumber
    }?.hidLayout?.reportDescriptor
    let driver: any PhysicalProtocolDriver
    switch protocolDriverRegistry.makeDriver(
      for: bound,
      model: identifier.model,
      claimed: nil,
      slotOrdinal: port,
      reportDescriptor: reportDescriptor,
      adapterRumbleBank: rumbleBank
    ) {
    case .success(let resolved):
      driver = resolved
    case .failure(let reason):
      await rejectHIDDevice(connection, identifier: identifier, binding: bound, reason: reason)
      return nil
    }
    // A HID interface of a controller that a raw-USB pipeline already serves would expose it twice.
    // The rejected connection's claim stays held while that pipeline runs. Only this HID-side
    // family is rejected; the raw-USB family stays bound on its own pipeline.
    if let rawUSBIdentifier = rawUSBIdentifier(servingSameControllerAs: identifier),
      deviceInfos[rawUSBIdentifier] != nil
    {
      await rejectHIDDevice(
        connection,
        identifier: identifier,
        binding: bound,
        reason: .ambiguousProtocolMatch
      )
      return nil
    }
    return (bound, driver)
  }

  /// Records `connection` as unbound because its one candidate `binding` was refused for `reason`.
  private func rejectHIDDevice(
    _ connection: HIDDeviceConnection,
    identifier: LogicalControllerID,
    binding: ProtocolBinding,
    reason: ProtocolBindingReason
  ) async {
    await rejectHIDDevice(
      connection,
      identifier: identifier,
      reason: reason,
      rejectedCandidates: [
        ProtocolBindingResult.RejectedCandidate(
          protocolID: binding.protocolID,
          reason: reason,
          catalogRecordID: binding.record?.recordID
        )
      ]
    )
  }

  /// Runs the startup of a registered HID `pipeline` in the order its session `plan` gives:
  /// element routing, unbound-claim reconciliation, startup output, feature reads, activation
  /// writes, output activation, the input-connection request, then periodic output.
  ///
  /// A native pass-through pipeline gets only the feature reads its allowance names, output
  /// activation, and the rumble keep-alive its record resends. Each step stops the startup once
  /// `pipeline` is no longer the current startup pipeline of `connection`. With
  /// `requiresSuccessfulStartupOutput`, external output is allowed only after startup output
  /// succeeded.
  private func runHIDStartup(
    _ pipeline: DevicePipeline,
    for identifier: LogicalControllerID,
    connection: HIDDeviceConnection,
    plan: DriverSessionPlan,
    requiresSuccessfulStartupOutput: Bool
  ) async {
    await pipeline.start()
    guard await isCurrentHIDStartupPipeline(pipeline, connection: connection) else { return }
    if plan.parsesHIDElementValues { await hidManager.routeElementValues(connection: connection) }
    guard await isCurrentHIDStartupPipeline(pipeline, connection: connection) else { return }
    await reconcileUnboundHIDClaims()
    guard await isCurrentHIDStartupPipeline(pipeline, connection: connection) else { return }
    // macOS initializes a native controller; OJD sends it no startup, status or periodic output
    // beyond its allowance, and makes feature reads only where the allowance says macOS does not.
    // Its startup player indicator follows its first input report (`routeHIDInputReport`).
    if pipeline.macOSOwnedOutput?.readsStartupFeatures == true {
      await sendHIDStartupFeatureReadRequestsIfNeeded(pipeline: pipeline, connection: connection)
      guard await isCurrentHIDStartupPipeline(pipeline, connection: connection) else { return }
    }
    guard !pipeline.observesOnly else {
      if await pipeline.controllerSessionState() == .active,
        !(await pipeline.requiresInputConnectionBeforeOutput())
      {
        await pipeline.activateOutput()
      }
      // macOS runs the controller; OJD keeps alive only the rumble its record's template resends.
      if await pipeline.resendsRumble {
        scheduleHIDPeriodicOutput(for: identifier, pipeline: pipeline, connection: connection)
      }
      return
    }
    // Startup writes go before or after the feature reads; activation follows the reads unless
    // it waits for a logical controller to connect.
    var startupOutputSucceeded = true
    if plan.outputPrecedesFeatureReads {
      startupOutputSucceeded = await sendHIDStartupOutputReportsIfNeeded(
        pipeline: pipeline,
        connection: connection
      )
      guard await isCurrentHIDStartupPipeline(pipeline, connection: connection) else { return }
    }
    await sendHIDStartupFeatureReadRequestsIfNeeded(pipeline: pipeline, connection: connection)
    guard await isCurrentHIDStartupPipeline(pipeline, connection: connection) else { return }
    if !plan.requiresInputConnectionBeforeOutput {
      await sendHIDActivationWritesIfNeeded(pipeline: pipeline, connection: connection)
      guard await isCurrentHIDStartupPipeline(pipeline, connection: connection) else { return }
    }
    if !plan.outputPrecedesFeatureReads {
      startupOutputSucceeded = await sendHIDStartupOutputReportsIfNeeded(
        pipeline: pipeline,
        connection: connection
      )
      guard await isCurrentHIDStartupPipeline(pipeline, connection: connection) else { return }
    }
    if requiresSuccessfulStartupOutput {
      guard startupOutputSucceeded else { return }
      await pipeline.setExternalOutputAllowed(externalOutputAllowed)
      guard await isCurrentHIDStartupPipeline(pipeline, connection: connection) else { return }
    }
    if !plan.requiresInputConnectionBeforeOutput {
      guard await isCurrentHIDStartupPipeline(pipeline, connection: connection) else { return }
      if await pipeline.controllerSessionState() == .active {
        await pipeline.activateOutput()
      }
      guard await isCurrentHIDStartupPipeline(pipeline, connection: connection) else { return }
    }
    await requestHIDInputConnectionStatusIfNeeded(pipeline: pipeline, connection: connection)
    guard await isCurrentHIDStartupPipeline(pipeline, connection: connection) else { return }
    scheduleHIDPeriodicOutput(for: identifier, pipeline: pipeline, connection: connection)
  }

  /// Whether `connection` is still the initialization to finish: the manager is not stopping, the
  /// task is not cancelled, and no other connection holds its initialization key.
  func isCurrentHIDInitialization(_ connection: HIDDeviceConnection) -> Bool {
    guard !Task.isCancelled, !isStopping else { return false }
    // Every input report asks; with no initialization pending, the key's catalog lookup is skipped.
    guard !hidInitializationTasks.isEmpty,
      let initialization = hidInitializationTasks[hidInitializationKey(for: connection)]
    else {
      return true
    }
    return initialization.connection.connectionID == connection.connectionID
  }

  /// Repeats the keep-alive output of a HID controller at the interval of the pipeline until the
  /// pipeline or its connection is replaced.
  ///
  /// A failed write is logged. Does nothing when `connection` is not the startup connection of
  /// `pipeline`.
  func scheduleHIDPeriodicOutput(
    for identifier: LogicalControllerID,
    pipeline: DevicePipeline,
    connection: HIDDeviceConnection
  ) {
    guard isCurrentHIDStartupConnection(pipeline, connection: connection) else { return }
    let address = connection.routingAddress
    hidPeriodicOutputTasks.removeValue(forKey: identifier)?.cancel()
    hidPeriodicOutputTasks[identifier] = Task { [weak self] in
      guard let self else { return }
      while !Task.isCancelled {
        guard let interval = await pipeline.hidKeepAliveInterval(), interval > 0 else {
          return
        }
        guard await isCurrentHIDStartupPipeline(pipeline, connection: connection) else {
          return
        }
        do { try await Task.sleep(nanoseconds: interval) } catch { return }
        guard !Task.isCancelled,
          await isCurrentHIDStartupPipeline(pipeline, connection: connection)
        else { return }
        if !(await sendHIDKeepAlive(
          address: address,
          identifier: identifier,
          pipeline: pipeline
        )) {
          print("[DeviceManager] HID periodic output failed for route=\(address)")
        }
      }
    }
  }
}
