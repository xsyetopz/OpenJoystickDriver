import Foundation

extension DeviceManager {
  func handleHIDDeviceConnected(connection: HIDDeviceConnection, ownership: HIDInputOwnership) async
  {
    let physicalDevice = connection.physicalDevice
    let routingLocationID = connection.routingLocationID
    guard !Task.isCancelled, !isStopping else { return }
    guard let vendorID = physicalDevice.vendorID else {
      print(
        "[DeviceManager] Skipping HID device without an observed vendor ID"
          + " at route loc=\(routingLocationID)"
      )
      return
    }
    guard let productID = physicalDevice.productID else {
      print(
        "[DeviceManager] Skipping HID device without an observed product ID"
          + " at route loc=\(routingLocationID)"
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
    } else if hasNativeHIDDevice(atLocation: routingLocationID) {
      guard isCurrentHIDInitialization(connection) else { return }
      recordPassThroughDevice(connection, vendorID: vendorID, productID: productID)
      _ = await hidManager.releaseInputClaim(locationID: routingLocationID)
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
        await updateHIDOwnership(ownership, locationID: routingLocationID)
        return
      }
      if case .hid = existingInfo.discoverySource {
        guard existingInfo.hidConnectionID != connection.connectionID else {
          await updateHIDOwnership(ownership, locationID: routingLocationID)
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
    let classification = protocolDriverRegistry.classify(physicalDevice, backend: .ioHID)
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
        identifier: identifier,
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
      vendorID: identifier.controllerIdentity.vendorID,
      productID: identifier.controllerIdentity.productID
    )
    deviceInfos[identifier] = DeviceInfo(
      name: name,
      connection: connectionName,
      serialNumber: identifier.controllerIdentity.serialNumber,
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
    await updateHIDOwnership(ownership, locationID: routingLocationID)
    guard !Task.isCancelled, deviceInfos[identifier]?.hidConnectionID == connection.connectionID,
      pipelines[identifier] == nil
    else { return }
    print("[DeviceManager] HID device connected:" + " \(name) (\(identifier))")
    let plan = driver.sessionPlan
    let pipeline = DevicePipeline(
      identifier: identifier,
      transport: .hid(locationID: routingLocationID),
      driver: driver,
      dispatcher: dispatcher,
      binding: binding,
      interface: physicalDevice.interfaces?.first,
      macOSOwnedOutput: physicalDevice.nativePassThrough
        ? MacOSOwnedOutput.allowance(for: binding.protocolID, record: binding.record) : nil,
      usbTransportProvider: usbTransportProvider,
      externalOutputAllowed: false,
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
    notifyControllerInventoryChanged()
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
        await dispatcher.activateOutput(for: identifier)
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
      guard startupOutputSucceeded else {
        print("[DeviceManager] Required HID startup output failed for loc=\(routingLocationID)")
        return
      }
      await pipeline.setExternalOutputAllowed(externalOutputAllowed)
      guard await isCurrentHIDStartupPipeline(pipeline, connection: connection) else { return }
    }
    if !plan.requiresInputConnectionBeforeOutput {
      guard await isCurrentHIDStartupPipeline(pipeline, connection: connection) else { return }
      if await pipeline.controllerSessionState() == .active {
        await dispatcher.activateOutput(for: identifier)
      }
      guard await isCurrentHIDStartupPipeline(pipeline, connection: connection) else { return }
    }
    await requestHIDInputConnectionStatusIfNeeded(pipeline: pipeline, connection: connection)
    guard await isCurrentHIDStartupPipeline(pipeline, connection: connection) else { return }
    scheduleHIDPeriodicOutput(for: identifier, pipeline: pipeline, connection: connection)
  }

  func isCurrentHIDInitialization(_ connection: HIDDeviceConnection) -> Bool {
    guard !Task.isCancelled, !isStopping else { return false }
    guard let initialization = hidInitializationTasks[hidInitializationKey(for: connection)] else {
      return true
    }
    return initialization.connection.connectionID == connection.connectionID
  }

  func scheduleHIDPeriodicOutput(
    for identifier: DeviceIdentifier,
    pipeline: DevicePipeline,
    connection: HIDDeviceConnection
  ) {
    guard isCurrentHIDStartupConnection(pipeline, connection: connection) else { return }
    let locationID = connection.routingLocationID
    hidPeriodicOutputTasks.removeValue(forKey: identifier)?.cancel()
    hidPeriodicOutputTasks[identifier] = Task { [weak self] in
      guard let self else { return }
      while !Task.isCancelled {
        guard let keepAlive = await pipeline.hidKeepAlivePlan(), keepAlive.interval > 0 else {
          return
        }
        guard await self.isCurrentHIDStartupPipeline(pipeline, connection: connection) else {
          return
        }
        do { try await Task.sleep(nanoseconds: keepAlive.interval) } catch { return }
        guard !Task.isCancelled,
          await self.isCurrentHIDStartupPipeline(pipeline, connection: connection)
        else { return }
        if !(await self.sendHIDWrites(
          keepAlive.writes,
          locationID: locationID,
          identifier: identifier,
          pipeline: pipeline
        )) {
          print("[DeviceManager] HID periodic output failed for loc=\(locationID)")
        }
      }
    }
  }
}
