import Foundation

extension ApplicationServiceClient {
  func call<Arguments: Encodable & Sendable, Value: Decodable & Sendable>(
    _ method: ApplicationServiceRPCMethod,
    _ arguments: Arguments,
    timeoutSeconds: TimeInterval = applicationServiceDefaultReplyTimeoutSeconds
  ) async throws -> Value {
    guard stateLock.withLock({ connected }) else {
      throw ApplicationServiceClientError.notConnected
    }
    do {
      return try await LocalServiceRPCClient.call(
        method: method.rawValue,
        arguments: arguments,
        timeoutSeconds: timeoutSeconds,
        socketPath: socketPath
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
      if Date() >= deadline { return false }
      try await Task.sleep(nanoseconds: 100_000_000)
    }
  }
}
