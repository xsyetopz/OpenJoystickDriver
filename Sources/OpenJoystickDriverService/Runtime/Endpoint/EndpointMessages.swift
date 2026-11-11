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

/// A line that a client sends: `Hello` first, then any `ProfileRequest`, `ModList`, or
/// `OutputRequest`, then `Subscription` or `FeedRequest`.
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
    /// A request to activate, deactivate, or change one remapping profile.
    case profileRequest = "ProfileRequest"
    /// A request for the installed mod packages.
    case modList = "ModList"
    /// A request to rumble, set the player indicator, or set the light of one controller.
    case outputRequest = "OutputRequest"

    /// Whether the client sends the kind to get an answer, after which it may send another line.
    var isCommand: Bool { [.profileRequest, .modList, .outputRequest].contains(self) }
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

/// A `ProfileRequest` line: `ojd profile activate`, `deactivate`, or `set` for one profile.
struct EndpointProfileRequest: Decodable, Sendable {
  /// What the request does to the profile.
  enum Operation: Sendable {
    /// Activates the profile.
    case activate
    /// Deactivates the profile.
    case deactivate
    /// Sets the value at the key; `null` removes a member.
    case set(ProfileKey, ProfileValue)
  }

  /// The members of the line.
  private enum CodingKeys: String, CodingKey {
    /// The key of the operation name.
    case action
    /// The key of the profile selector.
    case profile
    /// The key of the profile key to set.
    case key
    /// The key of the value to set.
    case value
  }

  /// The profile that the UUID or the name selects.
  let profile: ProfileSelector
  /// What to do to it.
  let operation: Operation

  /// Decodes the line; `set` needs a key and a `value`, which may be `null`.
  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    guard
      let selector = ProfileSelector(argument: try container.decode(String.self, forKey: .profile))
    else {
      throw DecodingError.dataCorruptedError(
        forKey: .profile,
        in: container,
        debugDescription: "The profile selector is empty."
      )
    }
    self.profile = selector
    switch try container.decode(String.self, forKey: .action) {
    case "Activate": operation = .activate
    case "Deactivate": operation = .deactivate
    case "Set":
      guard let key = ProfileKey(argument: try container.decode(String.self, forKey: .key)) else {
        throw DecodingError.dataCorruptedError(
          forKey: .key,
          in: container,
          debugDescription: "The key has an empty part."
        )
      }
      operation = .set(key, try container.decode(ProfileValue.self, forKey: .value))
    default:
      throw DecodingError.dataCorruptedError(
        forKey: .action,
        in: container,
        debugDescription: "The action is Activate, Deactivate, or Set."
      )
    }
  }
}

/// The answer to a `ProfileRequest`: the profile as the service reports it afterward.
struct EndpointProfileResult: Encodable, Sendable {
  /// The version of the endpoint API.
  let apiVersion = OpenJoystickDriverAPI.version
  /// The kind of the line, `ProfileResult`.
  let kind = "ProfileResult"
  /// The profile after the request.
  let profile: AutomationProfile
}

/// An `OutputRequest` line: `ojd controller rumble`, `player`, or `light` for one controller.
struct EndpointOutputRequest: Decodable, Sendable {
  /// The output that the request drives.
  enum Output: Sendable {
    /// Runs the rumble motors; the intensities are those of `ojd controller rumble`.
    case rumble(RumbleIntensities, seconds: Double)
    /// Sets the player indicator.
    case player(PhysicalPlayerIndicator)
    /// Sets the lightbar color, the LED brightness, or both.
    case light(color: ControllerColor?, brightness: UInt8?)
  }

  /// The members of the line.
  private enum CodingKeys: String, CodingKey {
    /// The key of the controller reference.
    case controller
    /// The key of the output name.
    case action
    /// The key of the left main motor.
    case left
    /// The key of the right main motor.
    case right
    /// The key of the left trigger motor.
    case leftTrigger
    /// The key of the right trigger motor.
    case rightTrigger
    /// The key of the rumble duration.
    case duration
    /// The key of the player number.
    case player
    /// The key of the light color.
    case color
    /// The key of the light brightness.
    case brightness
  }

  /// The port key, session token, or `VVVV:PPPP` model of the controller.
  let controller: String
  /// What to send to it.
  let output: Output

  /// Decodes the line; a duration, a player number, or a color out of range, and a `Light` that
  /// names neither a color nor a brightness, fail.
  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    controller = try container.decode(String.self, forKey: .controller)
    switch try container.decode(String.self, forKey: .action) {
    case "Rumble":
      let seconds =
        try container.decodeIfPresent(Double.self, forKey: .duration)
        ?? RumbleDuration.manualTestSeconds
      guard ControllerOutput.isValidRumbleDuration(seconds) else {
        throw DecodingError.dataCorruptedError(
          forKey: .duration,
          in: container,
          debugDescription: "The duration is above 0 and within the maximum."
        )
      }
      output = .rumble(
        .manualTest(
          lowFrequency: try container.decodeIfPresent(UInt8.self, forKey: .left),
          highFrequency: try container.decodeIfPresent(UInt8.self, forKey: .right),
          leftTrigger: try container.decodeIfPresent(UInt8.self, forKey: .leftTrigger),
          rightTrigger: try container.decodeIfPresent(UInt8.self, forKey: .rightTrigger)
        ),
        seconds: seconds
      )
    case "Player":
      guard
        let indicator = PhysicalPlayerIndicator(
          rawValue: try container.decode(Int.self, forKey: .player)
        )
      else {
        throw DecodingError.dataCorruptedError(
          forKey: .player,
          in: container,
          debugDescription: "The player is a number from 0 to 4."
        )
      }
      output = .player(indicator)
    case "Light":
      let hex = try container.decodeIfPresent(String.self, forKey: .color)
      let color = hex.flatMap(ControllerColor.init(hex:))
      let brightness = try container.decodeIfPresent(UInt8.self, forKey: .brightness)
      guard (hex == nil) == (color == nil), hex != nil || brightness != nil else {
        throw DecodingError.dataCorruptedError(
          forKey: .color,
          in: container,
          debugDescription: "The light needs a color as RRGGBB or a brightness."
        )
      }
      output = .light(color: color, brightness: brightness)
    default:
      throw DecodingError.dataCorruptedError(
        forKey: .action,
        in: container,
        debugDescription: "The output is Rumble, Player, or Light."
      )
    }
  }
}

/// The answer to an `OutputRequest`: what the controller did with each command.
struct EndpointOutputResult: Encodable, Sendable {
  /// The version of the endpoint API.
  let apiVersion = OpenJoystickDriverAPI.version
  /// The kind of the line, `OutputResult`.
  let kind = "OutputResult"
  /// The session ID of the controller.
  let controller: String
  /// One entry for each command sent.
  let results: [ControllerOutputEntry]

  /// Reports `result`.
  init(_ result: AutomationOutputResult) {
    controller = result.controller
    results = result.results
  }
}

/// The answer to a `ModList`:the installed mod packages, as `ojd mod list` prints them.
struct EndpointMods: Encodable, Equatable, Sendable {
  /// The version of the endpoint API.
  let apiVersion = OpenJoystickDriverAPI.version
  /// The kind of the line, `Mods`.
  let kind = "Mods"
  /// The packages of the store in name order, with the ones that cannot be used included.
  let mods: [ModPackageEntry]
}

/// The saved profiles that a `Profiles` subscription sends at once and after each change.
struct EndpointProfiles: Encodable, Equatable, Sendable {
  /// The version of the endpoint API.
  let apiVersion = OpenJoystickDriverAPI.version
  /// The kind of the line, `Profiles`.
  let kind = "Profiles"
  /// The profiles as the service reports them.
  let profiles: [AutomationProfile]
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
    guard let code = peer.code(), let signer = CodeSigningIdentity.of(code),
      unsafe SecCodeCopyStaticCode(code, SecCSFlags(), &staticCode) == errSecSuccess, let staticCode
    else { return nil }
    if signer.kind != .adHoc, !peer.satisfies(signer.requirement) { return nil }
    var url: CFURL?
    let copiedPath =
      unsafe SecCodeCopyPath(staticCode, SecCSFlags(), &url) == errSecSuccess
      ? (url as URL?)?.path : nil
    return Self(identity: signer, path: copiedPath)
  }
}
