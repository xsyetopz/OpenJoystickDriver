import Foundation

extension DeviceManager {
  /// Writes one user-output plan inside the output queue operation of its command, so the whole
  /// plan is atomic.
  ///
  /// Each run of writes goes to the body its destination names: USB packets to the pipeline's USB
  /// session, HID output reports to ``performHIDOutputPlan`` with the output rate limit, and
  /// feature reports to ``performHIDFeatureReports``, both behind the native write gate. Stops at
  /// the first failed run.
  internal func performPhysicalOutputPlan(
    _ plan: PhysicalOutputPlan,
    for identifier: LogicalControllerID,
    pipeline: DevicePipeline,
    detachedInfo: DeviceInfo?,
    in operation: PhysicalOutputQueueOperation
  ) async -> Bool {
    // Nothing to send (a Steam dongle without a controller) succeeds, except on a native
    // controller, whose executors refuse an empty batch.
    guard !plan.writes.isEmpty else { return pipeline.macOSOwnedOutput == nil }
    var cursor = PhysicalOutputWriteCursor(writes: plan.writes)
    while !cursor.isFinished {
      if cursor.index > 0, plan.intervalNanoseconds > 0 {
        do { try await Task.sleep(nanoseconds: plan.intervalNanoseconds) } catch { return false }
      }
      let sent = await performNextOutputRun(
        &cursor,
        plan: plan,
        for: identifier,
        pipeline: pipeline,
        detachedInfo: detachedInfo,
        in: operation
      )
      guard sent else { return false }
    }
    return true
  }

  /// Sends the run of writes of one destination at the cursor and moves the cursor past it.
  private func performNextOutputRun(
    _ cursor: inout PhysicalOutputWriteCursor,
    plan: PhysicalOutputPlan,
    for identifier: LogicalControllerID,
    pipeline: DevicePipeline,
    detachedInfo: DeviceInfo?,
    in operation: PhysicalOutputQueueOperation
  ) async -> Bool {
    switch cursor.writes[cursor.index] {
    case .usb:
      let packets = cursor.run { write -> PhysicalUSBOutputPacket? in
        guard case .usb(let packet, _) = write else { return nil }
        return packet
      }
      // A native controller is HID-only and receives no USB output.
      guard pipeline.macOSOwnedOutput == nil else { return false }
      return await pipeline.sendUSBOutput(packets, intervalNanoseconds: plan.intervalNanoseconds)
    case .hidOutput:
      let reports = cursor.run { write -> PhysicalHIDOutputReport? in
        guard case .hidOutput(let report) = write else { return nil }
        return report
      }
      guard let address = identifier.hidRoutingAddress else { return false }
      return await performHIDOutputPlan(
        reports,
        intervalNanoseconds: plan.intervalNanoseconds,
        address: address,
        identifier: identifier,
        pipeline: pipeline,
        startupConnection: nil,
        detachedInfo: detachedInfo,
        lifecycle: false,
        in: operation
      )
    case .hidFeature:
      let reports = cursor.run { write -> PhysicalHIDOutputReport? in
        guard case .hidFeature(let report) = write else { return nil }
        return report
      }
      guard let address = identifier.hidRoutingAddress else { return false }
      return await performHIDFeatureReports(
        reports,
        address: address,
        identifier: identifier,
        pipeline: pipeline,
        startupConnection: nil,
        detachedInfo: detachedInfo,
        lifecycle: false,
        in: operation
      )
    }
  }
}

/// The position in the writes of a plan that the run loop has reached.
struct PhysicalOutputWriteCursor {
  /// The writes of the plan, in order.
  let writes: [PhysicalOutputWrite]
  /// The index of the first write not yet taken.
  private(set) var index = 0

  /// Whether every write has been taken.
  var isFinished: Bool { index >= writes.count }

  /// Takes the writes from the cursor on that `item` maps to a value, up to the first that it does
  /// not.
  mutating func run<Item>(_ item: (PhysicalOutputWrite) -> Item?) -> [Item] {
    var items: [Item] = []
    while index < writes.count, let next = item(writes[index]) {
      items.append(next)
      index += 1
    }
    return items
  }
}
