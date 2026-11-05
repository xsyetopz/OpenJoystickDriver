import Foundation

extension DeviceManager {

  func neutralizePhysicalOutputs(
    for identifier: LogicalControllerID,
    pipeline: DevicePipeline,
    detachedInfo: DeviceInfo? = nil
  ) async {
    rumbleStopTasks.removeValue(forKey: identifier)?.cancel()
    rumbleStopTokens.remove(identifier)
    physicalOutputOwnership.removeDevice(identifier)
    let capabilities = await pipeline.physicalOutputCapabilities()
    if capabilities.supportsRumble {
      _ = await sendPhysicalOutput(
        .command(.stopRumble),
        for: identifier,
        pipeline: pipeline,
        detachedInfo: detachedInfo
      )
    }
    var channels = Set<PhysicalOutputChannel>()
    if capabilities.lightingFeatures.contains(.playerIndicator) {
      channels.insert(.playerIndicator)
    }
    if capabilities.lightingFeatures.contains(.programmableColor) { channels.insert(.color) }
    if capabilities.lightingFeatures.contains(.programmableBrightness) {
      channels.insert(.brightness)
    }
    channels.formUnion(capabilities.adaptiveTriggers.map(PhysicalOutputChannel.adaptiveTrigger))
    for channel in channels.sorted(by: { $0.sortKey < $1.sortKey }) {
      _ = await applyPhysicalChannel(
        channel,
        for: identifier,
        pipeline: pipeline,
        detachedInfo: detachedInfo
      )
    }
  }

  func discardPhysicalOutputs(for identifier: LogicalControllerID) {
    rumbleStopTasks.removeValue(forKey: identifier)?.cancel()
    rumbleStopTokens.remove(identifier)
    physicalOutputOwnership.removeDevice(identifier)
  }

  /// The one connected controller `controller` names; nil when none, or more than one, does.
  package func connectedIdentifier(
    for controller: ControllerReference
  ) async -> LogicalControllerID? {
    guard !isStopping else { return nil }
    return try? await resolve(controller)
  }

  /// The one connected controller `controller` names.
  package func resolve(
    _ controller: ControllerReference
  ) async throws(ControllerReferenceError) -> LogicalControllerID {
    try await controller.resolve(in: connectedControllers()).logicalControllerID
  }

  /// Every connected controller with the token of its attachment, sorted by key.
  package func connectedControllers() async -> [ConnectedController] {
    await connectedLogicalControllerIDs().sorted().compactMap { identifier in
      deviceInfos[identifier].map {
        ConnectedController(
          logicalControllerID: identifier,
          sessionToken: $0.sessionToken,
          installationKey: installationKey
        )
      }
    }
  }

  internal func enforcePhysicalHIDOutputInterval(
    for identifier: LogicalControllerID,
    pipeline: DevicePipeline
  ) async throws {
    let minimum = await pipeline.minimumPhysicalOutputIntervalNanoseconds()
    guard minimum > 0 else { return }
    while true {
      let now = DispatchTime.now().uptimeNanoseconds
      let previous = lastPhysicalHIDOutputNanoseconds[identifier] ?? 0
      let elapsed = now >= previous ? now - previous : minimum
      if elapsed >= minimum {
        lastPhysicalHIDOutputNanoseconds[identifier] = now
        return
      }
      try await Task.sleep(nanoseconds: minimum - elapsed)
    }
  }

  /// Whether output for `identifier` may be queued: a HID pipeline is current, or `detachedInfo`
  /// names a detached HID connection this manager still owns for neutralization.
  internal func acceptsPhysicalOutput(
    identifier: LogicalControllerID,
    pipeline: DevicePipeline,
    startupConnection: HIDDeviceConnection? = nil,
    detachedInfo: DeviceInfo?
  ) async -> Bool {
    // A raw-USB pipeline gates each packet itself on its current session and teardown scope.
    if case .usb = pipeline.transport { return true }
    if let detachedInfo {
      return isOwnedDetachedHIDNeutralization(
        identifier: identifier,
        pipeline: pipeline,
        detachedInfo: detachedInfo
      )
    }
    return await isCurrentPhysicalHIDOutput(
      identifier: identifier,
      pipeline: pipeline,
      startupConnection: startupConnection,
      detachedInfo: nil
    )
  }

  /// Writes output reports in order at `intervalNanoseconds` spacing inside an output queue
  /// operation. User output stops at the first failed report and keeps the physical output rate
  /// limit; a `lifecycle` plan (startup, recovery, keep-alive) is paced only by its own interval
  /// and sends every report, failing if any report failed.
  internal func performHIDOutputPlan(
    _ reports: [PhysicalHIDOutputReport],
    intervalNanoseconds: UInt64,
    address: ControllerConnectionAddress,
    identifier: LogicalControllerID,
    pipeline: DevicePipeline,
    startupConnection: HIDDeviceConnection?,
    detachedInfo: DeviceInfo?,
    lifecycle: Bool,
    in _: PhysicalOutputQueueOperation
  ) async -> Bool {
    // macOS owns a native controller's output; OJD writes only what its allowance names.
    if let allowance = pipeline.macOSOwnedOutput,
      reports.isEmpty || !reports.allSatisfy({ allowance.permits($0, kind: .output) })
    {
      return false
    }
    var succeeded = true
    for (index, report) in reports.enumerated() {
      if index > 0, intervalNanoseconds > 0 {
        do { try await Task.sleep(nanoseconds: intervalNanoseconds) } catch { return false }
      }
      guard
        await isCurrentPhysicalHIDOutput(
          identifier: identifier,
          pipeline: pipeline,
          startupConnection: startupConnection,
          detachedInfo: detachedInfo
        )
      else { return false }
      if !lifecycle {
        do { try await enforcePhysicalHIDOutputInterval(for: identifier, pipeline: pipeline) } catch
        { return false }
      }
      guard
        await isCurrentPhysicalHIDOutput(
          identifier: identifier,
          pipeline: pipeline,
          startupConnection: startupConnection,
          detachedInfo: detachedInfo
        )
      else { return false }
      let result: PhysicalHIDReportResult<Void>
      if let detachedInfo {
        guard
          let connection = await currentDetachedHIDConnection(
            identifier: identifier,
            pipeline: pipeline,
            detachedInfo: detachedInfo
          )
        else { return false }
        result = await hidManager.setOutputReport(connection: connection, report: report)
      } else if writesExactHIDConnection(identifier, pipeline: pipeline) {
        guard let connection = currentHIDConnection(for: identifier, address: address) else {
          return false
        }
        result = await hidManager.setOutputReport(connection: connection, report: report)
      } else {
        result = await hidManager.setOutputReport(address: address, report: report)
      }
      if !result.succeeded {
        guard lifecycle else { return false }
        print(
          "[DeviceManager] HID lifecycle output report failed for controller=\(identifier) "
            + "route=\(address) report=\(report.reportID): \(result.failureDescription)"
        )
        succeeded = false
      }
      guard
        await isCurrentPhysicalHIDOutput(
          identifier: identifier,
          pipeline: pipeline,
          startupConnection: startupConnection,
          detachedInfo: detachedInfo
        )
      else { return false }
    }
    return succeeded
  }

  func currentDetachedHIDConnection(
    identifier: LogicalControllerID,
    pipeline: DevicePipeline,
    detachedInfo: DeviceInfo
  ) async -> HIDDeviceConnection? {
    guard let address = identifier.hidRoutingAddress,
      let connectionID = detachedInfo.hidConnectionID,
      let physicalDevice = detachedInfo.physicalDevice,
      let snapshots = await hidManager.currentConnectionSnapshots(),
      let snapshot = snapshots.first(where: {
        $0.connection.connectionID == connectionID && $0.connection.physicalDevice == physicalDevice
          && $0.connection.routingAddress == address
      }),
      await isCurrentPhysicalHIDOutput(
        identifier: identifier,
        pipeline: pipeline,
        startupConnection: nil,
        detachedInfo: detachedInfo
      )
    else { return nil }
    return snapshot.connection
  }

  func isCurrentPhysicalHIDOutput(
    identifier: LogicalControllerID,
    pipeline: DevicePipeline,
    startupConnection: HIDDeviceConnection?,
    detachedInfo: DeviceInfo?
  ) async -> Bool {
    guard !isStopping || ControllerTeardownOutput.isActive else { return false }
    if let detachedInfo {
      guard
        isOwnedDetachedHIDNeutralization(
          identifier: identifier,
          pipeline: pipeline,
          detachedInfo: detachedInfo
        )
      else { return false }
      guard let address = identifier.hidRoutingAddress,
        let expectedConnectionID = detachedInfo.hidConnectionID,
        let key = hidInitializationKey(for: identifier, connectionID: expectedConnectionID),
        let expectedPhysicalDevice = detachedInfo.physicalDevice
      else { return false }
      if let initialization = hidInitializationTasks[key],
        initialization.connection.connectionID != expectedConnectionID
          || initialization.connection.physicalDevice != expectedPhysicalDevice
      {
        return false
      }
      guard let snapshots = await hidManager.currentConnectionSnapshots(),
        snapshots.contains(where: {
          $0.connection.connectionID == expectedConnectionID
            && $0.connection.physicalDevice == expectedPhysicalDevice
            && $0.connection.routingAddress == address
        }),
        isOwnedDetachedHIDNeutralization(
          identifier: identifier,
          pipeline: pipeline,
          detachedInfo: detachedInfo
        )
      else { return false }
      if let initialization = hidInitializationTasks[key],
        initialization.connection.connectionID != expectedConnectionID
          || initialization.connection.physicalDevice != expectedPhysicalDevice
      {
        return false
      }
      return startupConnection == nil
    }
    guard pipelines[identifier] === pipeline else { return false }
    if let startupConnection {
      return isCurrentHIDStartupConnection(pipeline, connection: startupConnection)
    }
    return true
  }

  private func isOwnedDetachedHIDNeutralization(
    identifier: LogicalControllerID,
    pipeline: DevicePipeline,
    detachedInfo: DeviceInfo
  ) -> Bool {
    guard pipelines[identifier] == nil, case .hid = detachedInfo.discoverySource,
      let currentInfo = deviceInfos[identifier], case .hid = currentInfo.discoverySource
    else { return false }
    return currentInfo.hidConnectionID == detachedInfo.hidConnectionID
      && currentInfo.physicalDevice == detachedInfo.physicalDevice
      && pipeline.identifier == identifier
  }
}
