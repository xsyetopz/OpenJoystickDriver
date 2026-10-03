import Foundation

extension DeviceManager {

  func neutralizePhysicalOutputs(
    for identifier: DeviceIdentifier,
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

  func discardPhysicalOutputs(for identifier: DeviceIdentifier) {
    rumbleStopTasks.removeValue(forKey: identifier)?.cancel()
    rumbleStopTokens.remove(identifier)
    physicalOutputOwnership.removeDevice(identifier)
  }

  internal func connectedIdentifier(
    matching model: DeviceIdentifier,
    runtimeIdentifier: String?
  ) -> DeviceIdentifier? {
    guard !isStopping else { return nil }
    return Self.connectedIdentifier(
      among: pipelines.keys,
      matching: model,
      runtimeIdentifier: runtimeIdentifier
    )
  }

  package static func connectedIdentifier<Identifiers: Sequence>(
    among identifiers: Identifiers,
    matching model: DeviceIdentifier,
    runtimeIdentifier: String?
  ) -> DeviceIdentifier? where Identifiers.Element == DeviceIdentifier {
    let matches = identifiers.filter {
      $0.modelMatches(model)
        && (runtimeIdentifier == nil || $0.runtimeIdentifier == runtimeIdentifier)
    }
    return matches.count == 1 ? matches.first : nil
  }

  internal func enforcePhysicalHIDOutputInterval(
    for identifier: DeviceIdentifier,
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
    identifier: DeviceIdentifier,
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
    locationID: UInt32,
    identifier: DeviceIdentifier,
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
        guard let connection = currentHIDConnection(for: identifier, locationID: locationID) else {
          return false
        }
        result = await hidManager.setOutputReport(connection: connection, report: report)
      } else {
        result = await hidManager.setOutputReport(locationID: locationID, report: report)
      }
      if !result.succeeded {
        guard lifecycle else { return false }
        print(
          "[DeviceManager] HID lifecycle output report failed for controller=\(identifier) "
            + "loc=\(locationID) report=\(report.reportID): \(result.failureDescription)"
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
    identifier: DeviceIdentifier,
    pipeline: DevicePipeline,
    detachedInfo: DeviceInfo
  ) async -> HIDDeviceConnection? {
    guard let locationID = identifier.locationID, let connectionID = detachedInfo.hidConnectionID,
      let physicalDevice = detachedInfo.physicalDevice,
      let snapshots = await hidManager.currentConnectionSnapshots(),
      let snapshot = snapshots.first(where: {
        $0.connection.connectionID == connectionID && $0.connection.physicalDevice == physicalDevice
          && $0.connection.routingLocationID == locationID
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
    identifier: DeviceIdentifier,
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
      guard let locationID = identifier.locationID,
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
            && $0.connection.routingLocationID == locationID
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
    identifier: DeviceIdentifier,
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
