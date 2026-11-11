import Darwin
import Foundation
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit

private func waitForSemaphore(
  _ semaphore: DispatchSemaphore,
  timeout: DispatchTime
) -> DispatchTimeoutResult { semaphore.wait(timeout: timeout) }

@Suite(.serialized, .timeLimit(.minutes(2)), .removingTemporarySockets)
struct LocalServiceRPCTests {
  @Test
  func roundTripUsesPrivateSocketAndBoundedJSONFrame() async throws {
    let socketPath = temporarySocketPath()
    let server = LocalServiceRPCServer(
      socketPath: socketPath,
      authentication: { _ in true },
      handler: { request in
        let value = try? JSONDecoder().decode(String.self, from: request.arguments)
        let result = value.flatMap { try? JSONEncoder().encode($0.uppercased()) }
        return LocalServiceRPCResponse(result: result, error: result == nil ? "decode" : nil)
      }
    )
    try server.start()
    defer { server.stop() }

    let result: String = try await LocalServiceRPCClient.call(
      method: "uppercase",
      arguments: "controller",
      timeoutSeconds: 10,
      socketPath: socketPath
    )
    let attributes = try FileManager.default.attributesOfItem(atPath: socketPath)

    #expect(result == "CONTROLLER")
    #expect(attributes[.posixPermissions] as? Int == 0o600)
  }

  @Test
  func rejectedPeerIsReportedAsAuthenticationFailure() async throws {
    let socketPath = temporarySocketPath()
    let handlerCalled = DispatchSemaphore(value: 0)
    let server = LocalServiceRPCServer(
      socketPath: socketPath,
      authentication: { _ in false },
      handler: { _ in
        handlerCalled.signal()
        return LocalServiceRPCResponse(result: Data(), error: nil)
      }
    )
    try server.start()
    defer { server.stop() }

    await #expect(throws: LocalServiceRPCError.peerRejected) {
      let _: Data = try await LocalServiceRPCClient.call(
        method: "rejected",
        arguments: LocalServiceRPCEmptyArguments(),
        timeoutSeconds: 10,
        socketPath: socketPath
      )
    }
    #expect(waitForSemaphore(handlerCalled, timeout: .now()) == .timedOut)
  }

  @Test
  func authenticationReceivesThePeerFromItsAuditToken() async throws {
    let socketPath = temporarySocketPath()
    let peers = PeerRecorder()
    let server = LocalServiceRPCServer(
      socketPath: socketPath,
      authentication: { peer in
        peers.record(peer)
        return true
      },
      handler: { _ in
        return LocalServiceRPCResponse(result: Data("1".utf8), error: nil)
      }
    )
    try server.start()
    defer { server.stop() }

    let _: Int = try await LocalServiceRPCClient.call(
      method: "peer",
      arguments: LocalServiceRPCEmptyArguments(),
      timeoutSeconds: 10,
      socketPath: socketPath
    )

    let peer = try #require(peers.last)
    #expect(peer.processIdentifier == getpid())
  }

  @Test
  func secondServerCannotDisplaceLiveSocketOwner() throws {
    let socketPath = temporarySocketPath()
    let first = LocalServiceRPCServer(
      socketPath: socketPath,
      authentication: { _ in true },
      handler: { _ in
        return LocalServiceRPCResponse(result: Data(), error: nil)
      }
    )
    let second = LocalServiceRPCServer(
      socketPath: socketPath,
      authentication: { _ in true },
      handler: { _ in
        return LocalServiceRPCResponse(result: Data(), error: nil)
      }
    )
    try first.start()
    defer { first.stop() }

    do {
      try second.start()
      Issue.record("Expected the live RPC socket owner to reject a second server.")
      second.stop()
    } catch LocalServiceRPCError.alreadyRunning {
      #expect(LocalServiceRPCClient.serverProcessIdentifier(socketPath: socketPath) == getpid())
    } catch { Issue.record("Unexpected second-server error: \(error)") }
  }

  @Test
  func eachRestartedServerAnswersOnItsOwnAndAStoppedServerAnswersNothing() async throws {
    var stopped: [String] = []
    for generation in 0..<20 {
      let socketPath = temporarySocketPath()
      let server = LocalServiceRPCServer(
        socketPath: socketPath,
        authentication: { _ in true },
        handler: { _ in
          return LocalServiceRPCResponse(result: try? JSONEncoder().encode(generation), error: nil)
        }
      )
      try server.start()
      let answer: Int = try await LocalServiceRPCClient.call(
        method: "generation",
        arguments: "",
        timeoutSeconds: 10,
        socketPath: socketPath
      )
      #expect(answer == generation)
      server.stop()
      stopped.append(socketPath)
    }
    for socketPath in stopped {
      #expect(LocalServiceRPCClient.serverProcessIdentifier(socketPath: socketPath) == nil)
    }
  }

  @Test
  func oversizedFrameIsRejectedBeforeWrite() throws {
    let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
    try #require(descriptor >= 0)
    defer { Darwin.close(descriptor) }
    let data = Data(count: LocalServiceRPCTransport.maximumFrameBytes + 1)

    #expect(throws: (any Error).self) {
      try LocalServiceRPCTransport.sendFrame(data, to: descriptor)
    }
  }

  @Test
  func responseWithoutErrorCodeStillDecodes() throws {
    let response = try JSONDecoder().decode(
      LocalServiceRPCResponse.self,
      from: Data(#"{"result":null,"error":"peer-error"}"#.utf8)
    )

    #expect(response.result == nil)
    #expect(response.error == "peer-error")
    #expect(response.errorCode == nil)
  }

  @Test
  func errorCodeRawValuesAreTheWireStrings() throws {
    #expect(LocalServiceRPCErrorCode.peerRejected.rawValue == "peerRejected")
    let response = try JSONDecoder().decode(
      LocalServiceRPCResponse.self,
      from: Data(#"{"result":null,"error":"rejected","errorCode":"peerRejected"}"#.utf8)
    )
    #expect(response.errorCode == .peerRejected)
  }

  @Test
  func partialFrameRemainsInvalidInsteadOfLookingLikePeerRejection() throws {
    var descriptors = [Int32](repeating: -1, count: 2)
    try unsafe #require(socketpair(AF_UNIX, SOCK_STREAM, 0, &descriptors) == 0)
    defer {
      Darwin.close(descriptors[0])
      Darwin.close(descriptors[1])
    }

    var byte: UInt8 = 0
    try unsafe #require(Darwin.write(descriptors[0], &byte, 1) == 1)
    try #require(shutdown(descriptors[0], SHUT_WR) == 0)

    #expect(throws: LocalServiceRPCError.invalidFrame) {
      try LocalServiceRPCTransport.receiveFrame(
        from: descriptors[1],
        closedBeforeFrameError: .peerRejected
      )
    }
  }

  @Test
  func typedPermissionRequestRoundTripsThroughClient() async throws {
    let socketPath = temporarySocketPath()
    let server = LocalServiceRPCServer(
      socketPath: socketPath,
      authentication: { _ in true },
      handler: { request in
        #expect(request.method == "requestAccess")
        do {
          let arguments = try JSONDecoder().decode(
            LocalServiceRPCPermissionArguments.self,
            from: request.arguments
          )
          #expect(arguments.requirement == .inputRead)
          let snapshot = PermissionManager.Snapshot(
            inputRead: .denied,
            inputInject: .granted
          )
          return LocalServiceRPCResponse(result: try JSONEncoder().encode(snapshot), error: nil)
        } catch {
          return LocalServiceRPCResponse(result: nil, error: error.localizedDescription)
        }
      }
    )
    try server.start()
    defer { server.stop() }

    let client = ApplicationServiceClient(socketPath: socketPath)
    await client.connect()
    #expect(client.isConnected)
    #expect(
      try await client.requestAccess(.inputRead)
        == PermissionManager.Snapshot(inputRead: .denied, inputInject: .granted)
    )
  }

  @Test
  func colorPreviewPreservesSelectorAndOwnershipToken() async throws {
    let socketPath = temporarySocketPath()
    let token = UUID()
    let server = LocalServiceRPCServer(
      socketPath: socketPath,
      authentication: { _ in true },
      handler: { request in
        do {
          if request.method == "previewPhysicalColor" {
            let arguments = try JSONDecoder().decode(
              LocalServiceRPCColorPreviewArguments.self,
              from: request.arguments
            )
            #expect(arguments.controller == .session(.fixture("controller-1")))
            #expect(arguments.token == token)
            #expect(arguments.red == 1)
            #expect(arguments.green == 2)
            #expect(arguments.blue == 3)
          } else {
            let arguments = try JSONDecoder().decode(
              LocalServiceRPCColorPreviewReleaseArguments.self,
              from: request.arguments
            )
            #expect(request.method == "releasePhysicalColorPreview")
            #expect(arguments.token == token)
          }
          return LocalServiceRPCResponse(result: try JSONEncoder().encode(true), error: nil)
        } catch {
          return LocalServiceRPCResponse(result: nil, error: error.localizedDescription)
        }
      }
    )
    try server.start()
    defer { server.stop() }

    let client = ApplicationServiceClient(socketPath: socketPath)
    await client.connect()
    #expect(
      try await client.previewPhysicalColor(
        for: .session(.fixture("controller-1")),
        token: token,
        red: 1,
        green: 2,
        blue: 3
      )
    )
    #expect(
      try await client.releasePhysicalColorPreview(
        for: .session(.fixture("controller-1")),
        token: token
      )
    )
  }

  @Test(.timeLimit(.minutes(1)))
  func cancellingHeldRequestClosesConnectionBeforeTimeoutAndNextCallWorks() async throws {
    let socketPath = temporarySocketPath()
    let (requestReceived, requestReceivedSignal) = AsyncStream.makeStream(of: Void.self)
    let (releaseHeldRequest, releaseGate) = AsyncStream.makeStream(of: Void.self)
    let server = LocalServiceRPCServer(
      socketPath: socketPath,
      authentication: { _ in true },
      handler: { request in
        if request.method == "held" {
          requestReceivedSignal.yield()
          for await _ in releaseHeldRequest { break }
        }
        return LocalServiceRPCResponse(result: try? JSONEncoder().encode("ok"), error: nil)
      }
    )
    try server.start()
    defer {
      releaseGate.finish()
      server.stop()
    }

    let task = Task {
      let _: String = try await LocalServiceRPCClient.call(
        method: "held",
        arguments: LocalServiceRPCEmptyArguments(),
        timeoutSeconds: 10,
        socketPath: socketPath
      )
    }
    for await _ in requestReceived { break }

    task.cancel()
    await #expect(throws: CancellationError.self) { try await task.value }

    let result: String = try await LocalServiceRPCClient.call(
      method: "afterCancellation",
      arguments: LocalServiceRPCEmptyArguments(),
      timeoutSeconds: 10,
      socketPath: socketPath
    )
    #expect(result == "ok")
    releaseGate.finish()
  }

  @Test
  func heldStatusWaitReportsAnEndOfStreamAsTheServiceClosingTheConnection() async throws {
    let socketPath = temporarySocketPath()
    let listener = try ClosingSocketListener(path: socketPath)
    defer { listener.stop() }
    let client = ApplicationServiceClient(socketPath: socketPath)
    await client.connect(timeoutSeconds: 2)

    await #expect(throws: LocalServiceRPCError.serviceClosedConnection) {
      _ = try await client.waitForServiceStatusChange(
        after: ServiceStatusRevision(instance: UUID(), generation: 1)
      )
    }
    await #expect(throws: LocalServiceRPCError.peerRejected) {
      _ = try await client.waitForServiceStatusChange(after: nil)
    }
  }

  @Test
  func heldStatusWaitReportsARejectingReplyAsAPeerRejection() async throws {
    let socketPath = temporarySocketPath()
    let server = LocalServiceRPCServer(
      socketPath: socketPath,
      authentication: { _ in false },
      handler: { _ in
        return LocalServiceRPCResponse(result: Data(), error: nil)
      }
    )
    try server.start()
    defer { server.stop() }
    let client = ApplicationServiceClient(socketPath: socketPath)
    await client.connect(timeoutSeconds: 2)

    await #expect(throws: LocalServiceRPCError.peerRejected) {
      _ = try await client.waitForServiceStatusChange(
        after: ServiceStatusRevision(instance: UUID(), generation: 1)
      )
    }
  }

  /// Sends `method` on a raw connection and returns it open; the caller closes it.
  private func send(method: String, socketPath: String) throws -> Int32 {
    let descriptor = try LocalServiceRPCTransport.openConnectedSocket(
      timeoutSeconds: 5,
      socketPath: socketPath
    )
    let request = LocalServiceRPCRequest(
      method: method,
      arguments: try JSONEncoder().encode(LocalServiceRPCEmptyArguments())
    )
    try LocalServiceRPCTransport.sendFrame(try JSONEncoder().encode(request), to: descriptor)
    return descriptor
  }

  @Test(.timeLimit(.minutes(1)))
  func aClientThatLeavesCancelsOnlyTheRequestsThatHoldTheirReplyOpen() async throws {
    let socketPath = temporarySocketPath()
    let started = Locked<Set<String>>([])
    let ended = Locked<[String: Bool]>([:])
    let server = LocalServiceRPCServer(
      socketPath: socketPath,
      authentication: { _ in true },
      handler: { request in
        started.withLock { _ = $0.insert(request.method) }
        try? await Task.sleep(nanoseconds: 300_000_000)
        ended.withLock { $0[request.method] = Task.isCancelled }
        return LocalServiceRPCResponse(result: Data(), error: nil)
      }
    )
    try server.start()
    defer { server.stop() }
    let held = ApplicationServiceRPCMethod.waitForServiceStatusChange.rawValue
    let mutation = ApplicationServiceRPCMethod.setSetting.rawValue

    let clients = [
      try send(method: held, socketPath: socketPath),
      try send(method: mutation, socketPath: socketPath),
    ]
    while started.withLock({ $0.count }) < 2 {
      try await Task.sleep(nanoseconds: 5_000_000)
    }
    for client in clients { Darwin.close(client) }
    while ended.withLock({ $0.count }) < 2 {
      try await Task.sleep(nanoseconds: 5_000_000)
    }

    #expect(ended.withLock { $0[held] } == true)
    #expect(ended.withLock { $0[mutation] } == false)
  }

  @Test
  func aHeldRequestWhoseWakePipeCannotBeMadeIsAnsweredWithTheConnectionFailureAndNeverRuns()
    async throws
  {
    let socketPath = temporarySocketPath()
    let handlerRan = Locked(false)
    let server = LocalServiceRPCServer(
      socketPath: socketPath,
      authentication: { _ in true },
      handler: { _ in
        handlerRan.withLock { $0 = true }
        return LocalServiceRPCResponse(result: Data(), error: nil)
      }
    )
    unsafe server.wakePipe = { _ in
      errno = EMFILE
      return -1
    }
    try server.start()
    defer { server.stop() }

    await #expect(throws: LocalServiceRPCError.remote(Self.connectionFailure(EMFILE))) {
      let _: Data = try await LocalServiceRPCClient.call(
        method: ApplicationServiceRPCMethod.waitForServiceStatusChange.rawValue,
        arguments: LocalServiceRPCEmptyArguments(),
        timeoutSeconds: 10,
        socketPath: socketPath
      )
    }
    #expect(!handlerRan.withLock { $0 })
  }

  @Test
  func theWakePipeOfAHeldRequestIsClosedOnExec() async throws {
    let socketPath = temporarySocketPath()
    let ends = Locked<[Int32]>([])
    let flags = Locked<[Int32]>([])
    let server = LocalServiceRPCServer(
      socketPath: socketPath,
      authentication: { _ in true },
      handler: { _ in
        flags.withLock { $0 = ends.withLock { $0 }.map { fcntl($0, F_GETFD) } }
        return LocalServiceRPCResponse(result: try? JSONEncoder().encode(true), error: nil)
      }
    )
    unsafe server.wakePipe = { descriptors in
      let status = unsafe Darwin.pipe(descriptors)
      ends.withLock { $0 = unsafe [descriptors[0], descriptors[1]] }
      return status
    }
    try server.start()
    defer { server.stop() }

    let _: Bool = try await LocalServiceRPCClient.call(
      method: ApplicationServiceRPCMethod.waitForServiceStatusChange.rawValue,
      arguments: LocalServiceRPCEmptyArguments(),
      timeoutSeconds: 10,
      socketPath: socketPath
    )

    let observed = flags.withLock { $0 }
    #expect(observed.count == 2)
    #expect(observed.allSatisfy { $0 >= 0 && $0 & FD_CLOEXEC != 0 })
  }

  @Test
  func aFailedPollIsReportedAndCancelsTheHeldRequest() async throws {
    let socketPath = temporarySocketPath()
    let reports = Locked<[String]>([])
    let (never, neverGate) = AsyncStream.makeStream(of: Void.self)
    defer { neverGate.finish() }
    let server = LocalServiceRPCServer(
      socketPath: socketPath,
      authentication: { _ in true },
      handler: { _ in
        for await _ in never {}
        return LocalServiceRPCResponse(
          result: try? JSONEncoder().encode(Task.isCancelled),
          error: nil
        )
      }
    )
    server.report = { message in reports.withLock { $0.append(message) } }
    unsafe server.pollConnection = { _, _, _ in
      errno = EINVAL
      return -1
    }
    try server.start()
    defer { server.stop() }

    let cancelled: Bool = try await LocalServiceRPCClient.call(
      method: ApplicationServiceRPCMethod.waitForServiceStatusChange.rawValue,
      arguments: LocalServiceRPCEmptyArguments(),
      timeoutSeconds: 10,
      socketPath: socketPath
    )

    #expect(cancelled)
    #expect(reports.withLock { $0.contains { $0.contains("errno \(EINVAL)") } })
  }

  private static func connectionFailure(_ code: Int32) -> String {
    LocalServiceRPCError.connectionFailed(code).localizedDescription
  }

}

private final class PeerRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var peers: [LocalSocketPeer] = []

  var last: LocalSocketPeer? { lock.withLock { peers.last } }

  func record(_ peer: LocalSocketPeer) { lock.withLock { peers.append(peer) } }
}

/// Accepts every connection and closes it without sending a frame.
private final class ClosingSocketListener: @unchecked Sendable {
  private let descriptor: Int32
  private let path: String

  init(path: String) throws {
    self.path = path
    descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
    try #require(descriptor >= 0)
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    withUnsafeMutableBytes(of: &address.sun_path) { buffer in
      _ = path.withCString { unsafe strncpy(buffer.baseAddress!, $0, buffer.count - 1) }
    }
    let bound = withUnsafePointer(to: &address) {
      unsafe $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        unsafe bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
      }
    }
    try #require(bound == 0)
    try #require(listen(descriptor, 8) == 0)
    let listening = descriptor
    Thread.detachNewThread {
      while true {
        let connection = accept(listening, nil, nil)
        if connection < 0 { return }
        Darwin.close(connection)
      }
    }
  }

  func stop() {
    shutdown(descriptor, SHUT_RDWR)
    Darwin.close(descriptor)
    unsafe unlink(path)
  }
}
