import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverMacOSPlatform

/// The failure to read, change or write the access grants.
enum AccessGrantStoreError: Error, Equatable, LocalizedError, Sendable {
  /// The file is damaged.
  case damaged
  /// The file's `apiVersion` or `kind` is not the supported one; the text says what was found. A
  /// missing or unknown `apiVersion` is E5001, as for every document; a wrong `kind` is a damaged
  /// file.
  case unsupported(DocumentHeaderProblem)
  /// No client or token has the ID.
  case unknownClient(String)
  /// Clients of this kind cannot be granted.
  case notGrantable(CodeSigningIdentity.Kind)
  /// The grant names no scope.
  case noScope
  /// The service is stopping.
  case serviceStopped
  /// A token has the name already.
  case duplicateToken(String)
  /// The name is not a valid token name.
  case invalidTokenName(String)
  /// The origin is not a valid web origin.
  case invalidOrigin(String)
  /// The WebSocket cannot use the port.
  case portUnavailable(Int)
  /// A token with origins cannot hold the `control` scope.
  case originsWithControl

  /// The code, then what it means and how to fix it, in the language of the user, then the value
  /// that the error is about.
  private static func coded(_ code: ErrorCode, detail: String? = nil) -> String {
    "\(code.rawValue): \(code.localizedExplanation)" + (detail.map { " (\($0))" } ?? "")
  }

  /// The code of the error, whose localized text `errorDescription` leads with.
  var code: ErrorCode {
    switch self {
    case .damaged: .damagedAccessGrants
    case .unsupported(let problem): problem.code ?? .damagedAccessGrants
    case .unknownClient: .unknownAccessClient
    case .notGrantable: .ungrantableClient
    case .noScope: .noAccessScope
    case .serviceStopped: .serviceStopping
    case .duplicateToken: .duplicateTokenName
    case .invalidTokenName: .invalidTokenName
    case .invalidOrigin: .invalidWebOrigin
    case .portUnavailable: .webPortUnavailable
    case .originsWithControl: .controlScopeWithOrigins
    }
  }

  /// The text that explains the failure to a user, led by its error code.
  var errorDescription: String? {
    switch self {
    case .damaged, .noScope, .serviceStopped, .originsWithControl:
      Self.coded(code)
    case .unsupported(let problem):
      Self.coded(code, detail: problem.message)
    case .unknownClient(let id): Self.coded(code, detail: id)
    case .notGrantable(let kind): Self.coded(code, detail: CommandLineName.kebab(kind.rawValue))
    case .duplicateToken(let name), .invalidTokenName(let name): Self.coded(code, detail: name)
    case .invalidOrigin(let origin): Self.coded(code, detail: origin)
    case .portUnavailable(let port): Self.coded(code, detail: String(port))
    }
  }
}

/// The contents of `AccessGrants.json`: whether the endpoint and its WebSocket are on, and the
/// granted clients and tokens.
struct AccessGrantFile: Equatable, Sendable {
  /// The `kind` of the file.
  static let kind = "AccessGrants"

  /// Whether the endpoint is on.
  var enabled = false
  /// The granted clients.
  var grants: [AccessGrant] = []
  /// The granted tokens.
  var tokens: [AccessTokenGrant] = []
  /// The settings of the WebSocket.
  var web = AccessWebSettings()

  /// Returns the grant of the client `identity`, or nil when it has none.
  func grant(for identity: CodeSigningIdentity) -> AccessGrant? {
    grants.first { $0.identity == identity }
  }

  /// Adds `scopes` to the client's grant, or grants it; returns the grant as stored.
  @discardableResult
  mutating func grant(
    _ identity: CodeSigningIdentity,
    scopes: [EndpointScope],
    path: String,
    at date: Date
  ) -> AccessGrant {
    let previous = grant(for: identity)?.scopes ?? []
    let grant = AccessGrant(
      identity: identity,
      scopes: previous + scopes,
      grantedAt: ISO8601DateFormatter().string(from: date),
      path: path
    )
    if let index = grants.firstIndex(where: { $0.identity == identity }) {
      grants[index] = grant
    } else {
      grants.append(grant)
    }
    return grant
  }

  /// Removes `scopes`, or every scope when nil; returns the grant left, or nil when none is.
  mutating func revoke(id: String, scopes: [EndpointScope]?) throws -> AccessGrant? {
    guard let index = grants.firstIndex(where: { $0.identity.accessID == id }) else {
      throw AccessGrantStoreError.unknownClient(id)
    }
    let grant = grants[index]
    let remaining = scopes.map { revoked in grant.scopes.filter { !revoked.contains($0) } } ?? []
    guard !remaining.isEmpty else {
      grants.remove(at: index)
      return nil
    }
    grants[index] = AccessGrant(
      identity: grant.identity,
      scopes: remaining,
      grantedAt: grant.grantedAt,
      path: grant.path
    )
    return grants[index]
  }

  /// Whether every `control` scope carries `controlGrantedAt`, which the service writes with it,
  /// and no token with origins holds `control`, because a page never drives a virtual gamepad.
  ///
  /// A file that breaks either rule is damaged, and the user grants again.
  var controlScopesAreValid: Bool {
    grants.allSatisfy { !$0.scopes.contains(.control) || $0.controlGrantedAt != nil }
      && tokens.allSatisfy {
        !$0.scopes.contains(.control) || ($0.controlGrantedAt != nil && $0.origins.isEmpty)
      }
  }
}

/// The header of the file is not supported, with the problem.
struct AccessGrantHeaderProblem: Error, Equatable, Sendable {
  /// The problem that makes the header unsupported.
  let problem: DocumentHeaderProblem
}

extension AccessGrantFile: Codable {
  /// The keys of the file.
  private enum CodingKeys: String, CodingKey, CaseIterable {
    /// The keys of the header, the endpoint switch, the grants, the tokens and the web settings.
    case apiVersion, kind, enabled, grants, tokens, web
  }

  /// Decodes the file, rejects unknown keys and a header that is not supported.
  init(from decoder: any Decoder) throws {
    try decoder.rejectUnknownKeys(CodingKeys.self)
    let container = try decoder.container(keyedBy: CodingKeys.self)
    if let problem = OpenJoystickDriverAPI.headerProblem(
      apiVersion: try container.decodeIfPresent(String.self, forKey: .apiVersion),
      kind: try container.decodeIfPresent(String.self, forKey: .kind),
      expected: Self.kind
    ) {
      throw AccessGrantHeaderProblem(problem: problem)
    }
    enabled = try container.decode(Bool.self, forKey: .enabled)
    grants = try container.decode([AccessGrant].self, forKey: .grants)
    tokens = try container.decode([AccessTokenGrant].self, forKey: .tokens)
    web = try container.decode(AccessWebSettings.self, forKey: .web)
  }

  /// Encodes the file with its header.
  func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(OpenJoystickDriverAPI.version, forKey: .apiVersion)
    try container.encode(Self.kind, forKey: .kind)
    try container.encode(enabled, forKey: .enabled)
    try container.encode(grants, forKey: .grants)
    try container.encode(tokens, forKey: .tokens)
    try container.encode(web, forKey: .web)
  }
}

/// Reads and writes `AccessGrants.json`; the application service is its only writer.
///
/// A damaged file is an error, not an empty one, so a mistake never silently turns the endpoint
/// off or drops grants that the user would then grant again.
struct AccessGrantStore: Sendable {
  /// The name of the file.
  static let fileName = "AccessGrants.json"

  /// The location of the file.
  let url: URL

  /// Creates the store for the file in `directory`.
  init(directory: URL = RemappingProfileLibrary.defaultDirectory) {
    url = directory.appendingPathComponent(Self.fileName, isDirectory: false)
  }

  /// The folder whose files the WebSocket's port serves as overlay pages.
  var pagesDirectory: URL {
    url.deletingLastPathComponent().appendingPathComponent("Overlays", isDirectory: true)
  }

  /// Returns the file's contents, or an empty file when it does not exist.
  ///
  /// - Throws: ``AccessGrantStoreError/unsupported(_:)`` when the header is not supported, and
  ///   ``AccessGrantStoreError/damaged`` when the file cannot be decoded or breaks a rule.
  func load() throws -> AccessGrantFile {
    let data: Data
    do { data = try Data(contentsOf: url) } catch CocoaError.fileReadNoSuchFile {
      return AccessGrantFile()
    }
    let decoded: AccessGrantFile?
    do {
      decoded = try JSONDecoder().decode(AccessGrantFile.self, from: data)
    } catch let problem as AccessGrantHeaderProblem {
      throw AccessGrantStoreError.unsupported(problem.problem.located(in: url.path))
    } catch {
      decoded = nil
    }
    guard let file = decoded,
      file.grants.allSatisfy({ $0.identity.requirement != nil && !$0.scopes.isEmpty }),
      file.hasValidTokensAndWeb, file.controlScopesAreValid
    else { throw AccessGrantStoreError.damaged }
    return file
  }

  /// Writes `file` as JSON with owner-only permissions, creating the directory.
  func save(_ file: AccessGrantFile) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    try RemappingProfileLibrary.createPrivateDirectory(url.deletingLastPathComponent())
    try RemappingProfileLibrary.writePrivate(encoder.encode(file), to: url)
  }
}

/// The clients and tokens the endpoint refused in the last day, newest first, so `ojd access list`
/// can offer them for a grant.
struct AccessRefusalLog: Sendable {
  /// How long a refusal stays listed, in seconds.
  static let retention: TimeInterval = 86_400

  /// The refused clients with the time of the refusal, newest first.
  private var entries: [(client: AccessRefusedClient, date: Date)] = []
  /// The refused tokens with the time of the refusal, newest first.
  private var tokenEntries: [(token: AccessRefusedToken, date: Date)] = []

  /// Records that the client `identity` was refused for `scopes`, replacing an earlier refusal of
  /// the same client and dropping the ones past the retention.
  mutating func record(
    _ identity: CodeSigningIdentity,
    path: String?,
    scopes: [EndpointScope],
    at date: Date
  ) {
    let client = AccessRefusedClient(
      identity: identity,
      path: path,
      scopes: scopes,
      reason: ErrorCode.notGranted.rawValue,
      refusalTime: ISO8601DateFormatter().string(from: date)
    )
    entries.removeAll {
      $0.client.id == client.id || date.timeIntervalSince($0.date) > Self.retention
    }
    entries.insert((client, date), at: 0)
  }

  /// Records a `hello` whose token matched no grant, when `name` is nil, or was not granted the
  /// scopes or the origin.
  mutating func recordToken(
    name: String?,
    origin: String?,
    transport: AccessTransport,
    scopes: [EndpointScope],
    at date: Date
  ) {
    let token = AccessRefusedToken(
      name: name,
      origin: origin,
      transport: transport,
      scopes: scopes,
      reason: ErrorCode.notGranted.rawValue,
      refusalTime: ISO8601DateFormatter().string(from: date)
    )
    tokenEntries.removeAll {
      ($0.token.name, $0.token.origin, $0.token.transport) == (name, origin, transport)
        || date.timeIntervalSince($0.date) > Self.retention
    }
    tokenEntries.insert((token, date), at: 0)
  }

  /// Removes the refused client `id`.
  mutating func remove(id: String) { entries.removeAll { $0.client.id == id } }

  /// Returns the clients refused within the retention before `now`.
  func clients(at now: Date) -> [AccessRefusedClient] {
    entries.filter { now.timeIntervalSince($0.date) <= Self.retention }.map(\.client)
  }

  /// Returns the tokens refused within the retention before `now`.
  func tokens(at now: Date) -> [AccessRefusedToken] {
    tokenEntries.filter { now.timeIntervalSince($0.date) <= Self.retention }.map(\.token)
  }
}
