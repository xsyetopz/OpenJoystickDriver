import Foundation

extension ApplicationServiceClient {
  /// Calls the RPC `method` with `arguments` and decodes the reply as `Value`.
  ///
  /// `closedWithoutReply` names the error for a connection that closes before the service replies.
  ///
  /// - Throws: ``ApplicationServiceClientError/notConnected`` before the client is connected, and
  ///   ``ApplicationServiceClientError/timeout`` when no reply arrives within `timeoutSeconds`.
  func call<Arguments: Encodable & Sendable, Value: Decodable & Sendable>(
    _ method: ApplicationServiceRPCMethod,
    _ arguments: Arguments,
    timeoutSeconds: TimeInterval = applicationServiceDefaultReplyTimeoutSeconds,
    closedWithoutReply: LocalServiceRPCClosedWithoutReply = .peerRejected
  ) async throws -> Value {
    guard stateLock.withLock({ connected }) else {
      throw ApplicationServiceClientError.notConnected
    }
    do {
      return try await LocalServiceRPCClient.call(
        method: method.rawValue,
        arguments: arguments,
        timeoutSeconds: timeoutSeconds,
        socketPath: socketPath,
        closedWithoutReply: closedWithoutReply
      )
    } catch LocalServiceRPCError.timeout { throw ApplicationServiceClientError.timeout }
  }

  /// Probes the local server every 100 ms until it answers or `deadline` passes; throws
  /// `CancellationError` when the calling task is cancelled.
  func waitForLocalServer(until deadline: Date) async throws -> Bool {
    let socketPath = self.socketPath
    let probe: @Sendable () -> Int32? = {
      LocalServiceRPCClient.serverProcessIdentifier(socketPath: socketPath)
    }
    while true {
      if (try? await BlockingWork.run(label: "com.openjoystickdriver.rpc.probe", probe)) != nil {
        stateLock.withLock { connected = true }
        return true
      }
      stateLock.withLock { unansweredProbes += 1 }
      if Date() >= deadline { return false }
      try await Task.sleep(nanoseconds: 100_000_000)
    }
  }
}
