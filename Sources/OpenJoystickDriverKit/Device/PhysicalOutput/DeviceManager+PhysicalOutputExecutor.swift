import Foundation

extension DeviceManager {
  /// The output queue of the interface `identifier` names, created on first use.
  func physicalOutputQueue(for identifier: DeviceIdentifier) -> PhysicalHIDOutputSerialQueue {
    if let queue = hidOutputQueues[identifier] { return queue }
    let queue = PhysicalHIDOutputSerialQueue(
      after: retiredHIDOutputQueues.removeValue(forKey: identifier)
    )
    hidOutputQueues[identifier] = queue
    return queue
  }

  /// Cancels the interface's queued output and removes its queue, when it is still `expected`
  /// (any queue when nil). An operation may still be running on it, so the next queue created for
  /// the interface waits until it drains.
  func retireOutputQueue(
    for identifier: DeviceIdentifier,
    expected: PhysicalHIDOutputSerialQueue? = nil
  ) {
    guard let queue = hidOutputQueues[identifier], expected.map({ $0 === queue }) ?? true else {
      return
    }
    queue.cancelAll()
    hidOutputQueues.removeValue(forKey: identifier)
    retiredHIDOutputQueues[identifier] = queue
  }

  /// Performs driver-produced lifecycle writes on a HID device in order, as one operation on the
  /// interface's output queue. A run of output reports goes out as one lifecycle output plan at
  /// `intervalNanoseconds` spacing and a run of feature reports as one feature batch, each through
  /// its write body and so behind the native write gate. Every write is attempted; the result is
  /// false if any failed or the operation was cancelled. A run of USB writes goes to the pipeline,
  /// which sends it on the driver's USB command channel; without one it fails the result.
  func sendHIDWrites(
    _ writes: [PhysicalOutputWrite],
    intervalNanoseconds: UInt64 = 0,
    locationID: UInt32,
    identifier: DeviceIdentifier,
    pipeline: DevicePipeline,
    startupConnection: HIDDeviceConnection? = nil,
    detachedInfo: DeviceInfo? = nil
  ) async -> Bool {
    guard
      await acceptsPhysicalOutput(
        identifier: identifier,
        pipeline: pipeline,
        startupConnection: startupConnection,
        detachedInfo: detachedInfo
      )
    else { return false }
    let outcome = await physicalOutputQueue(for: identifier).perform { [weak self] operation in
      guard let self else { return false }
      return await self.performHIDWrites(
        writes,
        intervalNanoseconds: intervalNanoseconds,
        locationID: locationID,
        identifier: identifier,
        pipeline: pipeline,
        startupConnection: startupConnection,
        detachedInfo: detachedInfo,
        in: operation
      )
    }
    return outcome == .completed(true)
  }

  private func performHIDWrites(
    _ writes: [PhysicalOutputWrite],
    intervalNanoseconds: UInt64,
    locationID: UInt32,
    identifier: DeviceIdentifier,
    pipeline: DevicePipeline,
    startupConnection: HIDDeviceConnection?,
    detachedInfo: DeviceInfo?,
    in operation: PhysicalOutputQueueOperation
  ) async -> Bool {
    var index = 0
    var succeeded = true
    while index < writes.count {
      var reports: [PhysicalHIDOutputReport] = []
      let sent: Bool
      switch writes[index] {
      case .usb:
        var packets: [PhysicalUSBOutputPacket] = []
        while index < writes.count, case .usb(let packet, _) = writes[index] {
          packets.append(packet)
          index += 1
        }
        sent = await pipeline.sendUSBOutput(packets, intervalNanoseconds: intervalNanoseconds)
      case .hidOutput:
        while index < writes.count, case .hidOutput(let report) = writes[index] {
          reports.append(report)
          index += 1
        }
        sent = await performHIDOutputPlan(
          reports,
          intervalNanoseconds: intervalNanoseconds,
          locationID: locationID,
          identifier: identifier,
          pipeline: pipeline,
          startupConnection: startupConnection,
          detachedInfo: detachedInfo,
          lifecycle: true,
          in: operation
        )
      case .hidFeature:
        while index < writes.count, case .hidFeature(let report) = writes[index] {
          reports.append(report)
          index += 1
        }
        sent = await performHIDFeatureReports(
          reports,
          locationID: locationID,
          identifier: identifier,
          pipeline: pipeline,
          startupConnection: startupConnection,
          detachedInfo: detachedInfo,
          lifecycle: true,
          in: operation
        )
      }
      succeeded = succeeded && sent
    }
    return succeeded
  }

  /// Writes feature reports in order inside an output queue operation. User output stops at the
  /// first failed report; a `lifecycle` batch sends every report and fails if any report failed.
  func performHIDFeatureReports(
    _ reports: [PhysicalHIDOutputReport],
    locationID: UInt32,
    identifier: DeviceIdentifier,
    pipeline: DevicePipeline,
    startupConnection: HIDDeviceConnection?,
    detachedInfo: DeviceInfo?,
    lifecycle: Bool,
    in _: PhysicalOutputQueueOperation
  ) async -> Bool {
    // macOS owns a native controller's output; OJD writes only what its allowance names.
    if let allowance = pipeline.nativeWrites,
      reports.isEmpty || !reports.allSatisfy({ allowance.permits($0, kind: .feature) })
    {
      return false
    }
    var succeeded = true
    for report in reports {
      guard
        isCurrentHIDFeatureOutput(
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
          ),
          isCurrentHIDFeatureOutput(
            identifier: identifier,
            pipeline: pipeline,
            startupConnection: startupConnection,
            detachedInfo: detachedInfo
          )
        else { return false }
        result = await hidManager.setFeatureReport(connection: connection, report: report)
      } else if writesExactHIDConnection(identifier, pipeline: pipeline) {
        guard let connection = currentHIDConnection(for: identifier, locationID: locationID) else {
          return false
        }
        result = await hidManager.setFeatureReport(connection: connection, report: report)
      } else {
        result = await hidManager.setFeatureReport(locationID: locationID, report: report)
      }
      guard
        isCurrentHIDFeatureOutput(
          identifier: identifier,
          pipeline: pipeline,
          startupConnection: startupConnection,
          detachedInfo: detachedInfo
        )
      else { return false }
      if !result.succeeded {
        print(
          "[DeviceManager] HID feature report failed for controller=\(identifier) "
            + "loc=\(locationID) report=\(report.reportID): \(result.failureDescription)"
        )
        guard lifecycle else { return false }
        succeeded = false
      }
    }
    return succeeded
  }

  private func isCurrentHIDFeatureOutput(
    identifier: DeviceIdentifier,
    pipeline: DevicePipeline,
    startupConnection: HIDDeviceConnection?,
    detachedInfo: DeviceInfo?
  ) -> Bool {
    guard !Task.isCancelled, !isStopping || ControllerTeardownOutput.isActive else { return false }
    if let detachedInfo {
      guard pipelines[identifier] == nil, isCurrentHIDDeviceInfo(detachedInfo, for: identifier),
        let connectionID = detachedInfo.hidConnectionID,
        let key = hidInitializationKey(for: identifier, connectionID: connectionID),
        let physicalDevice = detachedInfo.physicalDevice
      else { return false }
      if let initialization = hidInitializationTasks[key],
        initialization.connection.connectionID != connectionID
          || initialization.connection.physicalDevice != physicalDevice
      {
        return false
      }
      return true
    }
    guard pipelines[identifier] === pipeline else { return false }
    if let startupConnection {
      return isCurrentHIDStartupConnection(pipeline, connection: startupConnection)
    }
    return true
  }
}
