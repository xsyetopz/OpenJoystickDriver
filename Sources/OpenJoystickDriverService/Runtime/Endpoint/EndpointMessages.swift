import Foundation
import OpenJoystickDriverKit
import Security

/// The first line on every connection: a random nonce that a token client signs in its `hello`.
struct EndpointChallenge: Encodable, Sendable {
  let type = "challenge"
  /// 32 random bytes in unpadded base64url.
  let nonce: String
}

/// A line that a client sends: `hello` first, then `subscribe` or `feed`.
struct EndpointRequest: Decodable, Sendable {
  enum Kind: String, Decodable, Sendable {
    case hello
    case subscribe
    case feed
  }

  let type: Kind
  /// `hello` only.
  let `protocol`: Int?
  /// `hello` only.
  let scopes: [EndpointScope]?
  /// `hello` only; the name of a token from `ojd access grant --token`, instead of the signature.
  let tokenName: String?
  /// `hello` only, with `tokenName`; the lowercase hex HMAC-SHA256 of the challenge, keyed with
  /// the SHA-256 of the token.
  let proof: String?
  /// `subscribe` only; `controllers` is the one stream.
  let stream: String?
  /// `subscribe` only; adds the virtual gamepad's values to `input` lines.
  let output: Bool?
  /// `feed` only; the virtual HID profile of the gamepad, such as `hid-generic`.
  let `as`: String?
}

struct EndpointWelcome: Encodable, Sendable {
  let type = "welcome"
  let `protocol`: Int
  let version: String
  let scopes: [EndpointScope]
}

/// The answer to `feed`: the virtual gamepad exists and takes frame lines.
struct EndpointFeeding: Encodable, Sendable {
  let type = "feeding"
  let `as`: String
}

/// An error line; `code` is an endpoint-domain `ErrorCode`, described in `endpoint.schema.json`.
struct EndpointError: Encodable, Sendable {
  let type = "error"
  let code: ErrorCode
  /// English text for logs; clients branch on `code`.
  let message: String
  /// The protocol versions the service accepts; `E1003` only.
  var supported: [Int]?
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
