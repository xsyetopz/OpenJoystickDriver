import Darwin
import Foundation

extension LocalServiceRPCClient {
  /// Owns one call's descriptor.
  ///
  /// Cancellation shuts the socket down under the lock, so a blocked read or write returns at
  /// once; only the I/O thread closes the descriptor, so its number cannot be reused while
  /// cancellation still refers to it.
  final class CallState: @unchecked Sendable {
    /// Guards `descriptor` and `cancelled`.
    private let lock = NSLock()
    /// The call's socket; nil before ``install(_:)`` and after ``close()``.
    private var descriptor: Int32?
    /// Whether the call was cancelled.
    private var cancelled = false

    /// Whether the call was cancelled.
    var isCancelled: Bool { lock.withLock { cancelled } }

    /// Stores the call's socket; returns false when the call is already cancelled.
    func install(_ descriptor: Int32) -> Bool {
      lock.withLock {
        guard !cancelled else { return false }
        self.descriptor = descriptor
        return true
      }
    }

    /// Cancels the call and shuts down its socket, so a blocked read or write returns.
    func cancel() {
      lock.withLock {
        cancelled = true
        if let descriptor { shutdown(descriptor, SHUT_RDWR) }
      }
    }

    /// Closes the call's socket.
    func close() {
      lock.withLock {
        guard let descriptor else { return }
        self.descriptor = nil
        Darwin.close(descriptor)
      }
    }
  }

  /// Whether a server answers on the service's default socket.
  public static func isAvailable() -> Bool { serverProcessIdentifier() != nil }

  /// The process identifier of the server on the service's default socket; nil when none answers.
  public static func serverProcessIdentifier() -> Int32? {
    serverProcessIdentifier(socketPath: LocalServiceRPCTransport.defaultSocketPath)
  }

  /// The process identifier of the server on the socket at `socketPath`; nil when none answers
  /// within 0.2 s.
  package static func serverProcessIdentifier(socketPath: String) -> Int32? {
    guard
      let descriptor = try? LocalServiceRPCTransport.openConnectedSocket(
        timeoutSeconds: 0.2,
        socketPath: socketPath
      )
    else { return nil }
    defer { Darwin.close(descriptor) }
    var processIdentifier: pid_t = 0
    var size = socklen_t(MemoryLayout<pid_t>.size)
    guard unsafe getsockopt(descriptor, SOL_LOCAL, LOCAL_PEERPID, &processIdentifier, &size) == 0,
      processIdentifier > 0
    else { return nil }
    return processIdentifier
  }

  /// Calls `method` with `arguments` on the server at `socketPath` and decodes the result as
  /// `Value`.
  ///
  /// - Throws: ``LocalServiceRPCError``, ``ApplicationServiceRemappingRPCError`` when the response
  ///   carries a remapping failure, and `CancellationError` when the task is cancelled.
  static func call<Arguments: Encodable & Sendable, Value: Decodable & Sendable>(
    method: String,
    arguments: Arguments,
    timeoutSeconds: TimeInterval,
    socketPath: String = LocalServiceRPCTransport.defaultSocketPath,
    closedWithoutReply: LocalServiceRPCClosedWithoutReply = .peerRejected,
    as type: Value.Type = Value.self
  ) async throws -> Value {
    let requestData = try JSONEncoder().encode(
      LocalServiceRPCRequest(method: method, arguments: try JSONEncoder().encode(arguments))
    )
    let state = CallState()
    let responseData = try await withTaskCancellationHandler {
      try await BlockingWork.run(label: "com.openjoystickdriver.rpc.call") {
        try exchange(
          requestData,
          state: state,
          timeoutSeconds: timeoutSeconds,
          socketPath: socketPath,
          closedWithoutReply: closedWithoutReply
        )
      }
    } onCancel: {
      state.cancel()
    }
    let response = try JSONDecoder().decode(LocalServiceRPCResponse.self, from: responseData)
    if response.errorCode == .peerRejected { throw LocalServiceRPCError.peerRejected }
    if let error = response.remappingError { throw error }
    if let error = response.error { throw LocalServiceRPCError.remote(error) }
    guard let result = response.result else { throw LocalServiceRPCError.invalidFrame }
    return try JSONDecoder().decode(type, from: result)
  }

  /// Sends one request frame and reads its response frame, blocking the calling thread.
  private static func exchange(
    _ requestData: Data,
    state: CallState,
    timeoutSeconds: TimeInterval,
    socketPath: String,
    closedWithoutReply: LocalServiceRPCClosedWithoutReply
  ) throws -> Data {
    guard !state.isCancelled else { throw CancellationError() }
    let descriptor: Int32
    do {
      descriptor = try LocalServiceRPCTransport.openConnectedSocket(
        timeoutSeconds: timeoutSeconds,
        socketPath: socketPath
      )
    } catch {
      if state.isCancelled { throw CancellationError() }
      throw error
    }
    guard state.install(descriptor) else {
      Darwin.close(descriptor)
      throw CancellationError()
    }
    defer { state.close() }
    do {
      // A server that rejects the peer replies and closes without reading the request, so a
      // failed send still reads the reply that may be waiting. Darwin reports that closed peer
      // as EPIPE, ECONNRESET or, when the close lands during the send, ENOTCONN.
      var sendFailed = false
      do {
        try LocalServiceRPCTransport.sendFrame(requestData, to: descriptor)
      } catch LocalServiceRPCError.connectionFailed(let code)
        where code == EPIPE || code == ECONNRESET || code == ENOTCONN
      { sendFailed = true }
      let responseData: Data
      do {
        responseData = try LocalServiceRPCTransport.receiveFrame(
          from: descriptor,
          closedBeforeFrameError: closedWithoutReply.error
        )
      } catch  where sendFailed && !state.isCancelled { throw closedWithoutReply.error }
      guard !state.isCancelled else { throw CancellationError() }
      return responseData
    } catch {
      if state.isCancelled { throw CancellationError() }
      throw error
    }
  }
}
