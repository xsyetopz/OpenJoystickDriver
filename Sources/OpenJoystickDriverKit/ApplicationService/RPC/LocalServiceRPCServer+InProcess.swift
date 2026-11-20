import Foundation

// A client in the server's own process, such as the app's UI calling the service it hosts, skips
// the socket: no connection, no thread per call, no peer lookup. The request and the response
// keep their JSON frames, so both paths decode the same bytes and report the same errors.
extension LocalServiceRPCServer {
  /// A server that a client in this process can reach, held weakly so the registry keeps no server
  /// alive.
  private struct Registration: @unchecked Sendable {
    /// The listening server.
    weak var server: LocalServiceRPCServer?
  }

  /// The listening servers that answer clients in this process, by socket path.
  private static let inProcessServers = Locked<[String: Registration]>([:])

  /// The listening server on `socketPath` that answers clients in this process, or nil.
  static func inProcessServer(socketPath: String) -> LocalServiceRPCServer? {
    inProcessServers.withLock { $0[socketPath]?.server }
  }

  /// Lets clients in this process reach this server once it listens.
  func registerInProcess() {
    guard servesClientsInProcess else { return }
    Self.inProcessServers.withLock { $0[socketPath] = Registration(server: self) }
  }

  /// Sends clients in this process back to the socket, unless another server took the path.
  func unregisterInProcess() {
    Self.inProcessServers.withLock { servers in
      if let current = servers[socketPath], current.server === self || current.server == nil {
        servers[socketPath] = nil
      }
    }
  }

  /// Answers `requestData`, one encoded request frame, for a client in this process.
  ///
  /// The client is authenticated as ``LocalSocketPeer/currentProcess``. A method that holds its
  /// reply open is cancelled when the caller is cancelled or times out, as a hang-up cancels it on
  /// the socket; any other request runs to completion.
  ///
  /// - Parameters:
  ///   - requestData: The encoded ``LocalServiceRPCRequest``.
  ///   - timeoutSeconds: The longest wait for the response; below 0.1 s counts as 0.1 s.
  /// - Returns: The encoded ``LocalServiceRPCResponse``, or nil when this process cannot read its
  ///   own peer, so the caller uses the socket.
  /// - Throws: ``LocalServiceRPCError/timeout`` when no response arrives in time,
  ///   ``LocalServiceRPCError/invalidFrame`` for a response larger than the frame limit, and
  ///   `CancellationError` when the task is cancelled.
  func respondInProcess(to requestData: Data, timeoutSeconds: TimeInterval) async throws -> Data? {
    try Task.checkCancellation()
    guard let peer = LocalSocketPeer.currentProcess else { return nil }
    guard authentication(peer) else {
      return try JSONEncoder().encode(
        LocalServiceRPCResponse(
          result: nil,
          error: LocalServiceRPCError.peerRejected.localizedDescription,
          errorCode: .peerRejected
        )
      )
    }
    let request: LocalServiceRPCRequest
    do {
      request = try JSONDecoder().decode(LocalServiceRPCRequest.self, from: requestData)
    } catch {
      return try JSONEncoder().encode(
        LocalServiceRPCResponse(result: nil, error: error.localizedDescription)
      )
    }
    let call = InProcessCall(
      cancelsWork: ApplicationServiceRPCMethod(rawValue: request.method)?.holdsReplyOpen == true
    )
    let serve = handler
    call.start(
      Task {
        let response = await serve(request)
        call.finish(Result { try Self.frame(response) })
      }
    )
    let deadline = DispatchWorkItem { call.finish(.failure(LocalServiceRPCError.timeout)) }
    DispatchQueue.global().asyncAfter(
      deadline: .now() + max(0.1, timeoutSeconds),
      execute: deadline
    )
    defer { deadline.cancel() }
    return try await withTaskCancellationHandler {
      try await call.value()
    } onCancel: {
      call.finish(.failure(CancellationError()))
    }
  }

  /// Encodes `response` as the socket would send it.
  ///
  /// - Throws: ``LocalServiceRPCError/invalidFrame`` when it is larger than the frame limit.
  private static func frame(_ response: LocalServiceRPCResponse) throws -> Data {
    let data = try JSONEncoder().encode(response)
    guard data.count <= LocalServiceRPCTransport.maximumFrameBytes else {
      throw LocalServiceRPCError.invalidFrame
    }
    return data
  }
}

/// One in-process call: the first of the response, the deadline and the caller's cancellation
/// ends it.
private final class InProcessCall: @unchecked Sendable {
  /// Guards every property below.
  private let lock = NSLock()
  /// Whether an early end cancels the handler's task, for a method that holds its reply open.
  private let cancelsWork: Bool
  /// The handler's task; nil before ``start(_:)``.
  private var work: Task<Void, Never>?
  /// How the call ended; nil while it runs.
  private var outcome: Result<Data, any Error>?
  /// The caller waiting in ``value()``; nil before it waits and after it resumes.
  private var waiter: CheckedContinuation<Data, any Error>?

  /// Creates a call whose early end cancels the handler when `cancelsWork`.
  init(cancelsWork: Bool) { self.cancelsWork = cancelsWork }

  /// Keeps the handler's task, and cancels it at once when the call already ended early.
  func start(_ task: Task<Void, Never>) {
    let cancel = lock.withLock { () -> Bool in
      work = task
      if case .failure = outcome { return cancelsWork }
      return false
    }
    if cancel { task.cancel() }
  }

  /// Ends the call with `result`; a later end changes nothing.
  func finish(_ result: Result<Data, any Error>) {
    let (resume, cancel) = lock.withLock {
      () -> (CheckedContinuation<Data, any Error>?, Task<Void, Never>?) in
      guard outcome == nil else { return (nil, nil) }
      outcome = result
      defer { waiter = nil }
      let early: Bool
      if case .failure = result { early = cancelsWork } else { early = false }
      return (waiter, early ? work : nil)
    }
    cancel?.cancel()
    resume?.resume(with: result)
  }

  /// Waits for the end of the call.
  func value() async throws -> Data {
    try await withCheckedThrowingContinuation { continuation in
      let ended = lock.withLock { () -> Result<Data, any Error>? in
        if let outcome { return outcome }
        waiter = continuation
        return nil
      }
      if let ended { continuation.resume(with: ended) }
    }
  }
}
