import Foundation

extension DeviceManager {
  /// Writes one user-output plan inside the output queue operation of its command, so the whole
  /// plan is atomic. Each run of writes goes to the body its destination names: USB packets to
  /// the pipeline's USB session, HID output reports to ``performHIDOutputPlan`` with the output
  /// rate limit, and feature reports to ``performHIDFeatureReports``, both behind the native write
  /// gate. Stops at the first failed run.
  internal func performPhysicalOutputPlan(
    _ plan: PhysicalOutputPlan,
    for identifier: DeviceIdentifier,
    pipeline: DevicePipeline,
    detachedInfo: DeviceInfo?,
    in operation: PhysicalOutputQueueOperation
  ) async -> Bool {
    // Nothing to send (a Steam dongle without a controller) succeeds, except on a native
    // controller, whose executors refuse an empty batch.
    guard !plan.writes.isEmpty else { return pipeline.macOSOwnedOutput == nil }
    let writes = plan.writes
    var index = 0
    func run<Item>(_ item: (PhysicalOutputWrite) -> Item?) -> [Item] {
      var items: [Item] = []
      while index < writes.count, let next = item(writes[index]) {
        items.append(next)
        index += 1
      }
      return items
    }
    while index < writes.count {
      if index > 0, plan.intervalNanoseconds > 0 {
        do { try await Task.sleep(nanoseconds: plan.intervalNanoseconds) } catch { return false }
      }
      let sent: Bool
      switch writes[index] {
      case .usb:
        let packets = run { write -> PhysicalUSBOutputPacket? in
          guard case .usb(let packet, _) = write else { return nil }
          return packet
        }
        // A native controller is HID-only and receives no USB output.
        guard pipeline.macOSOwnedOutput == nil else { return false }
        sent = await pipeline.sendUSBOutput(packets, intervalNanoseconds: plan.intervalNanoseconds)
      case .hidOutput:
        let reports = run { write -> PhysicalHIDOutputReport? in
          guard case .hidOutput(let report) = write else { return nil }
          return report
        }
        guard let locationID = identifier.locationID else { return false }
        sent = await performHIDOutputPlan(
          reports,
          intervalNanoseconds: plan.intervalNanoseconds,
          locationID: locationID,
          identifier: identifier,
          pipeline: pipeline,
          startupConnection: nil,
          detachedInfo: detachedInfo,
          lifecycle: false,
          in: operation
        )
      case .hidFeature:
        let reports = run { write -> PhysicalHIDOutputReport? in
          guard case .hidFeature(let report) = write else { return nil }
          return report
        }
        guard let locationID = identifier.locationID else { return false }
        sent = await performHIDFeatureReports(
          reports,
          locationID: locationID,
          identifier: identifier,
          pipeline: pipeline,
          startupConnection: nil,
          detachedInfo: detachedInfo,
          lifecycle: false,
          in: operation
        )
      }
      guard sent else { return false }
    }
    return true
  }
}
