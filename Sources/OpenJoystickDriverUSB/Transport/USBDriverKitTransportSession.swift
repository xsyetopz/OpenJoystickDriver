import IOKit
public import OpenJoystickDriverKit
import SwifterKit

/// The raw USB session of one opened extension service.
actor USBDriverKitTransportSession: USBTransportSession {
  /// The driver context that carries the transfers.
  private let context: DriverContext
  /// The transfers awaiting their completion event; closing it closes the driver runtime.
  private let transfers: USBDriverKitPendingTransfers
  /// One event subscription serves both IN and OUT requests on this connection.
  private var eventTask: Task<Void, Never>?
  /// Whether the session is closed.
  private var isClosed = false
  /// Picks the timeout each transfer passes to the pipe.
  private let timeoutPolicy: USBPipeTimeoutPolicy

  /// Exclusive while the session is open, and unknown after it closes.
  var inputOwnership: HIDInputOwnership {
    get async { await transfers.isClosed ? .unknown : .exclusive }
  }

  /// Creates the session over `context`, which `closeRuntime` shuts down.
  init(context: DriverContext, closeRuntime: @escaping @Sendable () async -> Void) {
    self.context = context
    transfers = USBDriverKitPendingTransfers(closeRuntime: closeRuntime)
    timeoutPolicy = USBPipeTimeoutPolicy { endpoint in
      try await context.usbPipeDescriptors(endpoint: endpoint).endpoint.attributes
    }
  }

  /// Registers notifications before any asynchronous request can complete.
  func startEvents(runtime: DriverRuntimeConnection) async throws {
    let events = try await runtime.events()
    let pending = transfers
    eventTask = Task {
      do {
        for try await event in events {
          if case .pipeIO(let completion) = try event.usb() {
            await pending.receive(completion)
          }
        }
      } catch {
        await pending.close(error: USBDriverKitTransportProvider.transportError(error))
        return
      }
      await pending.close(error: .disconnected)
    }
  }

  /// Writes `data` to the endpoint `endpoint` and returns the number of bytes written.
  ///
  /// - Throws: ``USBTransportError/disconnected`` when the session is closed, and the mapped driver
  ///   error otherwise.
  func write(endpoint: UInt8, data: [UInt8], timeout: UInt32) async throws -> Int {
    guard !isClosed else { throw USBTransportError.disconnected }
    do {
      _ = try DriverCommand.usbEnqueueWrite(endpoint: endpoint, data: data, timeout: 0)
      let completion = try await transfer(endpoint: endpoint, timeout: timeout) { pipeTimeout in
        try await self.context.usbEnqueueWrite(
          endpoint: endpoint,
          data: data,
          timeout: pipeTimeout
        )
      }
      return Int(completion.bytesTransferred)
    } catch { throw USBDriverKitTransportProvider.transportError(error) }
  }

  /// Reads up to `length` bytes from the endpoint `endpoint`.
  ///
  /// - Throws: ``USBTransportError/disconnected`` when the session is closed, and the mapped driver
  ///   error otherwise.
  func read(endpoint: UInt8, length: Int, timeout: UInt32) async throws -> [UInt8] {
    guard !isClosed else { throw USBTransportError.disconnected }
    do {
      _ = try DriverCommand.usbEnqueueRead(endpoint: endpoint, length: length, timeout: 0)
      let completion = try await transfer(endpoint: endpoint, timeout: timeout) { pipeTimeout in
        try await self.context.usbEnqueueRead(
          endpoint: endpoint,
          length: length,
          timeout: pipeTimeout
        )
      }
      guard completion.data.count <= length else { throw USBTransportError.notSupported }
      return completion.data
    } catch { throw USBDriverKitTransportProvider.transportError(error) }
  }

  /// Enqueues a transfer with the pipe timeout of `timeoutPolicy` and waits for its completion.
  ///
  /// A separate host deadline of `timeout` aborts a silent pipe, since an interrupt pipe carries no
  /// timeout of its own, without reconnecting a healthy controller.
  private func transfer(
    endpoint: UInt8,
    timeout: UInt32,
    enqueue: @Sendable (UInt32) async throws -> UInt32
  ) async throws -> USBPipeIOCompletion {
    try await transfers.checkOpen()
    let pipeTimeout = await timeoutPolicy.timeout(
      endpoint: endpoint,
      requestedMilliseconds: timeout
    )
    return try await withTaskCancellationHandler {
      try Task.checkCancellation()
      try await transfers.beginSubmission()
      let requestID: UInt32
      do {
        requestID = try await enqueue(pipeTimeout)
      } catch {
        await transfers.submissionFailed()
        throw error
      }
      return try await transfers.wait(requestID: requestID, timeout: timeout) {
        try await self.context.usbAbortPipe(endpoint: endpoint)
      }
    } onCancel: {
      Task { await self.transfers.close(error: .disconnected) }
    }
  }

  /// Sends the control transfer `request` and returns the bytes it received.
  ///
  /// A standard SET_INTERFACE goes through the driver's alternate-setting selection of the
  /// interface it names: the kernel's `IOUSBHostInterface` refuses it as a device request, as the
  /// raw USB route shows, and the matched interface 0 can't select a setting of interface 1.
  ///
  /// - Throws: ``USBTransportError/disconnected`` when the session is closed, and the mapped driver
  ///   error otherwise.
  @discardableResult
  func controlTransfer(
    _ request: USBControlTransferRequest,
    timeout: UInt32
  ) async throws -> [UInt8] {
    guard !isClosed else { throw USBTransportError.disconnected }
    try await transfers.checkOpen()
    do {
      if let selection = IOUSBHostTransportProvider.alternateSettingSelection(request) {
        try await context.usbSelectAlternateSetting(
          selection.setting,
          ofInterface: selection.interface
        )
        return []
      }
      return try await context.usbControlTransfer(
        USBDriverKitTransportProvider.controlRequest(for: request),
        data: request.outputData,
        timeout: timeout
      ).data
    } catch { throw USBDriverKitTransportProvider.transportError(error) }
  }

  /// Closes the session and the driver runtime connection.
  func close() async {
    guard !isClosed else { return }
    isClosed = true
    eventTask?.cancel()
    eventTask = nil
    await transfers.close(error: .disconnected)
  }
}
