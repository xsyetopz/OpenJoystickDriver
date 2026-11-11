extension DevicePipeline {
  /// The least spacing between physical HID writes that the session plan names.
  func minimumPhysicalOutputIntervalNanoseconds() -> UInt64 {
    plan.minimumHIDOutputIntervalNanoseconds
  }

  /// The default colour of the controller from the driver; nil when it has none.
  func defaultColor() -> ControllerColor? { driver.defaultColor }

  /// Encodes `command` into the writes of the driver.
  ///
  /// - Throws: ``ControllerOutputError`` from the driver.
  func encode(
    _ command: ControllerOutputCommand
  ) throws(ControllerOutputError) -> PhysicalOutputPlan { try driver.encode(command) }

  /// Whether the template the driver encodes from, the record's or else the description's for the
  /// bound variant, names a resend interval.
  var resendsRumble: Bool {
    guard let binding else { return false }
    return binding.protocolID.rumbleTemplate(
      variant: binding.variant,
      record: binding.record?.rumbleTemplate
    )?.resendIntervalMilliseconds != nil
  }

  /// The spacing of HID keep-alive runs; nil while the session is inactive or the driver sends
  /// none over HID.
  func hidKeepAliveInterval() -> UInt64? {
    isActive ? plan.hidKeepAliveIntervalNanoseconds : nil
  }

  /// The writes of one HID keep-alive run, taken when the run is due so they reflect the driver's
  /// state then; nil while the session is inactive.
  func hidKeepAliveWrites() -> [PhysicalOutputWrite]? {
    isActive ? driver.keepAliveWrites() : nil
  }

  /// Sends packets in order on the current USB session at `intervalNanoseconds` spacing, stopping
  /// at the first failure; a disconnected session is invalidated.
  ///
  /// Without a USB session, the packets go to the driver's USB command channel, if it has one.
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
