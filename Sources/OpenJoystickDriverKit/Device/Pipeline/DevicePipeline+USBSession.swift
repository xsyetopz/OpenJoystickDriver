import Foundation

/// The transfer timeout of a session step that names none, in milliseconds.
let usbSessionDefaultTimeoutMilliseconds: UInt32 = 1000

extension DevicePipeline {
  /// The session of the mode this pipeline runs; a pipeline without a record runs none.
  var recordSession: ControllerSession { binding?.record?.session ?? .none }

  /// Runs the mode's vendor control transfers in the order listed, each only when its `match` holds
  /// for `device`.
  ///
  /// A rejected transfer fails startup unless it tolerates rejection.
  func performControlTransfers(
    handle: any USBTransportSession,
    device: USBTransportDevice?,
    runGeneration: UInt64?
  ) async throws {
    for transfer in recordSession.controlTransfers
    where
      transfer.match.holds(
        manufacturer: device?.manufacturer,
        product: device?.productName,
        release: device?.deviceRelease
      )
    {
      guard isCurrentUSBOperation(runGeneration) else { throw CancellationError() }
      do {
        let reply = try await handle.controlTransfer(
          try transfer.request(),
          timeout: transfer.timeoutMilliseconds.map(UInt32.init)
            ?? usbSessionDefaultTimeoutMilliseconds
        )
        appendToPacketLog(
          bytes: transfer.isInput ? reply : transfer.data ?? [],
          direction: transfer.isInput ? .received : .transmitted
        )
      } catch let error as USBTransportError
        where transfer.toleratesRejection && error.isIgnorableForTolerantStep
      {
        print("[DevicePipeline] Optional control transfer rejected for \(identifier): \(error)")
      }
      if let delay = transfer.delayMilliseconds, delay > 0 {
        try await Task.sleep(
          nanoseconds: UInt64(delay) * DeviceTransportProfile.nanosecondsPerMillisecond
        )
        guard isCurrentUSBOperation(runGeneration) else { throw CancellationError() }
      }
    }
  }

  /// The interval of the mode's keep-alive, used when the family's description declares none.
  var sessionKeepAliveIntervalNanoseconds: UInt64? {
    recordSession.keepAlive.map {
      UInt64($0.intervalMilliseconds) * DeviceTransportProfile.nanosecondsPerMillisecond
    }
  }

  /// The packets of the mode's keep-alive.
  func sessionKeepAliveWrites() -> [PhysicalOutputWrite] {
    (recordSession.keepAlive?.writes ?? []).map {
      $0.output(
        defaultEndpoint: transportProfile.outputEndpoint,
        defaultTimeoutMilliseconds: Int(usbSessionDefaultTimeoutMilliseconds)
      )
    }
  }

  /// Sends the mode's shutdown packets.
  ///
  /// The session is closing, so a failed packet is logged and the rest still go out.
  func sendUSBShutdownWrites(handle: any USBTransportSession) async {
    await sendUSBClosingWrites(
      recordSession.shutdownWrites.map {
        $0.write(
          defaultEndpoint: transportProfile.outputEndpoint,
          defaultTimeoutMilliseconds: Int(usbSessionDefaultTimeoutMilliseconds)
        )
      },
      handle: handle
    )
  }

  /// Sends the driver's power-off packets.
  ///
  /// Only a deliberate stop calls this: an I/O error or an unplug closes through
  /// `invalidateUSBHandle`, because a transient error must not turn a controller off.
  func sendUSBPowerOffWrites(handle: any USBTransportSession) async {
    await sendUSBClosingWrites(driver.powerOffWrites(), handle: handle)
  }

  private func sendUSBClosingWrites(
    _ writes: [PhysicalOutputWrite],
    handle: any USBTransportSession
  ) async {
    for write in writes {
      guard case .usb(let packet, _) = write else { continue }
      do {
        try await handle.write(
          endpoint: packet.endpoint,
          data: packet.bytes,
          timeout: packet.timeoutMilliseconds
        )
        appendToPacketLog(bytes: packet.bytes, direction: .transmitted)
      } catch { print("[DevicePipeline] Shutdown write failed for \(identifier): \(error)") }
    }
  }
}

extension USBTransportError {
  /// Whether a step that tolerates rejection skips this failure.
  var isIgnorableForTolerantStep: Bool {
    switch self {
    case .inputOutput, .notFound, .notSupported, .timeout: true
    default: false
    }
  }
}
