package import Darwin
import Foundation

/// The server of the service's local RPC socket.
///
/// It accepts connections on a Unix socket that only the current user can open, asks the
/// authentication closure whether the peer may call, and passes each request to the handler.
@safe
public final class LocalServiceRPCServer: @unchecked Sendable {
  /// Decides whether a peer may call; the server turns away a peer for which it returns false.
  public typealias Authentication = @Sendable (LocalSocketPeer) -> Bool
  /// Answers a request.
  ///
  /// For a method that holds its reply open (``ApplicationServiceRPCMethod/holdsReplyOpen``) the
  /// task is cancelled when the client closes its end first; every other request runs to
  /// completion.
  public typealias Handler = @Sendable (LocalServiceRPCRequest) async -> LocalServiceRPCResponse

  /// Decides whether a peer may call.
  private let authentication: Authentication
  /// Answers each request.
  private let handler: Handler
  /// The path of the Unix socket the server listens on.
  package let socketPath: String
  /// Guards `listener`, `starting` and `stopRequested`.
  private let stateLock = NSLock()
  /// The sockets of the started server; nil while it is stopped.
  private var listener: Listener?
  /// True while a `start()` call sets up the sockets, so a second call is refused.
  private var starting = false
  /// True when `stop()` ran while `starting`; `start()` stops the server it finished.
  private var stopRequested = false

  /// Told after every change of the listener's failure: the failure when the accept loop ends on a
  /// fatal error, nil when a start clears it.
  ///
  /// The service sets it before `start()`.
  package var listenerFailureChanged: (@Sendable (ServiceListenerFailure?) -> Void)?

  // The hooks below belong to tests; set them before `start()`.
  /// Runs inside `start()` after the sockets are listening and before the server publishes them.
  package var beforeListenerPublished: (@Sendable () -> Void)?
  /// Runs once the accept loop has stopped and closed its descriptors; tests await it.
  package var acceptLoopDidExit: (@Sendable () -> Void)?
  /// Takes one connection from the listening descriptor, as `accept` does; tests replace it to
  /// fail the call.
  package var acceptConnection: @Sendable (Int32) -> Int32 = { Darwin.accept($0, nil, nil) }
  /// Makes the pipe that wakes a held request's `poll`, as `pipe` does; tests replace it to fail
  /// the call.
  package var wakePipe: @Sendable (UnsafeMutablePointer<Int32>) -> Int32 = {
    unsafe Darwin.pipe($0)
  }
  /// Waits for an event on a held request's connection or its wake pipe, as `poll` does; tests
  /// replace it to fail the call.
  package var pollConnection: @Sendable (UnsafeMutablePointer<pollfd>, nfds_t, Int32) -> Int32 = {
    unsafe Darwin.poll($0, $1, $2)
  }
  /// Milliseconds the accept loop waits after running out of descriptors or memory.
  package var resourceWaitMilliseconds = AcceptFailure.resourceWaitMilliseconds
  /// Receives the accept loop's reports; they go to standard output.
  package var report: @Sendable (String) -> Void = { print($0) }
  /// The name that the server's reports carry.
  private static let name = "LocalServiceRPCServer"
  /// The process that runs the server, written into every listener failure record.
  private let process = ServiceListenerFailure.ProcessIdentity.current

  /// One started server's sockets.
  ///
  /// The accept loop closes `socket` and `wakeRead`. Whoever clears `listener` closes
  /// `wakeWrite`: `stop()`, or the loop when it ends on its own. The loop sees the hang-up of
  /// `wakeRead` when `wakeWrite` closes. `id` tells servers apart that get the same descriptor
  /// numbers one after another.
  private struct Listener {
    /// Tells this listener from another that gets the same descriptor numbers.
    let id = UUID()
    /// The listening socket.
    let socket: Int32
    /// The read end of the pipe that wakes the accept loop.
    let wakeRead: Int32
    /// The write end of the pipe that wakes the accept loop.
    let wakeWrite: Int32
  }

  /// Creates a server for the service's default socket.
  public convenience init(authentication: @escaping Authentication, handler: @escaping Handler) {
    self.init(
      socketPath: LocalServiceRPCTransport.defaultSocketPath,
      authentication: authentication,
      handler: handler
    )
  }

  /// Creates a server for the socket at `socketPath`.
  package init(
    socketPath: String,
    authentication: @escaping Authentication,
    handler: @escaping Handler
  ) {
    self.socketPath = socketPath
    self.authentication = authentication
    self.handler = handler
  }

  /// Starts listening and accepting connections.
  ///
  /// - Throws: ``LocalServiceRPCError/alreadyRunning`` when this server or another process already
  ///   serves the socket, and ``LocalServiceRPCError/connectionFailed(_:)`` with the error number
  ///   of a failed socket call.
  public func start() throws {
    try stateLock.withLock {
      guard listener == nil, !starting else { throw LocalServiceRPCError.alreadyRunning }
      starting = true
    }
    do { try startReserved() } catch {
      stateLock.withLock {
        starting = false
        stopRequested = false
      }
      throw error
    }
    if stateLock.withLock({
      defer { stopRequested = false }
      return stopRequested
    }) {
      stop()
    }
  }

  /// Call with the start slot reserved; the slot passes to `listener` when this returns.
  private func startReserved() throws {
    let path = socketPath
    try removeStaleSocket(at: path)
    let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
    guard descriptor >= 0 else { throw LocalServiceRPCError.connectionFailed(errno) }
    do {
      var address = try LocalServiceRPCTransport.socketAddress(path: path)
      let bindStatus = withUnsafePointer(to: &address) {
        unsafe $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
          unsafe Darwin.bind(
            descriptor,
            $0,
            LocalServiceRPCTransport.socketAddressLength(path: path)
          )
        }
      }
      guard bindStatus == 0 else { throw LocalServiceRPCError.connectionFailed(errno) }
      guard unsafe chmod(path, S_IRUSR | S_IWUSR) == 0 else {
        throw LocalServiceRPCError.connectionFailed(errno)
      }
      guard Darwin.listen(descriptor, 16) == 0 else {
        throw LocalServiceRPCError.connectionFailed(errno)
      }
      var wake: [Int32] = [-1, -1]
      guard unsafe pipe(&wake) == 0 else { throw LocalServiceRPCError.connectionFailed(errno) }
      let started = Listener(socket: descriptor, wakeRead: wake[0], wakeWrite: wake[1])
      beforeListenerPublished?()
      stateLock.withLock {
        listener = started
        starting = false
        clearListenerFailure()
      }
      BlockingWork.detachThread(name: "com.openjoystickdriver.rpc.accept") { [weak self] in
        self?.acceptConnections(started)
      }
    } catch {
      Darwin.close(descriptor)
      unsafe unlink(path)
      throw error
    }
  }

  /// Stops the server and deletes the record of a listener failure, also when the listener already
  /// stopped on its own: an orderly stop leaves nothing for `ojd` to report.
  ///
  /// A call while `start()` still sets up the sockets takes effect as soon as that call returns.
  public func stop() {
    stateLock.withLock {
      deleteListenerFailureRecord()
      guard let stopped = listener else {
        if starting { stopRequested = true }
        return
      }
      listener = nil
      // Closing the write end hangs up the read end, which wakes the accept loop to close the
      // rest. The socket file goes under the lock, so a later `start()` cannot lose its new file.
      Darwin.close(stopped.wakeWrite)
      unsafe unlink(socketPath)
    }
  }

  /// Ends the server when the loop stops on its own: the loop owns `wakeWrite` then, unless
  /// `stop()` already took the listener.
  ///
  /// Returns whether the loop ended the server, as opposed to `stop()` having done so. A fatal
  /// `failure` is recorded under the same lock, so a start that follows clears the record after it
  /// was written and a late write never replaces that clear.
  private func release(_ ended: Listener, failure: Int32?) -> Bool {
    stateLock.withLock {
      guard listener?.id == ended.id else { return false }
      listener = nil
      Darwin.close(ended.wakeWrite)
      unsafe unlink(socketPath)
      if let failure { recordListenerFailure(errno: failure) }
      return true
    }
  }

  /// Runs the loop.
  ///
  /// A loop that ends on a fatal error records why in a file beside the socket and in
  /// `listenerFailureChanged`, because the RPC socket cannot carry the reason once it is gone. The
  /// process keeps running.
  private func acceptConnections(_ listener: Listener) {
    let failure = acceptUntilEnd(listener)
    _ = release(listener, failure: failure)
    Darwin.close(listener.socket)
    Darwin.close(listener.wakeRead)
    acceptLoopDidExit?()
  }

  /// Accepts connections until the server stops, and returns the error number of a fatal error.
  private func acceptUntilEnd(_ listener: Listener) -> Int32? {
    while true {
      var events = [
        pollfd(fd: listener.socket, events: Int16(POLLIN), revents: 0),
        pollfd(fd: listener.wakeRead, events: Int16(POLLIN), revents: 0),
      ]
      let ready = unsafe poll(&events, 2, -1)
      if ready < 0 {
        let code = errno
        if code == EINTR { continue }
        report(endMessage(code))
        return code
      }
      if events[1].revents != 0 { return nil }
      guard events[0].revents & Int16(POLLIN) != 0 else {
        report(endMessage(EIO))
        return EIO
      }
      let connection = acceptConnection(listener.socket)
      guard connection >= 0 else {
        let next = unsafe AcceptFailure.continuation(
          errno: errno,
          server: Self.name,
          wake: listener.wakeRead,
          waitMilliseconds: resourceWaitMilliseconds,
          ended: .requestListenerStopped,
          report: report
        )
        switch next {
        case .goOn: continue
        case .stopped: return nil
        case .ended(let code): return code
        }
      }
      BlockingWork.detach(label: "com.openjoystickdriver.rpc.connection") { [weak self] in
        guard let self else {
          Darwin.close(connection)
          return
        }
        handleConnection(connection)
      }
    }
  }

  /// Writes the failure record beside the socket for the fatal accept error `code` and tells
  /// ``listenerFailureChanged``.
  private func recordListenerFailure(errno code: Int32) {
    let failure = ServiceListenerFailure(
      errorNumber: code,
      time: Date(),
      process: process
    )
    defer { listenerFailureChanged?(failure) }
    do { try failure.write(socketPath: socketPath) } catch {
      report(
        "[\(Self.name)] Could not record why the request listener stopped in "
          + "\(ServiceListenerFailure.path(forSocket: socketPath)): \(error.localizedDescription)"
      )
    }
  }

  /// A listener that starts deletes the record of the last failure.
  ///
  /// Runs under `stateLock`.
  private func clearListenerFailure() {
    deleteListenerFailureRecord()
    listenerFailureChanged?(nil)
  }

  /// Deletes the failure record beside the socket and reports a failure to delete it.
  private func deleteListenerFailureRecord() {
    do { try ServiceListenerFailure.clear(socketPath: socketPath) } catch {
      report(
        "[\(Self.name)] Could not delete the record of the last listener failure: "
          + error.localizedDescription
      )
    }
  }

  /// The report line for a fatal accept error `code`.
  private func endMessage(_ code: Int32) -> String {
    AcceptFailure.message(
      server: Self.name,
      errno: code,
      action: .fatal,
      ended: .requestListenerStopped
    )
  }

  /// Authenticates the peer of `descriptor`, reads one request and answers it, then closes the
  /// connection.
  private func handleConnection(_ descriptor: Int32) {
    guard let peer = LocalSocketPeer.authenticated(descriptor) else {
      Darwin.close(descriptor)
      return
    }
    do {
      try LocalServiceRPCTransport.setTimeout(descriptor, seconds: 35)
      guard authentication(peer) else {
        let response = LocalServiceRPCResponse(
          result: nil,
          error: LocalServiceRPCError.peerRejected.localizedDescription,
          errorCode: .peerRejected
        )
        try LocalServiceRPCTransport.sendFrame(try JSONEncoder().encode(response), to: descriptor)
        Darwin.close(descriptor)
        return
      }
      let data = try LocalServiceRPCTransport.receiveFrame(from: descriptor)
      let request = try JSONDecoder().decode(LocalServiceRPCRequest.self, from: data)
      answer(request, on: descriptor)
    } catch {
      let response = LocalServiceRPCResponse(result: nil, error: error.localizedDescription)
      if let encoded = try? JSONEncoder().encode(response) {
        try? LocalServiceRPCTransport.sendFrame(encoded, to: descriptor)
      }
      Darwin.close(descriptor)
    }
  }

  /// Runs the handler for `request`, sends its response and closes the connection.
  ///
  /// A client sends one request and then only reads. For a method that holds its reply open, any
  /// event on the connection before the response, a hang-up, an error or stray bytes, cancels the
  /// handler's task, so a request does not outlive its client. The wait is event-driven: the
  /// thread sleeps in `poll` on the connection and on a pipe that the finished task writes to.
  /// When that pipe cannot be made, the request is answered with the connection-failure error
  /// and the handler does not run; when `poll` fails, the failure is reported and the task is
  /// cancelled. Any other request runs to completion even when the client has left.
  ///
  /// Each connection holds one GCD thread for its request: for a held request until the response
  /// is sent or the client leaves, which is up to `TestNotificationDeadlines.pickupSeconds` plus
  /// `TestNotificationDeadlines.answerSeconds` seconds for a test notification request.
  private func answer(_ request: LocalServiceRPCRequest, on descriptor: Int32) {
    let watches = ApplicationServiceRPCMethod(rawValue: request.method)?.holdsReplyOpen == true
    var wake: (read: Int32, write: Int32) = (-1, -1)
    if watches {
      do { wake = try openWakePipe() } catch {
        let response = LocalServiceRPCResponse(result: nil, error: error.localizedDescription)
        if let encoded = try? JSONEncoder().encode(response) {
          try? LocalServiceRPCTransport.sendFrame(encoded, to: descriptor)
        }
        Darwin.close(descriptor)
        return
      }
    }
    let finished = DispatchSemaphore(value: 0)
    let wakeWrite = wake.write
    let serve = handler
    let task = Task {
      let response = await serve(request)
      if let encoded = try? JSONEncoder().encode(response) {
        try? LocalServiceRPCTransport.sendFrame(encoded, to: descriptor)
      }
      if watches { _ = unsafe Darwin.write(wakeWrite, "x", 1) }
      finished.signal()
    }
    if watches {
      var events = [
        pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0),
        pollfd(fd: wake.read, events: Int16(POLLIN), revents: 0),
      ]
      var ready: Int32
      var code: Int32
      repeat {
        ready = unsafe pollConnection(&events, 2, -1)
        code = errno
      } while ready < 0 && code == EINTR
      if ready < 0 {
        report(
          "[\(Self.name)] Waiting on a held request's connection failed (errno \(code)); "
            + "the request is cancelled."
        )
        task.cancel()
      } else if events[1].revents == 0 {
        task.cancel()
      }
    }
    finished.wait()
    if watches {
      Darwin.close(wake.read)
      Darwin.close(wake.write)
    }
    Darwin.close(descriptor)
  }

  /// Makes the pipe that wakes a held request's `poll`, with both ends closed on `exec`.
  private func openWakePipe() throws -> (read: Int32, write: Int32) {
    var ends: [Int32] = [-1, -1]
    guard unsafe wakePipe(&ends) == 0 else { throw LocalServiceRPCError.connectionFailed(errno) }
    for end in ends where fcntl(end, F_SETFD, FD_CLOEXEC) != 0 {
      let code = errno
      Darwin.close(ends[0])
      Darwin.close(ends[1])
      throw LocalServiceRPCError.connectionFailed(code)
    }
    return (ends[0], ends[1])
  }

  /// Deletes a socket file that no server answers on.
  ///
  /// - Throws: ``LocalServiceRPCError/alreadyRunning`` when a server answers on `path`,
  ///   ``LocalServiceRPCError/peerRejected`` when the file is not a socket of the current user, and
  ///   ``LocalServiceRPCError/connectionFailed(_:)`` when the file cannot be deleted.
  private func removeStaleSocket(at path: String) throws {
    guard FileManager.default.fileExists(atPath: path) else { return }
    if LocalServiceRPCClient.serverProcessIdentifier(socketPath: path) != nil {
      throw LocalServiceRPCError.alreadyRunning
    }
    var information = stat()
    guard unsafe lstat(path, &information) == 0 else { return }
    guard information.st_uid == geteuid(), information.st_mode & S_IFMT == S_IFSOCK else {
      throw LocalServiceRPCError.peerRejected
    }
    guard unsafe unlink(path) == 0 else { throw LocalServiceRPCError.connectionFailed(errno) }
  }
}
