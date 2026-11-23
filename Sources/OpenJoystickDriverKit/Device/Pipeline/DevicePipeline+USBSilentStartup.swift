import Foundation

/// The most toggle resets one USB session tries on a pad that stays silent after startup.
let usbSilentStartupRecoveryLimit = 2

extension DevicePipeline {
  /// Sends the plan's standard control requests in order.
  ///
  /// A request the device or host rejects is logged and skipped: the requests help some pads start
  /// and are not a precondition of any.
  ///
  /// - Throws: ``CancellationError`` when the run changes, and
  ///   ``USBTransportError/disconnected`` when the device goes away.
  func performStandardStartupRequests(
    handle: any USBTransportSession,
    runGeneration: UInt64?
  ) async throws {
    for request in plan.usbStartupStandardRequests {
      guard isCurrentUSBOperation(runGeneration) else { throw CancellationError() }
      do {
        try await handle.controlTransfer(request, timeout: usbSessionDefaultTimeoutMilliseconds)
      } catch let error as USBTransportError where !error.isDisconnected {
        print("[DevicePipeline] Standard startup request rejected for \(identifier): \(error)")
      }
    }
  }

  /// Resets the data toggles of the input and output endpoints and sends the startup writes again,
  /// for a pad that sent nothing after its startup writes.
  ///
  /// A pad whose toggle disagrees with the host's drops the first OUT packet as a repeat, so it
  /// never receives POWER ON and stays dark and silent (#59, #67).
  ///
  /// The endpoint reset ends any pending read, so an IN read is armed again before the writes, as
  /// at startup.
  ///
  /// - Returns: The armed read for the input loop to take as its next read, or nil when the session
  ///   cannot reset the toggles or the recovery failed, so the caller stops trying.
  func recoverSilentUSBStartup(
    handle: any USBTransportSession,
    generation: UInt64
  ) async -> Task<[UInt8], any Error>? {
    print("[DevicePipeline] No input after startup; resetting endpoint toggles: \(identifier)")
    do {
      for endpoint in [transportProfile.outputEndpoint, transportProfile.inputEndpoint] {
        try await handle.resynchronizeEndpoint(
          endpoint,
          timeout: usbSessionDefaultTimeoutMilliseconds
        )
      }
      guard isCurrentUSBRun(generation) else { return nil }
      try await performStandardStartupRequests(handle: handle, runGeneration: generation)
      let read = await armInputRead(handle: handle)
      do {
        try await sendUSBStartupOutputPackets(handle: handle, runGeneration: generation)
      } catch {
        read.cancel()
        throw error
      }
      return read
    } catch let error as USBTransportError where error == .notSupported {
      return nil
    } catch {
      print("[DevicePipeline] Silent startup recovery failed for \(identifier): \(error)")
      return nil
    }
  }
}
