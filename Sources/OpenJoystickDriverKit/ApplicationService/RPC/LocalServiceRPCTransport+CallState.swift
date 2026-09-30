import Darwin
import Foundation

extension LocalServiceRPCClient {
  /// Owns one call's descriptor. Cancellation shuts the socket down under the lock, so a blocked
  /// read or write returns at once; only the I/O thread closes the descriptor, so its number
  /// cannot be reused while cancellation still refers to it.
  final class CallState: @unchecked Sendable {
    private let lock = NSLock()
    private var descriptor: Int32?
    private var cancelled = false

    var isCancelled: Bool { lock.withLock { cancelled } }

    func install(_ descriptor: Int32) -> Bool {
      lock.withLock {
        guard !cancelled else { return false }
        self.descriptor = descriptor
        return true
      }
    }

    func cancel() {
      lock.withLock {
        cancelled = true
        if let descriptor { shutdown(descriptor, SHUT_RDWR) }
      }
    }

    func close() {
      lock.withLock {
        guard let descriptor else { return }
        self.descriptor = nil
        Darwin.close(descriptor)
      }
    }
  }

  public static func isAvailable() -> Bool { serverProcessIdentifier() != nil }

  public static func serverProcessIdentifier() -> Int32? {
    serverProcessIdentifier(socketPath: LocalServiceRPCTransport.defaultSocketPath)
  }

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
    guard getsockopt(descriptor, SOL_LOCAL, LOCAL_PEERPID, &processIdentifier, &size) == 0,
      processIdentifier > 0
    else { return nil }
    return processIdentifier
  }

  static func call<Arguments: Encodable & Sendable, Value: Decodable & Sendable>(
    method: String,
    arguments: Arguments,
    timeoutSeconds: TimeInterval,
    socketPath: String = LocalServiceRPCTransport.defaultSocketPath,
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
          socketPath: socketPath
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
    socketPath: String
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
      do {
        try LocalServiceRPCTransport.sendFrame(requestData, to: descriptor)
      } catch LocalServiceRPCError.connectionFailed(let code)
        where code == EPIPE || code == ECONNRESET
      { throw LocalServiceRPCError.peerRejected }
      let responseData = try LocalServiceRPCTransport.receiveFrame(
        from: descriptor,
        closedBeforeFrameError: .peerRejected
      )
      guard !state.isCancelled else { throw CancellationError() }
      return responseData
    } catch {
      if state.isCancelled { throw CancellationError() }
      throw error
    }
  }
}
