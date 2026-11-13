import Darwin
import Foundation
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit

@Suite(.timeLimit(.minutes(2)), .removingTemporarySockets)
struct LocalServiceRPCCancellationTests {
  @Test(.timeLimit(.minutes(1)))
  func cancellingCallToSilentServerEndsPromptlyWithCancellationError() async throws {
    let socketPath = temporarySocketPath()
    let listener = try silentListener(socketPath: socketPath)
    defer {
      Darwin.close(listener)
      unsafe unlink(socketPath)
    }

    let task = Task {
      let _: String = try await LocalServiceRPCClient.call(
        method: "neverAnswered",
        arguments: LocalServiceRPCEmptyArguments(),
        timeoutSeconds: 30,
        socketPath: socketPath
      )
    }
    let connection = await acceptConnection(on: listener)
    defer { Darwin.close(connection) }

    task.cancel()
    await #expect(throws: CancellationError.self) { try await task.value }
  }

  @Test(.timeLimit(.minutes(1)))
  func cancellingConnectStopsRetryingAndLeavesClientDisconnected() async {
    let client = ApplicationServiceClient(socketPath: temporarySocketPath())
    // The connect deadline exceeds the test's time limit, so only the cancellation can end it.
    let task = Task { await client.connect(timeoutSeconds: 3600) }
    await waitUntil("the client has probed twice without an answer") {
      client.stateLock.withLock { client.unansweredProbes } >= 2
    }

    task.cancel()
    await task.value
    #expect(!client.isConnected)
  }

  /// Returns the descriptor of the next client connection to `listener`.
  private func acceptConnection(on listener: Int32) async -> Int32 {
    await withCheckedContinuation { continuation in
      DispatchQueue.global().async { continuation.resume(returning: accept(listener, nil, nil)) }
    }
  }

  /// A socket that accepts connections into its backlog but never reads or replies.
  private func silentListener(socketPath: String) throws -> Int32 {
    let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
    try #require(descriptor >= 0)
    var address = try LocalServiceRPCTransport.socketAddress(path: socketPath)
    let bound = withUnsafePointer(to: &address) {
      unsafe $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        unsafe bind(descriptor, $0, LocalServiceRPCTransport.socketAddressLength(path: socketPath))
      }
    }
    try #require(bound == 0)
    try #require(listen(descriptor, 4) == 0)
    return descriptor
  }

}
