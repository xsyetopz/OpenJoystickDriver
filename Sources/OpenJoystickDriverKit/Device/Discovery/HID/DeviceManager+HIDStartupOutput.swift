import Foundation

extension DeviceManager {

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
        let locationID = connection.routingLocationID
        print("[DeviceManager] HID startup feature read exhausted for loc=\(locationID)")
      }
    }
  }

  private func attemptHIDStartupFeatureRead(
    pipeline: DevicePipeline,
    request: PhysicalHIDFeatureReadRequest,
    connection: HIDDeviceConnection,
    validatesReply: Bool
  ) async -> HIDFeatureReadAttempt {
    let locationID = connection.routingLocationID
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
        : await self.hidManager.getFeatureReport(locationID: locationID, request: request)
    }
    guard case .completed(let result?) = outcome,
      await isCurrentHIDStartupPipeline(pipeline, connection: connection)
    else { return .stopped }
    guard let data = result.value else {
      print(
        "[DeviceManager] HID startup feature read failed for controller=\(pipeline.identifier) "
          + "loc=\(locationID) report=\(request.reportID): \(result.failureDescription)"
      )
      return .retry
    }
    guard validatesReply else { return .accepted }
    let accepted = await pipeline.consumeFeatureReply(data, request: request)
    return accepted ? .accepted : .retry
  }

  func sendHIDActivationWritesIfNeeded(
    pipeline: DevicePipeline,
    connection: HIDDeviceConnection
  ) async {
    guard await isCurrentHIDStartupPipeline(pipeline, connection: connection) else { return }
    let writes = await pipeline.hidActivationWrites()
    guard await isCurrentHIDStartupPipeline(pipeline, connection: connection) else { return }
    _ = await sendHIDWrites(
      writes,
      locationID: connection.routingLocationID,
      identifier: pipeline.identifier,
      pipeline: pipeline,
      startupConnection: connection
    )
    await sendRecordStartupWrites(pipeline: pipeline, connection: connection)
  }

  /// Sends the record's startup writes in order, each after its delay. A failed write is logged
  /// and the rest still go out, as with the driver's activation writes.
  private func sendRecordStartupWrites(
    pipeline: DevicePipeline,
    connection: HIDDeviceConnection
  ) async {
    guard await isCurrentHIDStartupPipeline(pipeline, connection: connection) else { return }
    let writes = await pipeline.recordStartupWrites()
    for write in writes {
      if write.delayMilliseconds > 0 {
        let delay =
          UInt64(write.delayMilliseconds) * DeviceTransportProfile.nanosecondsPerMillisecond
        do { try await Task.sleep(nanoseconds: delay) } catch { return }
      }
      guard await isCurrentHIDStartupPipeline(pipeline, connection: connection) else { return }
      let sent = await sendHIDWrites(
        [write.write],
        locationID: connection.routingLocationID,
        identifier: pipeline.identifier,
        pipeline: pipeline,
        startupConnection: connection
      )
      guard await isCurrentHIDStartupPipeline(pipeline, connection: connection) else { return }
      if !sent {
        print(
          "[DeviceManager] Record startup write failed for controller=\(pipeline.identifier) "
            + "loc=\(connection.routingLocationID) report=\(write.report.reportID)"
        )
      }
    }
  }

  func sendHIDStartupOutputReportsIfNeeded(
    pipeline: DevicePipeline,
    connection: HIDDeviceConnection
  ) async -> Bool {
    guard await isCurrentHIDStartupPipeline(pipeline, connection: connection) else { return false }
    let writes = await pipeline.hidStartupWrites()
    let plan = await pipeline.sessionPlan()
    guard await isCurrentHIDStartupPipeline(pipeline, connection: connection) else { return false }
    let succeeded = await sendHIDWrites(
      writes,
      intervalNanoseconds: plan.hidStartupIntervalNanoseconds,
      locationID: connection.routingLocationID,
      identifier: pipeline.identifier,
      pipeline: pipeline,
      startupConnection: connection
    )
    guard await isCurrentHIDStartupPipeline(pipeline, connection: connection) else { return false }
    if plan.hasStartupRecovery {
      await runHIDStartupRecovery(pipeline: pipeline, connection: connection, plan: plan)
    }
    return succeeded
  }

  private func runHIDStartupRecovery(
    pipeline: DevicePipeline,
    connection: HIDDeviceConnection,
    plan: DriverSessionPlan
  ) async {
    let locationID = connection.routingLocationID
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
          locationID: locationID,
          identifier: pipeline.identifier,
          pipeline: pipeline,
          startupConnection: connection
        )
        guard await isCurrentHIDStartupPipeline(pipeline, connection: connection) else { return }
      }
    }
  }

  func isCurrentHIDStartupPipeline(
    _ pipeline: DevicePipeline,
    connection: HIDDeviceConnection
  ) async -> Bool {
    guard await pipeline.isActive else { return false }
    return isCurrentHIDStartupConnection(pipeline, connection: connection)
  }

  func isCurrentHIDStartupConnection(
    _ pipeline: DevicePipeline,
    connection: HIDDeviceConnection
  ) -> Bool {
    let identifier = pipeline.identifier
    guard !Task.isCancelled, !isStopping, isCurrentHIDInitialization(connection),
      pipelines[identifier] === pipeline, identifier.locationID == connection.routingLocationID,
      let info = deviceInfos[identifier], case .hid = info.discoverySource,
      info.hidConnectionID == connection.connectionID,
      info.physicalDevice == connection.physicalDevice,
      info.hidInputOwnership != .ownedByAnotherClient
    else { return false }
    return true
  }

  func requestHIDInputConnectionStatusIfNeeded(
    pipeline: DevicePipeline,
    connection: HIDDeviceConnection
  ) async {
    let locationID = connection.routingLocationID
    guard await isCurrentHIDStartupPipeline(pipeline, connection: connection) else { return }
    guard let write = await pipeline.hidPresenceRequestWrite() else { return }
    guard await isCurrentHIDStartupPipeline(pipeline, connection: connection) else { return }
    let result = await sendHIDWrites(
      [write],
      locationID: locationID,
      identifier: pipeline.identifier,
      pipeline: pipeline,
      startupConnection: connection
    )
    guard await isCurrentHIDStartupPipeline(pipeline, connection: connection) else { return }
    if !result {
      print(
        "[DeviceManager] HID connection-status request failed for"
          + " controller=\(pipeline.identifier) loc=\(locationID)"
      )
    }
  }
}
