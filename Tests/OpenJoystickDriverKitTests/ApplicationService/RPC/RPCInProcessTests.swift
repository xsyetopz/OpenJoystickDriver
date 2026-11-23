import Darwin
import Foundation
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit

/// A client in the server's own process reaches the handler without the socket.
@Suite(.serialized, .timeLimit(.minutes(2)), .removingTemporarySockets)
struct LocalServiceRPCInProcessTests {
  /// Counts the connections the server accepts.
  private final class AcceptCounter: Sendable {
    let count = Locked(0)

    func accept(_ socket: Int32) -> Int32 {
      count.withLock { $0 += 1 }
      return Darwin.accept(socket, nil, nil)
    }
  }

  /// A server on a temporary socket that answers "ok", runs `handler` first, and counts accepts.
  private func makeServer(
    inProcess: Bool,
    authentication: @escaping LocalServiceRPCServer.Authentication = { _ in true },
    handler: @escaping @Sendable (LocalServiceRPCRequest) async -> Void
  ) -> (LocalServiceRPCServer, AcceptCounter) {
    let server = LocalServiceRPCServer(
      socketPath: temporarySocketPath(),
      authentication: authentication
    ) { request in
      await handler(request)
      return LocalServiceRPCResponse(result: try? JSONEncoder().encode("ok"), error: nil)
    }
    let counter = AcceptCounter()
    server.acceptConnection = { counter.accept($0) }
    server.servesClientsInProcess = inProcess
    return (server, counter)
  }

  private func call(
    _ method: String,
    on server: LocalServiceRPCServer,
    timeoutSeconds: TimeInterval = 10
  ) async throws -> String {
    try await LocalServiceRPCClient.call(
      method: method,
      arguments: LocalServiceRPCEmptyArguments(),
      timeoutSeconds: timeoutSeconds,
      socketPath: server.socketPath
    )
  }

  @Test
  func inProcessCallAnswersWithoutConnectionAndAuthenticatesThisProcess() async throws {
    let peers = Locked<[pid_t]>([])
    let record: LocalServiceRPCServer.Authentication = { peer in
      peers.withLock { $0.append(peer.processIdentifier) }
      return true
    }
    let (server, counter) = makeServer(inProcess: true, authentication: record) { _ in }
    try server.start()
    defer { server.stop() }

    let result = try await call("echo", on: server)

    #expect(result == "ok")
    #expect(counter.count.withLock { $0 } == 0)
    #expect(peers.withLock { $0 } == [getpid()])
  }

  @Test
  func serverThatDoesNotServeInProcessAnswersOverTheSocket() async throws {
    let (server, counter) = makeServer(inProcess: false) { _ in }
    try server.start()
    defer { server.stop() }

    #expect(try await call("echo", on: server) == "ok")
    #expect(counter.count.withLock { $0 } == 1)
  }

  @Test
  func rejectedInProcessCallerIsReportedAndHandlerNeverRuns() async throws {
    let ran = Locked(false)
    let rejectAll: LocalServiceRPCServer.Authentication = { _ in false }
    let (server, _) = makeServer(inProcess: true, authentication: rejectAll) { _ in
      ran.withLock { $0 = true }
    }
    try server.start()
    defer { server.stop() }

    await #expect(throws: LocalServiceRPCError.peerRejected) {
      _ = try await call("rejected", on: server)
    }
    #expect(!ran.withLock { $0 })
  }

  @Test(.timeLimit(.minutes(1)))
  func slowRequestTimesOutAndStillRunsToCompletion() async throws {
    // The handler holds until the caller has timed out, so a late deadline under load cannot let
    // the response arrive first.
    let (release, releaseSignal) = AsyncStream.makeStream(of: Void.self)
    let (finished, finishedSignal) = AsyncStream.makeStream(of: Void.self)
    let (server, _) = makeServer(inProcess: true) { _ in
      for await _ in release { break }
      if !Task.isCancelled { finishedSignal.yield() }
    }
    try server.start()
    defer { server.stop() }

    await #expect(throws: LocalServiceRPCError.timeout) {
      _ = try await call("slow", on: server, timeoutSeconds: 0.1)
    }
    releaseSignal.yield()
    var completed = false
    for await _ in finished {
      completed = true
      break
    }
    #expect(completed)
  }

  @Test
  func cancellingHeldInProcessRequestCancelsItsHandler() async throws {
    let (received, receivedSignal) = AsyncStream.makeStream(of: Void.self)
    let (handlerCancelled, cancelledSignal) = AsyncStream.makeStream(of: Bool.self)
    let held = ApplicationServiceRPCMethod.waitForServiceStatusChange.rawValue
    let (server, _) = makeServer(inProcess: true) { request in
      guard request.method == held else { return }
      receivedSignal.yield()
      try? await Task.sleep(nanoseconds: 30_000_000_000)
      cancelledSignal.yield(Task.isCancelled)
    }
    try server.start()
    defer { server.stop() }

    let task = Task { try await call(held, on: server) }
    for await _ in received { break }
    task.cancel()

    await #expect(throws: CancellationError.self) { try await task.value }
    var wasCancelled = false
    for await cancelled in handlerCancelled {
      wasCancelled = cancelled
      break
    }
    #expect(wasCancelled)
    #expect(try await call("afterCancellation", on: server) == "ok")
  }

  @Test
  func stoppedServerIsNotReachedInProcess() async throws {
    let (server, _) = makeServer(inProcess: true) { _ in }
    try server.start()
    server.stop()

    #expect(LocalServiceRPCServer.inProcessServer(socketPath: server.socketPath) == nil)
    await #expect(throws: LocalServiceRPCError.self) { _ = try await call("echo", on: server) }
  }
}
