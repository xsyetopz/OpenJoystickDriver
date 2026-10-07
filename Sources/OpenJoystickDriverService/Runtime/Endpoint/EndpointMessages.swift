import Foundation
import OpenJoystickDriverKit
import Security

/// The first line on every connection: a random nonce that a token client signs in its `Hello`.
struct EndpointChallenge: Encodable, Sendable {
  let apiVersion = OpenJoystickDriverAPI.version
  let kind = "Challenge"
  /// 32 random bytes in unpadded base64url.
  let nonce: String
}

/// A line that a client sends: `Hello` first, then `Subscription` or `FeedRequest`.
///
/// A line with no `apiVersion`, or a missing or unknown `kind`, does not decode and is answered
/// like any other line that is not a request, with `E1004`.
struct EndpointRequest: Decodable, Sendable {
  enum Kind: String, Decodable, Sendable {
    case hello = "Hello"
    case subscription = "Subscription"
    case feedRequest = "FeedRequest"
  }

  let apiVersion: String
  let kind: Kind
  /// `Hello` only.
  let scopes: [EndpointScope]?
  /// `Hello` only; the name of a token from `ojd access grant --token`, instead of the signature.
  let tokenName: String?
  /// `Hello` only, with `tokenName`; the lowercase hex HMAC-SHA256 of the challenge, keyed with
  /// the SHA-256 of the token.
  let proof: String?
  /// `Subscription` only; `controllers` is the one stream.
  let stream: String?
  /// `Subscription` only; adds the virtual gamepad's values to the objects of the watch lines.
  let output: Bool?
  /// `FeedRequest` only; the virtual HID profile of the gamepad, such as `hid-generic`.
  let `as`: String?
}

struct EndpointWelcome: Encodable, Sendable {
  let apiVersion = OpenJoystickDriverAPI.version
  let kind = "Welcome"
  let version: String
  let scopes: [EndpointScope]
}

/// The answer to `FeedRequest`: the virtual gamepad exists and takes `Frame` lines.
struct EndpointFeedSession: Encodable, Sendable {
  let apiVersion = OpenJoystickDriverAPI.version
  let kind = "FeedSession"
  let `as`: String
}

/// A `RumbleCommand` line: the host's rumble command with `apiVersion` and `kind`.
struct EndpointRumbleCommand: Encodable, Sendable {
  let command: RumbleCommandLine

  init(_ command: RumbleCommandLine) { self.command = command }

  private enum CodingKeys: String, CodingKey {
    case apiVersion
    case kind
  }

  func encode(to encoder: any Encoder) throws {
    try command.encode(to: encoder)
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(OpenJoystickDriverAPI.version, forKey: .apiVersion)
    try container.encode(RumbleCommandLine.kind, forKey: .kind)
  }
}

/// A `Status` failure line; `code` is an endpoint-domain `ErrorCode`, described in
/// `endpoint.schema.json`.
struct EndpointError: Encodable, Sendable {
  struct Details: Encodable, Sendable {
    /// The `apiVersion` values the service accepts; `E1003` only.
    let supportedAPIVersions: [String]
  }

  let apiVersion = OpenJoystickDriverAPI.version
  let kind = "Status"
  let status = "Failure"
  let code: ErrorCode
  /// English text for logs; clients branch on `code`.
  let message: String
  var details: Details?
}

/// The client behind an endpoint connection, as its code signature identifies it.
struct EndpointClient: Sendable {
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
