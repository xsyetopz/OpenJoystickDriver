import Foundation

/// What a bridge needs to open an authenticated endpoint session.
public struct EndpointCredentials: Sendable {
  /// The path of the endpoint's Unix socket.
  public var socketPath: String
  /// The access token that keys the proof of the `Hello` line.
  public var token: String
  /// The name that the `Hello` line gives the token.
  public var tokenName: String

  /// Creates credentials from the socket path, the token and the token's name.
  public init(socketPath: String, token: String, tokenName: String) {
    self.socketPath = socketPath
    self.token = token
    self.tokenName = tokenName
  }
}

/// The data channel that a bridge reads from and writes to. ``PeerLink`` is the one the tool uses.
public protocol PeerChannel: AnyObject, Sendable {
  /// Called with each message that arrives on the data channel.
  var onMessage: (@Sendable (Data) -> Void)? { get set }
  /// Sends a message over the data channel.
  ///
  /// - Returns: Whether the channel accepted the message.
  @discardableResult
  func send(_ data: Data) -> Bool
}

/// The bridge on the Mac that runs the game.
///
/// It needs the `control` scope. A `Frame` from the peer's data channel goes to the endpoint's
/// virtual gamepad, and each `RumbleCommand` of the endpoint goes back over the data channel.
public final class HostBridge: @unchecked Sendable {
  /// The endpoint closes a feed that sends no frame for 2 seconds, so the bridge sends a
  /// `KeepAlive` line when no frame has arrived for this long.
  static let keepAliveInterval: TimeInterval = 0.5
  /// The pause after each frame that is sent to the endpoint.
  ///
  /// The endpoint shows a frame for the 8 ms that it holds a frame. A frame that the peer sends
  /// meanwhile replaces the one that waits.
  static let sendInterval: TimeInterval = 0.008

  /// The data channel to the peer.
  private let link: any PeerChannel
  /// The `as` member of the `FeedRequest`: the persona of the virtual gamepad.
  private let persona: String
  /// Guards `endpoint` and `stopped`.
  private let lock = NSLock()
  /// The session that `start(_:)` opens and `stop()` closes.
  private var endpoint: EndpointSession?
  /// Holds the newest frame of the peer for `sendLoop`.
  private let mailbox = FrameMailbox()
  /// Whether `stop()` has been called.
  private var stopped = false

  /// Called when the endpoint ends the feed or the connection closes.
  public var onEnd: (@Sendable (Error?) -> Void)?

  /// Creates a bridge between a data channel and a virtual gamepad of the endpoint.
  ///
  /// - Parameters:
  ///   - link: The data channel to the peer.
  ///   - persona: The persona that the `FeedRequest` asks for.
  public init(link: any PeerChannel, persona: String = "Generic") {
    self.link = link
    self.persona = persona
  }

  /// Connects with the `Control` scope, opens a feed, and starts the reader and sender threads.
  ///
  /// The reader sends each `RumbleCommand` of the endpoint to the peer. The sender sends the newest
  /// frame of the peer, or a `KeepAlive` line when none arrives in time.
  ///
  /// - Parameter credentials: The socket, the token and the token's name.
  /// - Throws: ``BridgeError`` when the connection or the handshake fails, or the endpoint does not
  ///   answer the `FeedRequest` with a `FeedSession`.
  public func start(_ credentials: EndpointCredentials) throws {
    let session = try EndpointSession.connect(
      socketPath: credentials.socketPath,
      token: credentials.token,
      tokenName: credentials.tokenName,
      scopes: ["Control"]
    )
    try session.send(["apiVersion": endpointAPIVersion, "kind": "FeedRequest", "as": persona])
    guard let reply = try session.readLine(), reply["kind"] as? String == "FeedSession" else {
      throw BridgeError.protocolViolation("The endpoint did not answer with a FeedSession.")
    }
    lock.lock()
    endpoint = session
    lock.unlock()
    link.onMessage = { [weak self] data in self?.receive(data) }
    Thread.detachNewThread { [weak self] in self?.readEndpoint(session) }
    Thread.detachNewThread { [weak self] in self?.sendLoop(session) }
  }

  /// Stops the bridge and closes the endpoint session.
  ///
  /// `onEnd` is not called after this.
  public func stop() {
    lock.lock()
    stopped = true
    let session = endpoint
    lock.unlock()
    session?.close()
  }

  /// Whether `stop()` has been called, read under the lock.
  private var isStopped: Bool {
    lock.lock()
    defer { lock.unlock() }
    return stopped
  }

  /// Runs on the WebRTC callback thread: it checks the message and hands it on, and never blocks.
  private func receive(_ data: Data) {
    guard let frame = PeerMessage.frame(from: data) else { return }
    mailbox.post(frame)
  }

  /// Sends each `RumbleCommand` line of the endpoint to the peer until the connection ends.
  ///
  /// A line of another kind, or one longer than `PeerMessage.maximumBytes`, is dropped.
  private func readEndpoint(_ session: EndpointSession) {
    do {
      while let line = try session.readLine() {
        guard line["kind"] as? String == "RumbleCommand",
          let data = try? JSONSerialization.data(withJSONObject: line),
          data.count <= PeerMessage.maximumBytes
        else { continue }
        link.send(data)
      }
      finish(nil)
    } catch { finish(error) }
  }

  /// The one thread that sends to the endpoint: the newest frame, or a `KeepAlive` when none
  /// came within the keep-alive interval.
  private func sendLoop(_ session: EndpointSession) {
    let keepAlive: EndpointSession.Line = ["apiVersion": endpointAPIVersion, "kind": "KeepAlive"]
    while !isStopped {
      if let frame = mailbox.next(timeout: Self.keepAliveInterval) {
        if (try? session.send(frame)) == nil { return }
        Thread.sleep(forTimeInterval: Self.sendInterval)
      } else if (try? session.send(keepAlive)) == nil {
        return
      }
    }
  }

  /// Reports the end of the feed to `onEnd`, unless `stop()` has been called.
  private func finish(_ error: Error?) {
    if isStopped { return }
    onEnd?(error)
  }
}

/// The bridge on the player's Mac.
///
/// It needs the `read` scope. It subscribes to the controllers, sends the chosen controller's input
/// as `Frame` lines over the data channel, and reports each `RumbleCommand` that the peer sends
/// back. The endpoint has no message that drives a physical controller's rumble, so the bridge only
/// reports the commands.
public final class PlayerBridge: @unchecked Sendable {
  /// The data channel to the peer.
  private let link: any PeerChannel
  /// The `id` of the controller to forward, or nil for the first one that the endpoint reports.
  private let controller: String?
  /// Guards `endpoint` and `stopped`.
  private let lock = NSLock()
  /// The session that `start(_:)` opens and `stop()` closes.
  private var endpoint: EndpointSession?
  /// The `id` of the controller whose input is forwarded, once it is known.
  private var chosen: String?
  /// Whether `stop()` has been called.
  private var stopped = false

  /// Called with each valid `RumbleCommand` that the peer sends.
  public var onRumble: (@Sendable (EndpointSession.Line) -> Void)?
  /// Called with the error, or nil, when the subscription ends or the connection closes.
  public var onEnd: (@Sendable (Error?) -> Void)?

  /// Creates a bridge that forwards the input of one controller to the peer.
  ///
  /// - Parameters:
  ///   - link: The data channel to the peer.
  ///   - controller: The `id` from the watch lines; without it, the first controller that the
  ///     endpoint reports.
  public init(link: any PeerChannel, controller: String? = nil) {
    self.link = link
    self.controller = controller
    self.chosen = controller
  }

  /// Connects with the `Read` scope, subscribes to the controllers, and starts the reader thread.
  ///
  /// - Parameter credentials: The socket, the token and the token's name.
  /// - Throws: ``BridgeError`` when the connection or the handshake fails, or the request cannot be
  ///   sent.
  public func start(_ credentials: EndpointCredentials) throws {
    let session = try EndpointSession.connect(
      socketPath: credentials.socketPath,
      token: credentials.token,
      tokenName: credentials.tokenName,
      scopes: ["Read"]
    )
    try session.send([
      "apiVersion": endpointAPIVersion, "kind": "Subscription", "stream": "Controllers",
    ])
    lock.lock()
    endpoint = session
    lock.unlock()
    link.onMessage = { [weak self] data in
      guard let command = PeerMessage.rumble(from: data) else { return }
      self?.onRumble?(command)
    }
    Thread.detachNewThread { [weak self] in self?.readEndpoint(session) }
  }

  /// Stops the bridge and closes the endpoint session.
  ///
  /// `onEnd` is not called after this.
  public func stop() {
    lock.lock()
    stopped = true
    let session = endpoint
    lock.unlock()
    session?.close()
  }

  /// Passes each line of the endpoint to `forward(_:)` until the connection ends.
  private func readEndpoint(_ session: EndpointSession) {
    do {
      while let line = try session.readLine() {
        forward(line)
      }
      finish(nil)
    } catch { finish(error) }
  }

  /// Sends the `Frame` of the chosen controller's `MODIFIED` line to the peer.
  ///
  /// When no controller is chosen, the first `ADDED` line chooses its controller.
  private func forward(_ line: EndpointSession.Line) {
    if chosen == nil, line["type"] as? String == "ADDED",
      let object = line["object"] as? [String: Any], let id = object["id"] as? String
    {
      chosen = id
    }
    guard let (id, frame) = FrameTranslation.frame(fromWatchLine: line), id == chosen,
      let data = try? JSONSerialization.data(withJSONObject: frame)
    else { return }
    link.send(data)
  }

  /// Reports the end of the subscription to `onEnd`, unless `stop()` has been called.
  private func finish(_ error: Error?) {
    lock.lock()
    let wasStopped = stopped
    lock.unlock()
    if !wasStopped { onEnd?(error) }
  }
}
