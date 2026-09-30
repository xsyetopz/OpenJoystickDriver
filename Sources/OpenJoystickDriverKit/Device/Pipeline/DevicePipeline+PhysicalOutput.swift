extension DevicePipeline {
  func minimumPhysicalOutputIntervalNanoseconds() -> UInt64 {
    driver.sessionPlan.minimumHIDOutputIntervalNanoseconds
  }

  func defaultColor() -> ControllerColor? { driver.defaultColor }

  func encode(
    _ command: ControllerOutputCommand
  ) throws(ControllerOutputError) -> PhysicalOutputPlan { try driver.encode(command) }

  func hidKeepAlivePlan() -> (writes: [PhysicalOutputWrite], interval: UInt64)? {
    guard isActive, let interval = driver.sessionPlan.hidKeepAliveIntervalNanoseconds else {
      return nil
    }
    return (driver.keepAliveWrites(), interval)
  }

  /// Sends packets in order on the current USB session at `intervalNanoseconds` spacing,
  /// stopping at the first failure; a disconnected session is invalidated. Without a USB session,
  /// the packets go to the driver's USB command channel, if it has one.
  func sendUSBOutput(
    _ packets: [PhysicalUSBOutputPacket],
    intervalNanoseconds: UInt64 = 0
  ) async -> Bool {
    guard let handle = usbHandle else {
      return await sendUSBCommands(packets, intervalNanoseconds: intervalNanoseconds)
    }
    do {
      for (index, packet) in packets.enumerated() {
        if index > 0, intervalNanoseconds > 0 {
          try await Task.sleep(nanoseconds: intervalNanoseconds)
        }
        _ = try await writeUSBPacket(
          handle: handle,
          endpoint: packet.endpoint,
          data: packet.bytes,
          timeout: packet.timeoutMilliseconds
        )
      }
      return true
    } catch {
      if let error = error as? USBTransportError, error.isDisconnected {
        await invalidateUSBHandle(handle)
      }
      print("[DevicePipeline] Output send failed for \(identifier): \(error)")
      return false
    }
  }
}
