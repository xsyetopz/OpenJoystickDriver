import Foundation
import IOKit
import IOUSBHost
import OpenJoystickDriverKit

// `@unchecked Sendable` because `IOUSBHostPipe` is not annotated `Sendable`, and awaiting its
// nonisolated `enqueueIORequest` sends it out of the session actor. Only the session actor
// creates, aborts, and drops pipes; the box carries one across that single await.
/// A box that carries an `IOUSBHostPipe` across the one await that sends it out of the session
/// actor.
final class IOUSBHostPipeBox: @unchecked Sendable {
  /// The boxed pipe.
  let pipe: IOUSBHostPipe
  /// Boxes `pipe`.
  init(_ pipe: IOUSBHostPipe) { self.pipe = pipe }
}

/// The raw USB session of one opened IOUSBHost interface.
actor IOUSBHostTransportSession: USBTransportSession {
  /// The opened interface.
  private let interface: IOUSBHostInterface
  /// The device the interface belongs to.
  private let device: USBTransportDevice
  /// The number of the opened interface.
  private let interfaceNumber: UInt8
  /// The other interfaces of the device opened to select an alternate setting, by number; each
  /// stays open until the session closes, so the device keeps the setting.
  private var siblings: [UInt8: IOUSBHostInterface] = [:]
  /// The pipes opened so far, by endpoint address.
  private var pipes: [UInt8: IOUSBHostPipeBox] = [:]
  /// Whether the session is closed.
  private var isClosed = false
  /// Whether the interface has been destroyed.
  private var isDestroyed = false
  // Actor methods are reentrant at every `await`, so `close()` can run while a transfer is
  // suspended. The interface owns the `ioData` buffers, so it is destroyed only once no
  // transfer is in flight.
  /// The number of transfers that are in flight.
  private var inFlightTransfers = 0
  // Allocating an `ioData` buffer is a kernel call, as costly as the transfer itself, and an
  // input endpoint is read once per report. A read takes a free buffer of its length here and
  // returns it once the bytes are copied out; reads that overlap each take their own.
  /// The free read buffers, by length.
  private var readBuffers: [Int: [NSMutableData]] = [:]
  /// The most free buffers kept for one length.
  private static let readBufferLimit = 2

  /// Exclusive while the session is open, and unknown after it closes.
  var inputOwnership: HIDInputOwnership { isClosed ? .unknown : .exclusive }

  /// Creates the session for `interface`, number `interfaceNumber` of `device`.
  init(interface: IOUSBHostInterface, device: USBTransportDevice, interfaceNumber: UInt8) {
    self.interface = interface
    self.device = device
    self.interfaceNumber = interfaceNumber
  }

  /// Writes `data` to the OUT endpoint `endpoint` and returns the number of bytes written.
  ///
  /// - Throws: ``USBTransportError/disconnected`` when the session is closed,
  ///   ``USBTransportError/notSupported`` for an endpoint that is not OUT or for empty data, and
  ///   the mapped IOUSBHost error otherwise.
  func write(endpoint: UInt8, data: [UInt8], timeout: UInt32) async throws -> Int {
    guard !isClosed else { throw USBTransportError.disconnected }
    guard USBEndpointDirection(endpointAddress: endpoint) == .out, !data.isEmpty else {
      throw USBTransportError.notSupported
    }
    beginTransfer()
    defer { endTransfer() }
    do {
      let buffer = try interface.ioData(withCapacity: data.count)
      Self.copy(data, into: buffer)
      return try await transfer(endpoint: endpoint, buffer: buffer, timeout: timeout)
    } catch { throw closeIfDisconnected(error) }
  }

  /// Reads up to `length` bytes from the IN endpoint `endpoint`.
  ///
  /// - Throws: ``USBTransportError/disconnected`` when the session is closed,
  ///   ``USBTransportError/notSupported`` for an endpoint that is not IN or for a length of zero,
  ///   and the mapped IOUSBHost error otherwise.
  func read(endpoint: UInt8, length: Int, timeout: UInt32) async throws -> [UInt8] {
    guard !isClosed else { throw USBTransportError.disconnected }
    guard USBEndpointDirection(endpointAddress: endpoint) == .in, length > 0 else {
      throw USBTransportError.notSupported
    }
    beginTransfer()
    defer { endTransfer() }
    do {
      let buffer = try readBuffer(length: length)
      let count = try await transfer(endpoint: endpoint, buffer: buffer, timeout: timeout)
      guard !isClosed else { throw USBTransportError.disconnected }
      let bytes = unsafe Array(
        UnsafeRawBufferPointer(start: buffer.bytes, count: min(count, buffer.length))
      )
      recycle(buffer, length: length)
      return bytes
    } catch { throw closeIfDisconnected(error) }
  }

  /// A free read buffer of `length` bytes, or a new one when none is free.
  private func readBuffer(length: Int) throws -> NSMutableData {
    if let buffer = readBuffers[length]?.popLast() { return buffer }
    return try interface.ioData(withCapacity: length)
  }

  /// Keeps `buffer` for the next read of `length` bytes while the session is open.
  private func recycle(_ buffer: NSMutableData, length: Int) {
    guard !isClosed, readBuffers[length, default: []].count < Self.readBufferLimit else { return }
    readBuffers[length, default: []].append(buffer)
  }

  /// Sends the control transfer `request` and returns the bytes it received.
  ///
  /// A standard SET_INTERFACE goes through `selectAlternateSetting` of the interface it names,
  /// since IOUSBHost refuses it as a device request.
  ///
  /// - Throws: ``USBTransportError/disconnected`` when the session is closed,
  ///   ``USBTransportError/notFound`` when SET_INTERFACE names an interface the registry does not
  ///   list, and the mapped IOUSBHost error otherwise.
  @discardableResult
  func controlTransfer(
    _ request: USBControlTransferRequest,
    timeout: UInt32
  ) async throws -> [UInt8] {
    guard !isClosed else { throw USBTransportError.disconnected }
    if let selection = IOUSBHostTransportProvider.alternateSettingSelection(request) {
      try selectAlternateSetting(selection.setting, ofInterface: selection.interface)
      return []
    }
    beginTransfer()
    defer { endTransfer() }
    do {
      let buffer: NSMutableData?
      switch request.dataStage {
      case .none: buffer = nil
      case .output(let data):
        let output = try interface.ioData(withCapacity: data.count)
        Self.copy(data, into: output)
        buffer = output
      case .input(let length): buffer = try interface.ioData(withCapacity: Int(length))
      }
      let (status, count) = try await interface.completedDeviceRequest(
        IOUSBHostTransportProvider.deviceRequest(for: request),
        data: buffer,
        completionTimeout: IOUSBHostTransportProvider.completionTimeout(milliseconds: timeout)
      )
      guard !isClosed else { throw USBTransportError.disconnected }
      guard status == kIOReturnSuccess else {
        throw IOUSBHostTransportProvider.transportError(status)
      }
      guard request.direction == .in, let buffer else { return [] }
      return unsafe Array(Data(bytes: buffer.bytes, count: min(count, buffer.length)))
    } catch { throw closeIfDisconnected(error) }
  }

  /// Sends `CLEAR_FEATURE(ENDPOINT_HALT)` for `endpoint`, which resets the device's data toggle
  /// (USB 2.0 9.4.5), then clears the host pipe's halt, which resets the host's toggle and aborts
  /// the pipe's pending transfers.
  ///
  /// A device that rejects the request still has the host side reset.
  ///
  /// - Throws: ``USBTransportError/disconnected`` when the session is closed, and the mapped
  ///   IOUSBHost error of the pipe otherwise.
  func resynchronizeEndpoint(_ endpoint: UInt8, timeout: UInt32) async throws {
    guard !isClosed else { throw USBTransportError.disconnected }
    let pipe = try pipe(for: endpoint)
    let clearHalt = try USBControlTransferRequest(
      kind: .standard,
      recipient: .endpoint,
      request: 0x01,
      index: UInt16(endpoint)
    )
    // The host's `clearStall` may send the same request; a device that stalls this one still has
    // its toggle reset by that one, so a rejection here does not end the reset.
    do { try await controlTransfer(clearHalt, timeout: timeout) } catch let error
      as USBTransportError
    { guard !error.isDisconnected else { throw error } }
    guard !isClosed else { throw USBTransportError.disconnected }
    do { try pipe.pipe.clearStall() } catch { throw closeIfDisconnected(error) }
  }

  /// Selects `setting` on the interface `number` of the device with SET_INTERFACE.
  ///
  /// Selecting on the session's own interface closes its pipes, which reopen on their next use.
  private func selectAlternateSetting(_ setting: UInt8, ofInterface number: UInt8) throws {
    do {
      guard number != interfaceNumber else {
        pipes.removeAll()
        try interface.selectAlternateSetting(Int(setting))
        return
      }
      try sibling(number).selectAlternateSetting(Int(setting))
    } catch { throw closeIfDisconnected(error) }
  }

  /// Returns the interface `number` of the device, opening it on first use.
  private func sibling(_ number: UInt8) throws -> IOUSBHostInterface {
    if let sibling = siblings[number] { return sibling }
    guard
      let service = try IOUSBHostTransportProvider.interfaceService(
        for: device,
        interfaceNumber: number
      )
    else { throw USBTransportError.notFound }
    defer { IOObjectRelease(service) }
    let sibling = try IOUSBHostTransportProvider.openInterface(
      service: service,
      device: device,
      interfaceNumber: number
    )
    siblings[number] = sibling
    return sibling
  }

  /// Aborts the pipes, closes the sibling interfaces, and destroys the interface once no transfer
  /// is in flight.
  func close() {
    guard !isClosed else { return }
    isClosed = true
    for sibling in siblings.values { sibling.destroy() }
    siblings.removeAll()
    for box in pipes.values { try? box.pipe.__abort(with: .synchronous) }
    pipes.removeAll()
    readBuffers.removeAll()
    destroyInterfaceIfIdle()
  }

  /// Counts a transfer as in flight.
  private func beginTransfer() { inFlightTransfers += 1 }

  /// Counts a transfer as finished and destroys the interface if the session is closed and idle.
  private func endTransfer() {
    inFlightTransfers -= 1
    destroyInterfaceIfIdle()
  }

  /// Destroys the interface when the session is closed and no transfer is in flight.
  private func destroyInterfaceIfIdle() {
    guard isClosed, inFlightTransfers == 0, !isDestroyed else { return }
    isDestroyed = true
    interface.destroy()
  }

  /// Runs one transfer of `buffer` on the pipe of `endpoint` and returns the byte count.
  ///
  /// A pipe that takes no completion timeout is aborted at the host deadline instead, which ends
  /// the transfer with ``USBTransportError/timeout``.
  private func transfer(endpoint: UInt8, buffer: NSMutableData, timeout: UInt32) async throws -> Int
  {
    let pipe = try pipe(for: endpoint)
    let attributes = unsafe pipe.pipe.descriptors.pointee.descriptor.bmAttributes
    let deadline = IOUSBHostTransportProvider.hostDeadlineMilliseconds(
      endpointAttributes: attributes,
      milliseconds: timeout
    ).map { milliseconds in
      Task { [weak self] in
        // A cancelled sleep means the transfer completed first.
        do { try await Task.sleep(nanoseconds: UInt64(milliseconds) * 1_000_000) } catch { return }
        await self?.abortExpiredTransfers(on: endpoint)
      }
    }
    defer { deadline?.cancel() }
    do {
      let result = try await pipe.pipe.completedIORequest(
        with: buffer,
        completionTimeout: IOUSBHostTransportProvider.pipeCompletionTimeout(
          endpointAttributes: attributes,
          milliseconds: timeout
        )
      )
      guard result.0 == kIOReturnSuccess else {
        throw IOUSBHostTransportProvider.transportError(result.0)
      }
      return result.1
    } catch let error as USBTransportError { throw error } catch {
      throw IOUSBHostTransportProvider.transportError(error)
    }
  }

  // A deadline cancelled before it reaches the actor does nothing. One that reaches it as its
  // transfer completes finds no pending transfer, or ends an overlapping one on the same pipe as a
  // timeout, which callers already treat as an idle interval.
  /// Aborts the pending transfers of `endpoint`, which complete with `kIOReturnAborted`.
  private func abortExpiredTransfers(on endpoint: UInt8) {
    guard !Task.isCancelled, !isClosed, let box = pipes[endpoint] else { return }
    try? box.pipe.__abort(with: .asynchronous)
  }

  /// Copies `data` into `buffer`.
  private static func copy(_ data: [UInt8], into buffer: NSMutableData) {
    data.withUnsafeBytes { source in
      guard let baseAddress = source.baseAddress else { return }
      unsafe buffer.mutableBytes.copyMemory(from: baseAddress, byteCount: source.count)
    }
  }

  /// Maps `error` to a transport error and closes the session when it means a disconnect.
  private func closeIfDisconnected(_ error: any Error) -> USBTransportError {
    let transportError =
      error as? USBTransportError ?? IOUSBHostTransportProvider.transportError(error)
    if transportError.isDisconnected { close() }
    return transportError
  }

  /// Returns the pipe of `endpoint`, opening it on first use.
  private func pipe(for endpoint: UInt8) throws -> IOUSBHostPipeBox {
    if let pipe = pipes[endpoint] { return pipe }
    do {
      let pipe = IOUSBHostPipeBox(try interface.copyPipe(withAddress: Int(endpoint)))
      pipes[endpoint] = pipe
      return pipe
    } catch { throw IOUSBHostTransportProvider.transportError(error) }
  }
}
