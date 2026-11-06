import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverMacOSPlatform
import Security

/// The first line on every connection: a random nonce that a token client signs in its `Hello`.
struct EndpointChallenge: Encodable, Sendable {
  /// The version of the endpoint API.
  let apiVersion = OpenJoystickDriverAPI.version
  /// The kind of the line, `Challenge`.
  let kind = "Challenge"
  /// 32 random bytes in unpadded base64url.
  let nonce: String
}

/// A line that a client sends: `Hello` first, then `Subscription` or `FeedRequest`.
///
/// A line is checked by ``EndpointHeader`` first: a missing header is answered with `E1011`, an
/// unsupported `apiVersion` with `E1009`, and an unknown kind, or one that is not accepted at
/// that point, with `E1010`. A line that fails to decode after that gets `E1003`.
struct EndpointRequest: Decodable, Sendable {
  /// The kinds of line that a client sends.
  enum Kind: String, Decodable, Sendable {
    /// The first line, which names the scopes and the proof of the client.
    case hello = "Hello"
    /// A request for a stream of controller values.
    case subscription = "Subscription"
    /// A request for a virtual gamepad that takes `Frame` lines.
    case feedRequest = "FeedRequest"
  }

  /// The version of the endpoint API that the client speaks.
  let apiVersion: String
  /// The kind of the line.
  let kind: Kind
  /// `Hello` only.
  let scopes: [EndpointScope]?
  /// `Hello` only; the name of a token from `ojd access grant --token`, instead of the signature.
  let tokenName: String?
  /// `Hello` only, with `tokenName`; the lowercase hex HMAC-SHA256 of the challenge, keyed with
  /// the SHA-256 of the token.
  let proof: String?
  /// `Subscription` only; `Controllers` is the one stream.
  let stream: String?
  /// `Subscription` only; adds the virtual gamepad's values to the objects of the watch lines.
  let output: Bool?
  /// `FeedRequest` only; the persona id of the gamepad, a ``VirtualHIDProfileID`` raw value.
  let `as`: String?
}

/// The answer to a `Hello` that is accepted.
struct EndpointWelcome: Encodable, Sendable {
  /// The version of the endpoint API.
  let apiVersion = OpenJoystickDriverAPI.version
  /// The kind of the line, `Welcome`.
  let kind = "Welcome"
  /// The version of the service.
  let version: String
  /// The scopes that the connection holds.
  let scopes: [EndpointScope]
}

/// The answer to `FeedRequest`: the virtual gamepad exists and takes `Frame` lines.
struct EndpointFeedSession: Encodable, Sendable {
  /// The version of the endpoint API.
  let apiVersion = OpenJoystickDriverAPI.version
  /// The kind of the line, `FeedSession`.
  let kind = "FeedSession"
  /// The persona of the virtual gamepad.
  let `as`: VirtualHIDProfileID
}

/// The answer to `Drain`: every frame sent before it has played, the last one for its full time.
struct EndpointDrained: Encodable, Sendable {
  /// The version of the endpoint API.
  let apiVersion = OpenJoystickDriverAPI.version
  /// The kind of the line, `Drained`.
  let kind = "Drained"
}

/// A `RumbleCommand` line: the host's rumble command with `apiVersion` and `kind`.
struct EndpointRumbleCommand: Encodable, Sendable {
  /// The rumble command of the host.
  let command: RumbleCommandLine

  /// Creates the line for `command`.
  init(_ command: RumbleCommandLine) { self.command = command }

  /// The keys that the line adds to the command.
  private enum CodingKeys: String, CodingKey {
    /// The key of the API version.
    case apiVersion
    /// The key of the kind.
    case kind
  }

  /// Encodes the rumble command with the API version and the kind.
  func encode(to encoder: any Encoder) throws {
    try command.encode(to: encoder)
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(OpenJoystickDriverAPI.version, forKey: .apiVersion)
    try container.encode(RumbleCommandLine.kind, forKey: .kind)
  }
}

/// A `Frame` line: the frame body that `ojd virtual feed` takes with `apiVersion` and `kind`.
struct EndpointFrame: Encodable, Sendable {
  /// The frame body.
  let frame: VirtualFeedFrame

  /// Creates the line for `frame`.
  init(_ frame: VirtualFeedFrame) { self.frame = frame }

  /// The keys that the line adds to the frame.
  private enum CodingKeys: String, CodingKey {
    /// The key of the API version.
    case apiVersion
    /// The key of the kind.
    case kind
  }

  /// Encodes the frame with the API version and the kind.
  func encode(to encoder: any Encoder) throws {
    try frame.encode(to: encoder)
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(OpenJoystickDriverAPI.version, forKey: .apiVersion)
    try container.encode(VirtualFeedFrame.kind, forKey: .kind)
  }
}

/// A `Status` failure line; `code` is an endpoint-domain `ErrorCode`, described in
/// `endpoint.schema.json`.
struct EndpointError: Encodable, Error, Sendable {
  /// The extra facts of a failure.
  struct Details: Encodable, Sendable {
    /// The `apiVersion` values the service accepts; `E1009`, `E1010` and `E1011` only.
    let supportedAPIVersions: [String]
  }

  /// The version of the endpoint API.
  let apiVersion = OpenJoystickDriverAPI.version
  /// The kind of the line, `Status`.
  let kind = "Status"
  /// The status of the line, `Failure`.
  let status = "Failure"
  /// The error code of the failure.
  let code: ErrorCode
  /// English text for logs; clients branch on `code`.
  let message: String
  /// The details of the failure, when it has any.
  var details: Details?

  /// A refusal of a line's header, which lists the versions the service speaks.
  init(header code: ErrorCode, message: String) {
    self.init(code: code, message: message)
    details = .init(supportedAPIVersions: [OpenJoystickDriverAPI.version])
  }

  /// Creates the failure with `code` and `message` and no details.
  init(code: ErrorCode, message: String) {
    self.code = code
    self.message = message
  }
}

/// The client behind an endpoint connection, as its code signature identifies it.
struct EndpointClient: Sendable {
  /// The code-signing identity of the client.
  let identity: CodeSigningIdentity
  /// The client's executable, when Security can name it; for display only.
  let path: String?

  /// Reads the peer's signature from its audit token.
  ///
  /// Nil when Security cannot resolve the code, or when the running code does not satisfy the
  /// requirement of the signature on disk, such as a binary modified after it started.
  static func identify(_ peer: LocalSocketPeer) -> Self? {
    var staticCode: SecStaticCode?
    guard let code = peer.code(), let identity = CodeSigningIdentity.of(code),
      SecCodeCopyStaticCode(code, SecCSFlags(), &staticCode) == errSecSuccess, let staticCode
    else { return nil }
    if identity.kind != .adHoc, !peer.satisfies(identity.requirement) { return nil }
    var url: CFURL?
    let path =
      SecCodeCopyPath(staticCode, SecCSFlags(), &url) == errSecSuccess ? (url as URL?)?.path : nil
    return Self(identity: identity, path: path)
  }
}
