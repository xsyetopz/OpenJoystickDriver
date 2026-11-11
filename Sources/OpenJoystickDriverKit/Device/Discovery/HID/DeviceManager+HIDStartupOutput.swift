import Foundation

extension DeviceManager {

  /// Reads the startup feature reports that the pipeline requests.
  ///
  /// A read is retried up to three times when the session plan validates replies. An exhausted read
  /// is logged and the next request still goes out. The run ends when the pipeline or its
  /// connection stops being current.
  func sendHIDStartupFeatureReadRequestsIfNeeded(
    pipeline: DevicePipeline,
    connection: HIDDeviceConnection
  ) async {
    guard await isCurrentHIDStartupPipeline(pipeline, connection: connection) else { return }
    let requests = await pipeline.hidStartupFeatureReads()
    let validatesReplies = await pipeline.sessionPlan().validatesFeatureReplies
    guard await isCurrentHIDStartupPipeline(pipeline, connection: connection) else { return }
    for request in requests {
      let outcome = await HIDFeatureReadRetry.run(maximumAttempts: validatesReplies ? 3 : 1) {
        await self.attemptHIDStartupFeatureRead(
          pipeline: pipeline,
          request: request,
          connection: connection,
          validatesReply: validatesReplies
        )
      }
      guard await isCurrentHIDStartupPipeline(pipeline, connection: connection) else { return }
      switch outcome {
      case .accepted: break
      case .stopped: return
      case .retry:
        let address = connection.routingAddress
        print("[DeviceManager] HID startup feature read exhausted for route=\(address)")
      }
    }
  }

  /// Makes one attempt at a startup feature read through the output queue of the controller, so it
  /// never interleaves with a write.
  ///
  /// - Returns: ``HIDFeatureReadAttempt/accepted`` when the read gave data and, with
  ///   `validatesReply`, the pipeline accepted it; ``HIDFeatureReadAttempt/retry`` for a failed
  ///   read or a rejected reply; ``HIDFeatureReadAttempt/stopped`` when the pipeline or connection
  ///   stops being current.
  private func attemptHIDStartupFeatureRead(
    pipeline: DevicePipeline,
    request: PhysicalHIDFeatureReadRequest,
    connection: HIDDeviceConnection,
    validatesReply: Bool
  ) async -> HIDFeatureReadAttempt {
    let address = connection.routingAddress
    guard await isCurrentHIDStartupPipeline(pipeline, connection: connection) else {
      return .stopped
    }
    // The read is an operation on the interface's output queue, so it never interleaves with a
    // write's operation. It takes the same route as the controller's writes.
    let outcome = await physicalOutputQueue(for: pipeline.identifier).perform {
      [weak self] _ -> PhysicalHIDReportResult<Data>? in
      guard let self, await self.isCurrentHIDStartupConnection(pipeline, connection: connection)
      else { return nil }
      return await self.writesExactHIDConnection(pipeline.identifier, pipeline: pipeline)
        ? await self.hidManager.getFeatureReport(connection: connection, request: request)
        : await self.hidManager.getFeatureReport(address: address, request: request)
    }
    guard case .completed(let result?) = outcome,
      await isCurrentHIDStartupPipeline(pipeline, connection: connection)
    else { return .stopped }
    guard let data = result.value else {
      print(
        "[DeviceManager] HID startup feature read failed for controller=\(pipeline.identifier) "
          + "route=\(address) report=\(request.reportID): \(result.failureDescription)"
      )
      return .retry
    }
    guard validatesReply else { return .accepted }
    let accepted = await pipeline.consumeFeatureReply(data, request: request)
    return accepted ? .accepted : .retry
  }

  /// Sends the activation writes of the driver, then those of the controller record, to a HID
  /// controller; does nothing unless `pipeline` is current for `connection`.
  func sendHIDActivationWritesIfNeeded(
    pipeline: DevicePipeline,
    connection: HIDDeviceConnection
  ) async {
    guard await isCurrentHIDStartupPipeline(pipeline, connection: connection) else { return }
    let writes = await pipeline.hidActivationWrites()
    guard await isCurrentHIDStartupPipeline(pipeline, connection: connection) else { return }
    _ = await sendHIDWrites(
      writes,
      address: connection.routingAddress,
      identifier: pipeline.identifier,
      pipeline: pipeline,
      startupConnection: connection
    )
    await sendRecordStartupWrites(pipeline: pipeline, connection: connection)
  }

  /// Sends the activation-phase startup writes of the record or its description in order, each
  /// after its delay.
  ///
  /// A failed write is logged and the rest still go out, as with the driver's activation writes.
  private func sendRecordStartupWrites(
    pipeline: DevicePipeline,
    connection: HIDDeviceConnection
  ) async {
    guard await isCurrentHIDStartupPipeline(pipeline, connection: connection) else { return }
    let writes = await pipeline.activationStartupWrites()
    let sent = await sendHIDStartupWrites(
      writes,
      intervalNanoseconds: 0,
      pipeline: pipeline,
      connection: connection
    )
    guard await isCurrentHIDStartupPipeline(pipeline, connection: connection) else { return }
    if !sent {
      print(
        "[DeviceManager] Startup write failed for controller=\(pipeline.identifier) "
          + "route=\(connection.routingAddress)"
      )
    }
  }

  /// Sends startup writes in order at `intervalNanoseconds` spacing.
  ///
  /// A write that names its own delay waits that long first, in place of the interval; the writes
  /// between two such writes go out as one batch.
  private func sendHIDStartupWrites(
    _ writes: [PhysicalOutputWrite],
    intervalNanoseconds: UInt64,
    pipeline: DevicePipeline,
    connection: HIDDeviceConnection
  ) async -> Bool {
    // An empty list still goes to `sendHIDWrites`, which decides whether output is accepted.
    var batches: [[PhysicalOutputWrite]] = writes.isEmpty ? [[]] : []
    for write in writes {
      if write.startupDelayMilliseconds != nil || batches.isEmpty {
        batches.append([write])
      } else {
        batches[batches.count - 1].append(write)
      }
    }
    var succeeded = true
    for batch in batches {
      if let delay = batch.first?.startupDelayMilliseconds, delay > 0 {
        let nanoseconds = UInt64(delay) * DeviceTransportProfile.nanosecondsPerMillisecond
        do { try await Task.sleep(nanoseconds: nanoseconds) } catch { return false }
      }
      guard await isCurrentHIDStartupPipeline(pipeline, connection: connection) else {
        return false
      }
      let sent = await sendHIDWrites(
        batch,
        intervalNanoseconds: intervalNanoseconds,
        address: connection.routingAddress,
        identifier: pipeline.identifier,
        pipeline: pipeline,
        startupConnection: connection
      )
      succeeded = succeeded && sent
    }
    return succeeded
  }

  /// Sends the HID startup output reports and records their result for the controller details, then
  /// runs the startup recovery that the session plan names.
  ///
  /// - Returns: Whether every startup write went out; false when the pipeline stops being current.
  func sendHIDStartupOutputReportsIfNeeded(
    pipeline: DevicePipeline,
    connection: HIDDeviceConnection
  ) async -> Bool {
    guard await isCurrentHIDStartupPipeline(pipeline, connection: connection) else { return false }
    let writes = await pipeline.hidStartupWrites()
    let plan = await pipeline.sessionPlan()
    guard await isCurrentHIDStartupPipeline(pipeline, connection: connection) else { return false }
    let succeeded = await sendHIDStartupWrites(
      writes,
      intervalNanoseconds: plan.hidStartupIntervalNanoseconds,
      pipeline: pipeline,
      connection: connection
    )
    guard await isCurrentHIDStartupPipeline(pipeline, connection: connection) else { return false }
    // The controller details show the result; a startup with no writes has none to show.
    if !succeeded {
      print(
        "[DeviceManager] HID startup output failed for controller=\(pipeline.identifier) "
          + "route=\(connection.routingAddress)"
      )
      await pipeline.recordStartupOutputStatus("failed")
    } else if !writes.isEmpty {
      await pipeline.recordStartupOutputStatus("succeeded")
    }
    if plan.hasStartupRecovery {
      await runHIDStartupRecovery(pipeline: pipeline, connection: connection, plan: plan)
    }
    return succeeded
  }

  /// Repeats the startup recovery writes for the rounds that `plan` names, one round per recovery
  /// interval, and then expires the recovery.
  ///
  /// A failed recovery write is not retried within its round. The run ends when the pipeline stops
  /// being current.
  private func runHIDStartupRecovery(
    pipeline: DevicePipeline,
    connection: HIDDeviceConnection,
    plan: DriverSessionPlan
  ) async {
    let address = connection.routingAddress
    let interval = plan.hidStartupIntervalNanoseconds
    for round in 0...plan.hidStartupRecoveryRounds {
      do { try await Task.sleep(nanoseconds: plan.hidStartupRecoveryIntervalNanoseconds) } catch {
        return
      }
      guard !Task.isCancelled, await isCurrentHIDStartupPipeline(pipeline, connection: connection)
      else { return }
      if round == plan.hidStartupRecoveryRounds {
        await pipeline.expireHIDStartupRecovery()
        return
      }
      let writes = await pipeline.hidStartupRecoveryWrites()
      guard await isCurrentHIDStartupPipeline(pipeline, connection: connection) else { return }
      for (index, write) in writes.enumerated() {
        if index > 0 { do { try await Task.sleep(nanoseconds: interval) } catch { return } }
        guard !Task.isCancelled, await isCurrentHIDStartupPipeline(pipeline, connection: connection)
        else { return }
        // A failed recovery write is not retried within the round; expiry still follows.
        _ = await sendHIDWrites(
          [write],
          address: address,
          identifier: pipeline.identifier,
          pipeline: pipeline,
          startupConnection: connection
        )
        guard await isCurrentHIDStartupPipeline(pipeline, connection: connection) else { return }
      }
    }
  }

  /// Whether `pipeline` is active and `connection` is still its current startup connection.
  func isCurrentHIDStartupPipeline(
    _ pipeline: DevicePipeline,
    connection: HIDDeviceConnection
  ) async -> Bool {
    guard await pipeline.isActive else { return false }
    return isCurrentHIDStartupConnection(pipeline, connection: connection)
  }

  /// Whether `connection` is the HID connection that `pipeline` serves.
  ///
  /// The manager must not be stopping, the initialization must be current, and the pipeline, its
  /// routing address and the device information must still match. Another client must not own the
  /// input.
  func isCurrentHIDStartupConnection(
    _ pipeline: DevicePipeline,
    connection: HIDDeviceConnection
  ) -> Bool {
    let identifier = pipeline.identifier
    guard !Task.isCancelled, !isStopping, isCurrentHIDInitialization(connection),
      pipelines[identifier] === pipeline, identifier.hidRoutingAddress == connection.routingAddress,
      let info = deviceInfos[identifier], case .hid = info.discoverySource,
      info.hidConnectionID == connection.connectionID,
      info.physicalDevice == connection.physicalDevice,
      info.hidInputOwnership != .ownedByAnotherClient
    else { return false }
    return true
  }

  /// Sends the presence request of the pipeline to find out whether the controller's input
  /// connection is up, and logs a failed write; does nothing when the pipeline has no such request.
  func requestHIDInputConnectionStatusIfNeeded(
    pipeline: DevicePipeline,
    connection: HIDDeviceConnection
  ) async {
    let address = connection.routingAddress
    guard await isCurrentHIDStartupPipeline(pipeline, connection: connection) else { return }
    guard let write = await pipeline.hidPresenceRequestWrite() else { return }
    guard await isCurrentHIDStartupPipeline(pipeline, connection: connection) else { return }
    let result = await sendHIDWrites(
      [write],
      address: address,
      identifier: pipeline.identifier,
      pipeline: pipeline,
      startupConnection: connection
    )
    guard await isCurrentHIDStartupPipeline(pipeline, connection: connection) else { return }
    if !result {
      print(
        "[DeviceManager] HID connection-status request failed for"
          + " controller=\(pipeline.identifier) route=\(address)"
      )
    }
  }
}
