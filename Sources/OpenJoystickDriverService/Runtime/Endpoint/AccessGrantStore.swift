import Foundation
import OpenJoystickDriverKit

enum AccessGrantStoreError: Error, Equatable, LocalizedError, Sendable {
  case damaged
  case unknownClient(String)
  case notGrantable(CodeSigningIdentity.Kind)
  case noScope
  case serviceStopped
  case duplicateToken(String)
  case invalidTokenName(String)
  case invalidOrigin(String)
  case portUnavailable(Int)

  var errorDescription: String? {
    switch self {
    case .damaged:
      "The endpoint access file \(AccessGrantStore.fileName) is damaged. "
        + "Fix or delete it, then try again."
    case .unknownClient(let id): "No endpoint client has the ID \(id)."
    case .notGrantable(let kind):
      "A client signed \(kind.rawValue) cannot be granted, because any local program can "
        + "claim its signature."
    case .noScope: "Choose at least one scope to grant."
    case .serviceStopped: "The service is stopping. Start it, then try again."
    case .duplicateToken(let name):
      "A token named \(name) exists. Revoke token:\(name) first, or choose another name."
    case .invalidTokenName(let name):
      "\"\(name)\" is not a token name. Use 1 to 64 letters, digits, dots, hyphens, or "
        + "underscores."
    case .invalidOrigin(let origin):
      "\"\(origin)\" is not a web origin. Use scheme://host[:port] with http or https, "
        + "such as http://127.0.0.1:8080."
    case .portUnavailable(let port):
      "Port \(port) on 127.0.0.1 is in use or cannot be opened. Choose another with --port."
    }
  }
}

/// The contents of `AccessGrants.json`: whether the endpoint and its WebSocket are on, and the
/// granted clients and tokens.
struct AccessGrantFile: Codable, Equatable, Sendable {
  var enabled = false
  var grants: [AccessGrant] = []
  var tokens: [AccessTokenGrant] = []
  var web = AccessWebSettings()

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
}

/// Reads and writes `AccessGrants.json`; the application service is its only writer.
///
/// A damaged file is an error, not an empty one, so a mistake never silently turns the endpoint
/// off or drops grants that the user would then grant again.
struct AccessGrantStore: Sendable {
  static let fileName = "AccessGrants.json"

  let url: URL

  init(directory: URL = RemappingProfileLibrary.defaultDirectory) {
    url = directory.appendingPathComponent(Self.fileName, isDirectory: false)
  }

  /// The folder whose files the WebSocket's port serves as overlay pages.
  var pagesDirectory: URL {
    url.deletingLastPathComponent().appendingPathComponent("Overlays", isDirectory: true)
  }

  func load() throws -> AccessGrantFile {
    let data: Data
    do { data = try Data(contentsOf: url) } catch CocoaError.fileReadNoSuchFile {
      return AccessGrantFile()
    }
    guard let file = try? JSONDecoder().decode(AccessGrantFile.self, from: data),
      file.grants.allSatisfy({ $0.identity.requirement != nil && !$0.scopes.isEmpty }),
      file.hasValidTokensAndWeb
    else { throw AccessGrantStoreError.damaged }
    return file
  }

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
  static let retention: TimeInterval = 86_400

  private var entries: [(client: AccessRefusedClient, date: Date)] = []
  private var tokenEntries: [(token: AccessRefusedToken, date: Date)] = []

  mutating func record(
    _ identity: CodeSigningIdentity,
    path: String?,
    scopes: [EndpointScope],
    reason: String,
    at date: Date
  ) {
    let client = AccessRefusedClient(
      identity: identity,
      path: path,
      scopes: scopes,
      reason: reason,
      refusedAt: ISO8601DateFormatter().string(from: date)
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
      reason: "not-granted",
      refusedAt: ISO8601DateFormatter().string(from: date)
    )
    tokenEntries.removeAll {
      ($0.token.name, $0.token.origin, $0.token.transport) == (name, origin, transport)
        || date.timeIntervalSince($0.date) > Self.retention
    }
    tokenEntries.insert((token, date), at: 0)
  }

  mutating func remove(id: String) { entries.removeAll { $0.client.id == id } }

  func clients(at now: Date) -> [AccessRefusedClient] {
    entries.filter { now.timeIntervalSince($0.date) <= Self.retention }.map(\.client)
  }

  func tokens(at now: Date) -> [AccessRefusedToken] {
    tokenEntries.filter { now.timeIntervalSince($0.date) <= Self.retention }.map(\.token)
  }
}
