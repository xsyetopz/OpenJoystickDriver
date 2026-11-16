import Foundation
import LiveKitWebRTC

/// The side of the signaling that a link plays.
///
/// The offerer creates the offer and opens the data channel; the answerer receives the channel from
/// the offerer.
public enum SignalingRole: String, Sendable {
  /// Creates the offer and opens the data channel.
  case offer
  /// Applies the offer and creates the answer.
  case answer
}

/// One WebRTC data channel to one peer.
///
/// The offer and the answer travel out of band as a blob: base64 of a JSON object with `type` and
/// `sdp`. The blob is made after ICE gathering has finished, so the SDP carries the candidates and
/// no trickle exchange is needed. The link opens no listening socket: ICE binds UDP sockets for
/// the data channel, and TCP candidates are off.
public final class PeerLink: NSObject, @unchecked Sendable {
  /// The label of the data channel that the offerer opens.
  public static let channelLabel = "ojd"

  /// Called on a WebRTC thread with each message of the data channel.
  public var onMessage: (@Sendable (Data) -> Void)?
  /// Called on a WebRTC thread when the data channel opens.
  public var onOpen: (@Sendable () -> Void)?

  /// The factory that creates the peer connection of every link.
  private static let factory = LKRTCPeerConnectionFactory()

  /// The side of the signaling that this link plays.
  private let role: SignalingRole
  /// Guards `channel`, `gatheringWaiters` and `openWaiters`.
  private let lock = NSLock()
  // swift-format-ignore: NeverUseImplicitlyUnwrappedOptionals
  // The factory takes `self` as delegate, so `init` assigns this after `super.init()`.
  /// The peer connection, assigned in `init`.
  private var connection: LKRTCPeerConnection!
  /// The data channel, set by `attach(_:)`.
  private var channel: LKRTCDataChannel?
  /// The tasks that wait in `waitForGathering` for the end of ICE gathering.
  private var gatheringWaiters: [CheckedContinuation<Void, Never>] = []
  /// The tasks that wait in `waitUntilOpen` for the data channel to open.
  private var openWaiters: [CheckedContinuation<Void, Never>] = []

  /// Creates the peer connection, and for the offerer the data channel.
  ///
  /// TCP candidates are off, so ICE binds only UDP sockets.
  ///
  /// - Parameters:
  ///   - role: The side of the signaling that this link plays.
  ///   - iceServers: The URLs of one ICE server; none leaves the configuration without one.
  /// - Throws: ``BridgeError/signaling(_:)`` when WebRTC cannot create the connection or the
  ///   channel.
  public init(role: SignalingRole, iceServers: [String] = []) throws {
    self.role = role
    super.init()
    let configuration = LKRTCConfiguration()
    configuration.sdpSemantics = .unifiedPlan
    configuration.tcpCandidatePolicy = .disabled
    configuration.iceServers = iceServers.isEmpty ? [] : [LKRTCIceServer(urlStrings: iceServers)]
    let constraints = LKRTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
    guard
      let created = Self.factory.peerConnection(
        with: configuration,
        constraints: constraints,
        delegate: self
      )
    else { throw BridgeError.signaling("WebRTC could not create a peer connection.") }
    self.connection = created
    if role == .offer {
      let settings = LKRTCDataChannelConfiguration()
      settings.isOrdered = true
      guard
        let opened = created.dataChannel(
          forLabel: Self.channelLabel,
          configuration: settings
        )
      else { throw BridgeError.signaling("WebRTC could not create the data channel.") }
      attach(opened)
    }
  }

  /// Creates the local description, waits for ICE gathering to finish, and encodes the result.
  ///
  /// The answerer calls ``accept(_:)`` first.
  ///
  /// - Returns: The offer blob for the offerer, and the answer blob for the answerer.
  /// - Throws: ``BridgeError/signaling(_:)`` when WebRTC creates no description, or the error of
  ///   WebRTC.
  public func localBlob() async throws -> String {
    let constraints = LKRTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
    let description: LKRTCSessionDescription =
      try await withCheckedThrowingContinuation { continuation in
        let completion: @Sendable (LKRTCSessionDescription?, Error?) -> Void = { sdp, error in
          if let sdp {
            continuation.resume(returning: sdp)
          } else {
            continuation.resume(throwing: error ?? BridgeError.signaling("No description."))
          }
        }
        if role == .offer {
          connection.offer(for: constraints, completionHandler: completion)
        } else {
          connection.answer(for: constraints, completionHandler: completion)
        }
      }
    try await setLocal(description)
    await waitForGathering()
    guard let local = connection.localDescription else {
      throw BridgeError.signaling("The peer connection has no local description.")
    }
    return try Self.encode(local)
  }

  /// Applies the peer's blob: the answer for the offerer, the offer for the answerer.
  public func accept(_ blob: String) async throws {
    let description = try Self.decode(blob)
    let expected: LKRTCSdpType = role == .offer ? .answer : .offer
    guard description.type == expected else {
      throw BridgeError.signaling("Expected an \(role == .offer ? "answer" : "offer") blob.")
    }
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      connection.setRemoteDescription(description) { error in
        if let error { continuation.resume(throwing: error) } else { continuation.resume() }
      }
    }
  }

  /// Returns when the data channel is open, at once when it already is.
  public func waitUntilOpen() async {
    await withCheckedContinuation { continuation in
      lock.lock()
      if channel?.readyState == .open {
        lock.unlock()
        continuation.resume()
      } else {
        openWaiters.append(continuation)
        lock.unlock()
      }
    }
  }

  /// Sends the data as a text message over the data channel.
  ///
  /// - Returns: Whether the channel accepted the message; false when there is no channel.
  @discardableResult
  public func send(_ data: Data) -> Bool {
    lock.lock()
    let current = channel
    lock.unlock()
    return current?.sendData(LKRTCDataBuffer(data: data, isBinary: false)) ?? false
  }

  /// Closes the data channel and the peer connection.
  public func close() {
    channel?.close()
    connection.close()
  }

  /// Applies the description as the local description of the peer connection.
  private func setLocal(_ description: LKRTCSessionDescription) async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      connection.setLocalDescription(description) { error in
        if let error { continuation.resume(throwing: error) } else { continuation.resume() }
      }
    }
  }

  /// Returns when ICE gathering is complete, at once when it already is.
  private func waitForGathering() async {
    await withCheckedContinuation { continuation in
      lock.lock()
      if connection.iceGatheringState == .complete {
        lock.unlock()
        continuation.resume()
      } else {
        gatheringWaiters.append(continuation)
        lock.unlock()
      }
    }
  }

  /// Stores the data channel and makes this link its delegate.
  private func attach(_ channel: LKRTCDataChannel) {
    lock.lock()
    self.channel = channel
    lock.unlock()
    channel.delegate = self
  }

  /// The blob of a description: base64 of a JSON object with `type` and `sdp`.
  private static func encode(_ description: LKRTCSessionDescription) throws -> String {
    let object = [
      "type": LKRTCSessionDescription.string(for: description.type), "sdp": description.sdp,
    ]
    return try JSONSerialization.data(withJSONObject: object).base64EncodedString()
  }

  /// The description in a blob.
  ///
  /// - Throws: ``BridgeError/signaling(_:)`` when the blob is longer than
  ///   `PeerMessage.maximumBytes` or is not a session description.
  static func decode(_ blob: String) throws -> LKRTCSessionDescription {
    guard blob.utf8.count <= PeerMessage.maximumBytes else {
      throw BridgeError.signaling("The blob is longer than \(PeerMessage.maximumBytes) bytes.")
    }
    guard let data = Data(base64Encoded: blob.trimmingCharacters(in: .whitespacesAndNewlines)),
      let object = try? JSONSerialization.jsonObject(with: data) as? [String: String],
      let type = object["type"], let sdp = object["sdp"]
    else { throw BridgeError.signaling("The blob is not a session description.") }
    return LKRTCSessionDescription(type: LKRTCSessionDescription.type(for: type), sdp: sdp)
  }
}

extension PeerLink: LKRTCPeerConnectionDelegate {
  /// Ignores signaling state changes.
  public func peerConnection(
    _: LKRTCPeerConnection,
    didChange _: LKRTCSignalingState
  ) {}
  /// Ignores added media streams; the link carries only a data channel.
  public func peerConnection(
    _: LKRTCPeerConnection,
    didAdd _: LKRTCMediaStream
  ) {}
  /// Ignores removed media streams.
  public func peerConnection(
    _: LKRTCPeerConnection,
    didRemove _: LKRTCMediaStream
  ) {}
  /// Ignores negotiation requests; the offer is made once, by ``localBlob()``.
  public func peerConnectionShouldNegotiate(_: LKRTCPeerConnection) {}
  /// Ignores ICE connection state changes.
  public func peerConnection(
    _: LKRTCPeerConnection,
    didChange _: LKRTCIceConnectionState
  ) {}
  /// Ignores single candidates; the blob carries them after gathering completes.
  public func peerConnection(
    _: LKRTCPeerConnection,
    didGenerate _: LKRTCIceCandidate
  ) {}
  /// Ignores removed candidates.
  public func peerConnection(
    _: LKRTCPeerConnection,
    didRemove _: [LKRTCIceCandidate]
  ) {}

  /// Resumes the tasks that wait for gathering when ICE gathering completes.
  public func peerConnection(
    _: LKRTCPeerConnection,
    didChange newState: LKRTCIceGatheringState
  ) {
    guard newState == .complete else { return }
    lock.lock()
    let waiters = gatheringWaiters
    gatheringWaiters = []
    lock.unlock()
    for waiter in waiters { waiter.resume() }
  }

  /// Attaches the data channel that the offerer opened, and reports it when it is open.
  public func peerConnection(
    _: LKRTCPeerConnection,
    didOpen dataChannel: LKRTCDataChannel
  ) {
    attach(dataChannel)
    if dataChannel.readyState == .open { opened() }
  }
}

extension PeerLink: LKRTCDataChannelDelegate {
  /// Reports the channel when its state is open.
  public func dataChannelDidChangeState(_ dataChannel: LKRTCDataChannel) {
    if dataChannel.readyState == .open { opened() }
  }

  /// Passes the message to ``onMessage``.
  public func dataChannel(
    _: LKRTCDataChannel,
    didReceiveMessageWith buffer: LKRTCDataBuffer
  ) {
    onMessage?(buffer.data)
  }

  /// Resumes the tasks that wait for the channel to open, and calls ``onOpen``.
  private func opened() {
    lock.lock()
    let waiters = openWaiters
    openWaiters = []
    lock.unlock()
    for waiter in waiters { waiter.resume() }
    onOpen?()
  }
}
