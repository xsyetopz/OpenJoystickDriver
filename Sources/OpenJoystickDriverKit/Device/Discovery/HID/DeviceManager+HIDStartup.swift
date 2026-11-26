import Foundation

extension DeviceManager {
  /// Runs the startup of a registered HID `pipeline` in the order its session `plan` gives:
  /// element routing, unbound-claim reconciliation, startup output, feature reads, activation
  /// writes, output activation, the input-connection request, then periodic output.
  ///
  /// A native pass-through pipeline gets only the feature reads its allowance names, output
  /// activation, and the rumble keep-alive its record resends. Each step stops the startup once
  /// `pipeline` is no longer the current startup pipeline of `connection`. With
  /// `requiresSuccessfulStartupOutput`, external output is allowed only after startup output
  /// succeeded.
  func runHIDStartup(
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
      await finishPassThroughHIDStartup(pipeline, for: identifier, connection: connection)
      return
    }
    guard
      let startupOutputSucceeded = await sendHIDStartupReports(
        pipeline,
        connection: connection,
        plan: plan
      )
    else { return }
    if requiresSuccessfulStartupOutput {
      guard startupOutputSucceeded else { return }
      await pipeline.setExternalOutputAllowed(externalOutputAllowed)
      guard await isCurrentHIDStartupPipeline(pipeline, connection: connection) else { return }
    }
    await finishHIDStartup(pipeline, for: identifier, connection: connection, plan: plan)
  }

  /// Finishes the startup of a native pass-through `pipeline`: output activation, and the rumble
  /// keep-alive its record resends.
  private func finishPassThroughHIDStartup(
    _ pipeline: DevicePipeline,
    for identifier: LogicalControllerID,
    connection: HIDDeviceConnection
  ) async {
    if await pipeline.controllerSessionState() == .active,
      !(await pipeline.requiresInputConnectionBeforeOutput())
    {
      await pipeline.activateOutput()
    }
    // macOS runs the controller; OJD keeps alive only the rumble its record's template resends.
    if await pipeline.resendsRumble {
      scheduleHIDPeriodicOutput(for: identifier, pipeline: pipeline, connection: connection)
    }
  }

  /// Sends the startup output, feature reads and activation writes of `pipeline` in the order
  /// `plan` gives, and returns whether the startup output succeeded, or nil once `pipeline` is no
  /// longer the current startup pipeline of `connection`.
  private func sendHIDStartupReports(
    _ pipeline: DevicePipeline,
    connection: HIDDeviceConnection,
    plan: DriverSessionPlan
  ) async -> Bool? {
    // Startup writes go before or after the feature reads; activation follows the reads unless
    // it waits for a logical controller to connect.
    var startupOutputSucceeded = true
    if plan.outputPrecedesFeatureReads {
      startupOutputSucceeded = await sendHIDStartupOutputReportsIfNeeded(
        pipeline: pipeline,
        connection: connection
      )
      guard await isCurrentHIDStartupPipeline(pipeline, connection: connection) else { return nil }
    }
    await sendHIDStartupFeatureReadRequestsIfNeeded(pipeline: pipeline, connection: connection)
    guard await isCurrentHIDStartupPipeline(pipeline, connection: connection) else { return nil }
    if !plan.requiresInputConnectionBeforeOutput {
      await sendHIDActivationWritesIfNeeded(pipeline: pipeline, connection: connection)
      guard await isCurrentHIDStartupPipeline(pipeline, connection: connection) else { return nil }
    }
    if !plan.outputPrecedesFeatureReads {
      startupOutputSucceeded = await sendHIDStartupOutputReportsIfNeeded(
        pipeline: pipeline,
        connection: connection
      )
      guard await isCurrentHIDStartupPipeline(pipeline, connection: connection) else { return nil }
    }
    return startupOutputSucceeded
  }

  /// Activates the output of `pipeline` unless it waits for an input connection, requests the
  /// input-connection status, then schedules periodic output.
  private func finishHIDStartup(
    _ pipeline: DevicePipeline,
    for identifier: LogicalControllerID,
    connection: HIDDeviceConnection,
    plan: DriverSessionPlan
  ) async {
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
