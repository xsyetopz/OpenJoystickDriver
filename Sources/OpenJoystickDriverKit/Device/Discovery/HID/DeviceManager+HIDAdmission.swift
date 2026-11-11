import Foundation

extension DeviceManager {
  /// Admits one HID connection: binds it to a driver, starts its device pipeline and runs its
  /// startup output.
  ///
  /// A native pass-through connection binds observe-only and leaves every other interface at its
  /// location to macOS. A connection that no driver binds, or that a raw-USB pipeline of the same
  /// controller serves, is recorded as unbound. Every await checks that this initialization is
  /// still current, because a later connection can replace it.
  func handleHIDDeviceConnected(connection: HIDDeviceConnection, ownership: HIDInputOwnership) async
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
    // macOS serves a native controller: OJD binds only its native interface, observe-only, and
    // leaves every other HID interface at its location to macOS.
    if physicalDevice.nativePassThrough {
      await yieldRawUSBPipelines(toNative: identifier)
      await prepareNativeHIDLocation(connection)
    } else if hasNativeHIDDevice(at: routingAddress) {
      guard isCurrentHIDInitialization(connection) else { return }
      recordPassThroughDevice(connection, vendorID: vendorID, productID: productID)
      _ = await hidManager.releaseInputClaim(address: routingAddress)
      return
    }
    // A family's non-role interface carries no controller; its claim is held while a sibling
    // role is bound, through the unbound-claim reconciliation.
    guard role != .notARole else {
      await rejectHIDDevice(
        connection,
        identifier: identifier,
        reason: .interfaceContractMismatch,
        rejectedCandidates: []
      )
      return
    }

    if let existingPipeline = pipelines[identifier] {
      guard let existingInfo = deviceInfos[identifier] else {
        await updateHIDOwnership(ownership, address: routingAddress)
        return
      }
      if case .hid = existingInfo.discoverySource {
        guard existingInfo.hidConnectionID != connection.connectionID else {
          await updateHIDOwnership(ownership, address: routingAddress)
          return
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
          return
        }
        deviceInfos.removeValue(forKey: identifier)
        lastPhysicalHIDOutputNanoseconds.removeValue(forKey: identifier)
        await existingPipeline.stop()
        guard !Task.isCancelled, isCurrentHIDInitialization(connection),
          deviceInfos[identifier] == nil, pipelines[identifier] == nil
        else { return }
        if let existingOutputQueue {
          retireOutputQueue(for: identifier, expected: existingOutputQueue)
        }
        print("[DeviceManager] Replacing stale HID connection snapshot: \(identifier)")
      }
    }
    let connectionName = physicalDevice.transportProperty ?? "HID"
    let modeSelection = await selectedHIDMode(
      for: connection,
      device: physicalDevice,
      vendorID: vendorID,
      productID: productID
    )
    guard !Task.isCancelled, isCurrentHIDInitialization(connection) else { return }
    let classification = protocolDriverRegistry.classify(
      physicalDevice,
      backend: connection.accessBackend,
      modeID: modeSelection.modeID
    )
    let binding: ProtocolBinding
    let driver: any PhysicalProtocolDriver
    switch classification {
    case .unsupported(let reason, let rejected):
      await rejectHIDDevice(
        connection,
        identifier: identifier,
        reason: reason,
        rejectedCandidates: rejected.map { [$0] } ?? []
      )
      return
    case .conflict(let reason, let candidates):
      await rejectHIDDevice(
        connection,
        identifier: identifier,
        reason: reason,
        rejectedCandidates: candidates.map {
          ProtocolBindingResult.RejectedCandidate(protocolID: $0, reason: reason)
        }
      )
      return
    case .bound(let bound):
      // No row names an assembly policy yet (the vocabulary is empty), so each role is its own
      // logical controller; the first policy must assemble its roles here.
      if let policy = protocolDriverRegistry.assemblyPolicy(for: bound) { switch policy {} }
      let reportDescriptor = physicalDevice.interfaces?.first {
        $0.interfaceNumber == bound.interfaceNumber
      }?.hidLayout?.reportDescriptor
      switch protocolDriverRegistry.makeDriver(
        for: bound,
        model: identifier.model,
        claimed: nil,
        reportDescriptor: reportDescriptor
      ) {
      case .success(let resolved):
        binding = bound
        driver = resolved
      case .failure(let reason):
        await rejectHIDDevice(
          connection,
          identifier: identifier,
          reason: reason,
          rejectedCandidates: [
            ProtocolBindingResult.RejectedCandidate(
              protocolID: bound.protocolID,
              reason: reason,
              catalogRecordID: bound.record?.recordID
            )
          ]
        )
        return
      }
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
        reason: .ambiguousProtocolMatch,
        rejectedCandidates: [
          ProtocolBindingResult.RejectedCandidate(
            protocolID: binding.protocolID,
            reason: .ambiguousProtocolMatch,
            catalogRecordID: binding.record?.recordID
          )
        ]
      )
      return
    }
    clearUnboundDevice(.hid(connection.connectionID))

    let name = controllerDisplayName(
      productName: physicalDevice.productName,
      vendorID: identifier.model.vendorID,
      productID: identifier.model.productID
    )
    deviceInfos[identifier] = DeviceInfo(
      name: name,
      connection: connectionName,
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
      sessionState: suspendedControllerIdentities.contains(identifier) ? .suspended : .active
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
    guard let initialization = hidInitializationTasks[hidInitializationKey(for: connection)] else {
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
