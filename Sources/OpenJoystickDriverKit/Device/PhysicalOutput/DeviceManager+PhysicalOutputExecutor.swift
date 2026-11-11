import Foundation

extension DeviceManager {
  /// The output queue of the interface `identifier` names, created on first use.
  func physicalOutputQueue(for identifier: LogicalControllerID) -> PhysicalHIDOutputSerialQueue {
    if let queue = hidOutputQueues[identifier] { return queue }
    let queue = PhysicalHIDOutputSerialQueue(
      after: retiredHIDOutputQueues.removeValue(forKey: identifier)
    )
    hidOutputQueues[identifier] = queue
    return queue
  }

  /// Cancels the interface's queued output and removes its queue, when it is still `expected` (any
  /// queue when nil).
  ///
  /// An operation may still be running on it, so the next queue created for the interface waits
  /// until it drains.
  func retireOutputQueue(
    for identifier: LogicalControllerID,
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
  /// interface's output queue.
  ///
  /// A run of output reports goes out as one lifecycle output plan at `intervalNanoseconds` spacing
  /// and a run of feature reports as one feature batch, each through its write body and so behind
  /// the native write gate. Every write is attempted; the result is false if any failed or the
  /// operation was cancelled. A run of USB writes goes to the pipeline, which sends it on the
  /// driver's USB command channel; without one it fails the result.
  func sendHIDWrites(
    _ writes: [PhysicalOutputWrite],
    intervalNanoseconds: UInt64 = 0,
    address: ControllerConnectionAddress,
    identifier: LogicalControllerID,
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
        address: address,
        identifier: identifier,
        pipeline: pipeline,
        startupConnection: startupConnection,
        detachedInfo: detachedInfo,
        in: operation
      )
    }
    return outcome == .completed(true)
  }

  /// Sends one HID keep-alive run.
  ///
  /// The pipeline produces the run's writes inside the output queue operation, so a rumble command
  /// queued before the run is encoded first and the run resends the state it left. A run with no
  /// writes sends nothing. The result is false if a write failed or the operation was cancelled. An
  /// inactive session sends nothing and is not a failure; the loop ends at its next interval check.
  func sendHIDKeepAlive(
    address: ControllerConnectionAddress,
    identifier: LogicalControllerID,
    pipeline: DevicePipeline
  ) async -> Bool {
    guard
      await acceptsPhysicalOutput(identifier: identifier, pipeline: pipeline, detachedInfo: nil)
    else { return false }
    let outcome = await physicalOutputQueue(for: identifier).perform { [weak self] operation in
      guard let self else { return false }
      guard let writes = await pipeline.hidKeepAliveWrites(), !writes.isEmpty else { return true }
      return await self.performHIDWrites(
        writes,
        intervalNanoseconds: 0,
        address: address,
        identifier: identifier,
        pipeline: pipeline,
        startupConnection: nil,
        detachedInfo: nil,
        in: operation
      )
    }
    return outcome == .completed(true)
  }

  /// Writes `writes` in order inside the output queue operation `operation`.
  ///
  /// Consecutive USB packets and consecutive HID output reports each go out as one batch, spaced by
  /// `intervalNanoseconds`.
  ///
  /// - Returns: Whether every write succeeded.
  private func performHIDWrites(
    _ writes: [PhysicalOutputWrite],
    intervalNanoseconds: UInt64,
    address: ControllerConnectionAddress,
    identifier: LogicalControllerID,
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
          address: address,
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
          address: address,
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

  /// Writes feature reports in order inside an output queue operation.
  ///
  /// User output stops at the first failed report; a `lifecycle` batch sends every report and fails
  /// if any report failed.
  func performHIDFeatureReports(
    _ reports: [PhysicalHIDOutputReport],
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
        guard let connection = currentHIDConnection(for: identifier, address: address) else {
          return false
        }
        result = await hidManager.setFeatureReport(connection: connection, report: report)
      } else {
        result = await hidManager.setFeatureReport(address: address, report: report)
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
            + "route=\(address) report=\(report.reportID): \(result.failureDescription)"
        )
        guard lifecycle else { return false }
        succeeded = false
      }
    }
    return succeeded
  }

  /// Whether a HID feature write for `identifier` may be made now: the task is not cancelled, the
  /// manager is not stopping unless teardown output runs, and the pipeline, the startup connection
  /// or the detached device information is current.
  private func isCurrentHIDFeatureOutput(
    identifier: LogicalControllerID,
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
