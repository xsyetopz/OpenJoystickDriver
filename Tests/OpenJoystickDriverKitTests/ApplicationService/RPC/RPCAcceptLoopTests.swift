import Darwin
import Foundation
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit

private final class Counter: @unchecked Sendable {
  private let lock = NSLock()
  private var value = 0

  /// The count before this call.
  func next() -> Int {
    lock.withLock {
      defer { value += 1 }
      return value
    }
  }
  var count: Int { lock.withLock { value } }
}

private final class Reports: @unchecked Sendable {
  private let lock = NSLock()
  private var lines: [String] = []

  func add(_ line: String) { lock.withLock { lines.append(line) } }
  var all: [String] { lock.withLock { lines } }
}

private final class Changes: @unchecked Sendable {
  private let lock = NSLock()
  private var values: [ServiceListenerFailure?] = []

  func add(_ failure: ServiceListenerFailure?) { lock.withLock { values.append(failure) } }
  var all: [ServiceListenerFailure?] { lock.withLock { values } }
}

@Suite(.serialized, .removingTemporarySockets)
struct RPCAcceptLoopTests {
  private func makeServer(
    generation: Int = 0,
    socketPath: String = temporarySocketPath()
  ) -> LocalServiceRPCServer {
    LocalServiceRPCServer(
      socketPath: socketPath,
      authentication: { _ in true },
      handler: { _ in
        return LocalServiceRPCResponse(result: try? JSONEncoder().encode(generation), error: nil)
      }
    )
  }

  private func call(_ server: LocalServiceRPCServer) async throws -> Int {
    try await LocalServiceRPCClient.call(
      method: "generation",
      arguments: "",
      timeoutSeconds: 10,
      socketPath: server.socketPath
    )
  }

  /// Connects and leaves the connection open, which makes the listening socket readable.
  private func connect(_ server: LocalServiceRPCServer) throws -> Int32 {
    let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
    try #require(descriptor >= 0)
    var address = try LocalServiceRPCTransport.socketAddress(path: server.socketPath)
    let status = withUnsafePointer(to: &address) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        Darwin.connect(
          descriptor,
          $0,
          LocalServiceRPCTransport.socketAddressLength(path: server.socketPath)
        )
      }
    }
    try #require(status == 0)
    return descriptor
  }

  private func waitForExit(_ exited: DispatchSemaphore, seconds: Double = 10) async throws -> Bool {
    try await BlockingWork.run(label: "rpc-test-wait") {
      exited.wait(timeout: .now() + seconds) == .success
    }
  }

  @Test
  func stoppingEndsTheAcceptLoopAfterItClosedItsDescriptors() async throws {
    let server = makeServer()
    let exited = DispatchSemaphore(value: 0)
    server.acceptLoopDidExit = { exited.signal() }
    try server.start()
    server.stop()
    server.stop()

    #expect(try await waitForExit(exited))
    #expect(LocalServiceRPCClient.serverProcessIdentifier(socketPath: server.socketPath) == nil)
  }

  @Test
  func startingARunningServerIsRefused() throws {
    let server = makeServer()
    try server.start()
    defer { server.stop() }

    #expect(throws: LocalServiceRPCError.alreadyRunning) { try server.start() }
  }

  @Test
  func aStopDuringStartLeavesTheServerStoppedAndRestartable() async throws {
    let server = makeServer(generation: 9)
    let exited = DispatchSemaphore(value: 0)
    server.acceptLoopDidExit = { exited.signal() }
    server.beforeListenerPublished = { [weak server] in
      server?.stop()
      // A start while the first still runs is refused.
      #expect(throws: LocalServiceRPCError.alreadyRunning) { try server?.start() }
    }
    try server.start()

    #expect(try await waitForExit(exited))
    #expect(!FileManager.default.fileExists(atPath: server.socketPath))
    server.beforeListenerPublished = nil
    try server.start()
    defer { server.stop() }
    #expect(try await call(server) == 9)
  }

  @Test
  func onlyOneOfTwoConcurrentStartsSucceeds() async throws {
    for _ in 0..<20 {
      let server = makeServer()
      let outcomes = await withTaskGroup(of: Bool.self) { group in
        for _ in 0..<4 {
          group.addTask { (try? server.start()) != nil }
        }
        var started = 0
        for await ok in group where ok { started += 1 }
        return started
      }
      server.stop()
      #expect(outcomes == 1)
    }
  }

  @Test
  func anOldLoopThatExitsLateDoesNotEndTheNewestStart() async throws {
    let server = makeServer(generation: 7)
    let exits = Counter()
    server.acceptLoopDidExit = { _ = exits.next() }
    let cycles = 30
    for _ in 0..<cycles {
      try server.start()
      server.stop()
    }
    try server.start()
    defer { server.stop() }

    await waitUntil("the stopped loops exit") { exits.count == cycles }
    #expect(try await call(server) == 7)
    #expect(FileManager.default.fileExists(atPath: server.socketPath))
  }

  @Test
  func aLoopThatRanOutOfResourcesReportsItWaitsAndAcceptsAgain() async throws {
    let server = makeServer(generation: 3)
    let attempts = Counter()
    let reports = Reports()
    server.resourceWaitMilliseconds = 20
    server.report = reports.add
    server.acceptConnection = { descriptor in
      if attempts.next() == 0 {
        errno = EMFILE
        return -1
      }
      return Darwin.accept(descriptor, nil, nil)
    }
    try server.start()
    defer { server.stop() }

    #expect(try await call(server) == 3)
    let line = try #require(reports.all.first)
    #expect(line.contains("Cannot accept connections"))
    #expect(line.contains("retrying in 20 ms"))
  }

  @Test
  func stoppingEndsTheWaitForResourcesAtOnce() async throws {
    let server = makeServer()
    let reports = Reports()
    let exited = DispatchSemaphore(value: 0)
    server.resourceWaitMilliseconds = 600_000
    server.report = reports.add
    server.acceptLoopDidExit = { exited.signal() }
    server.acceptConnection = { _ in
      errno = EMFILE
      return -1
    }
    try server.start()
    let client = try connect(server)
    defer { Darwin.close(client) }
    await waitUntil("the loop reports the wait") { !reports.all.isEmpty }

    server.stop()
    #expect(try await waitForExit(exited, seconds: 10))
  }

  @Test
  func aFatalAcceptFailureReportsItsCodeAndReleasesTheServer() async throws {
    let server = makeServer(generation: 5)
    let reports = Reports()
    let exited = DispatchSemaphore(value: 0)
    let failures = Counter()
    let changes = Changes()
    server.report = reports.add
    server.acceptLoopDidExit = { exited.signal() }
    server.listenerFailureChanged = changes.add
    server.acceptConnection = { descriptor in
      if failures.next() == 0 {
        errno = EBADF
        return -1
      }
      return Darwin.accept(descriptor, nil, nil)
    }
    try server.start()
    let client = try connect(server)
    defer { Darwin.close(client) }

    #expect(try await waitForExit(exited))
    let line = try #require(reports.all.first)
    #expect(line.contains(ErrorCode.requestListenerStopped.rawValue))
    #expect(line.contains(ErrorCode.requestListenerStopped.localizedExplanation))
    // The service records why and tells its owner; the process keeps running.
    guard case .stopped(let recorded) = ServiceListenerFailure.read(socketPath: server.socketPath)
    else {
      Issue.record("Expected the listener failure file")
      return
    }
    #expect(recorded.code == .requestListenerStopped)
    #expect(recorded.errorNumber == EBADF)
    #expect(recorded.process == .current)
    #expect(abs(recorded.time.timeIntervalSinceNow) < 60)
    // The start cleared the record (nil), then the loop's failure arrived.
    #expect(changes.all == [nil, recorded])
    // The loop released the listener, so the server starts again and stopping is safe.
    server.stop()
    try server.start()
    defer { server.stop() }
    #expect(try await call(server) == 5)
    // A successful start deletes the record of the last failure and tells the owner.
    #expect(ServiceListenerFailure.read(socketPath: server.socketPath) == .absent)
    #expect(changes.all == [nil, recorded, nil])
  }

  @Test
  func aFailedPollEndsTheLoopAsAFailureToo() async throws {
    let server = makeServer()
    let exited = DispatchSemaphore(value: 0)
    let changes = Changes()
    server.acceptLoopDidExit = { exited.signal() }
    server.listenerFailureChanged = changes.add
    server.report = { _ in }
    server.acceptConnection = { _ in
      errno = EINVAL
      return -1
    }
    try server.start()
    let client = try connect(server)
    defer { Darwin.close(client) }

    #expect(try await waitForExit(exited))
    guard case .stopped(let recorded) = ServiceListenerFailure.read(socketPath: server.socketPath)
    else {
      Issue.record("Expected the listener failure file")
      return
    }
    #expect(recorded.errorNumber == EINVAL)
    try ServiceListenerFailure.clear(socketPath: server.socketPath)
  }

  @Test
  func stoppingTheServerRecordsNoFailure() async throws {
    let server = makeServer()
    let exited = DispatchSemaphore(value: 0)
    let changes = Changes()
    server.acceptLoopDidExit = { exited.signal() }
    server.listenerFailureChanged = changes.add
    try server.start()
    server.stop()

    #expect(try await waitForExit(exited))
    #expect(changes.all == [nil])
    #expect(ServiceListenerFailure.read(socketPath: server.socketPath) == .absent)
  }

  @Test
  func anOrderlyStopDeletesTheRecordOfAFailedListener() async throws {
    let server = makeServer()
    let exited = DispatchSemaphore(value: 0)
    server.acceptLoopDidExit = { exited.signal() }
    server.report = { _ in }
    server.acceptConnection = { _ in
      errno = EBADF
      return -1
    }
    try server.start()
    let client = try connect(server)
    defer { Darwin.close(client) }
    #expect(try await waitForExit(exited))
    guard case .stopped = ServiceListenerFailure.read(socketPath: server.socketPath) else {
      Issue.record("Expected the listener failure file")
      return
    }

    server.stop()

    #expect(ServiceListenerFailure.read(socketPath: server.socketPath) == .absent)
  }

  @Test
  func aStartDeletesTheFileOfAnEarlierFailure() throws {
    let server = makeServer()
    try ServiceListenerFailure(errorNumber: EBADF, time: Date(), process: .current)
      .write(
        socketPath: server.socketPath
      )

    try server.start()
    defer { server.stop() }

    #expect(ServiceListenerFailure.read(socketPath: server.socketPath) == .absent)
  }
}

struct AcceptFailureWaitTests {
  @Test
  func aPollFailureDuringTheWaitIsReportedAsFatalWithItsCode() {
    nonisolated(unsafe) var lines: [String] = []
    let goesOn = AcceptFailure.continuesAfter(
      errno: EMFILE,
      server: "Test",
      wake: -1,
      waitMilliseconds: 1_000,
      ended: .requestListenerStopped,
      pollCall: { _, _, _ in
        errno = EINVAL
        return -1
      },
      report: { lines.append($0) }
    )

    #expect(!goesOn)
    #expect(lines.count == 2)
    #expect(lines[0].contains("Cannot accept connections"))
    #expect(lines[1].contains(ErrorCode.requestListenerStopped.rawValue))
    #expect(lines[1].contains("errno \(EINVAL)"))
  }

  @Test
  func aWakeDescriptorThatIsClosedIsAFailureNotAStop() {
    var ends: [Int32] = [-1, -1]
    #expect(pipe(&ends) == 0)
    Darwin.close(ends[0])
    Darwin.close(ends[1])

    #expect(AcceptFailure.wait(milliseconds: 1_000, wake: ends[0]) == .failed(EBADF))
  }
}
