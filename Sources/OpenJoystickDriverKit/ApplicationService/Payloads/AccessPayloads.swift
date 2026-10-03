import CryptoKit
import Foundation

/// What an endpoint client may do: `read` controller events, or `control` a virtual gamepad.
public enum EndpointScope: String, Codable, CaseIterable, Comparable, Sendable {
  case read
  case control

  public static func < (lhs: Self, rhs: Self) -> Bool {
    allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
  }
}

extension CodeSigningIdentity {
  /// The short ID that `ojd access` shows for a client: the first 8 hex digits of the SHA-256 of
  /// its kind, team, and signing identifier.
  public var accessID: String {
    let key = "\(kind.rawValue)\n\(teamIdentifier ?? "")\n\(identifier)"
    return SHA256.hash(data: Data(key.utf8)).prefix(4).map { String(format: "%02x", $0) }.joined()
  }
}

/// A client the user allowed to use the endpoint, as stored in `AccessGrants.json`.
public struct AccessGrant: Codable, Equatable, Sendable {
  public let kind: CodeSigningIdentity.Kind
  public let identifier: String
  public let teamIdentifier: String?
  /// Sorted, without repeats.
  public let scopes: [EndpointScope]
  /// ISO 8601 time of the latest `ojd access grant` for this client.
  public let grantedAt: String
  /// Where the client was when it was granted; for display only.
  public let path: String

  public init(
    identity: CodeSigningIdentity,
    scopes: [EndpointScope],
    grantedAt: String,
    path: String
  ) {
    kind = identity.kind
    identifier = identity.identifier
    teamIdentifier = identity.teamIdentifier
    self.scopes = Array(Set(scopes)).sorted()
    self.grantedAt = grantedAt
    self.path = path
  }

  public var identity: CodeSigningIdentity {
    CodeSigningIdentity(kind: kind, identifier: identifier, teamIdentifier: teamIdentifier)
  }
}

/// A grant as `ojd access` prints it, with its client ID.
public struct AccessGrantSummary: Codable, Equatable, Sendable {
  public let id: String
  public let kind: CodeSigningIdentity.Kind
  public let identifier: String
  public let teamIdentifier: String?
  public let scopes: [EndpointScope]
  public let grantedAt: String
  public let path: String

  public init(_ grant: AccessGrant) {
    id = grant.identity.accessID
    kind = grant.kind
    identifier = grant.identifier
    teamIdentifier = grant.teamIdentifier
    scopes = grant.scopes
    grantedAt = grant.grantedAt
    path = grant.path
  }
}

/// A client the endpoint refused in the last 24 hours.
public struct AccessRefusedClient: Codable, Equatable, Sendable {
  public let id: String
  public let kind: CodeSigningIdentity.Kind
  public let identifier: String
  public let teamIdentifier: String?
  /// The client's executable, when the service could read it.
  public let path: String?
  public let scopes: [EndpointScope]
  /// The error code the client got, such as `not-granted`.
  public let reason: String
  /// ISO 8601 time of the latest refusal.
  public let refusedAt: String

  public init(
    identity: CodeSigningIdentity,
    path: String?,
    scopes: [EndpointScope],
    reason: String,
    refusedAt: String
  ) {
    id = identity.accessID
    kind = identity.kind
    identifier = identity.identifier
    teamIdentifier = identity.teamIdentifier
    self.path = path
    self.scopes = Array(Set(scopes)).sorted()
    self.reason = reason
    self.refusedAt = refusedAt
  }

  public var identity: CodeSigningIdentity {
    CodeSigningIdentity(kind: kind, identifier: identifier, teamIdentifier: teamIdentifier)
  }
}

/// A client connected to the endpoint.
public struct AccessConnection: Codable, Equatable, Sendable {
  public let id: String
  public let identifier: String
  public let scopes: [EndpointScope]

  public init(identity: CodeSigningIdentity, scopes: [EndpointScope]) {
    id = identity.accessID
    identifier = identity.identifier
    self.scopes = scopes
  }
}

/// The endpoint's state, its grants, and the clients it refused recently.
public struct AccessStatusPayload: Codable, Equatable, Sendable {
  public let enabled: Bool
  /// Where the endpoint listens while it is enabled.
  public let socketPath: String
  public let connections: [AccessConnection]
  public let grants: [AccessGrantSummary]
  public let refused: [AccessRefusedClient]

  public init(
    enabled: Bool,
    socketPath: String,
    connections: [AccessConnection],
    grants: [AccessGrantSummary],
    refused: [AccessRefusedClient]
  ) {
    self.enabled = enabled
    self.socketPath = socketPath
    self.connections = connections
    self.grants = grants
    self.refused = refused
  }
}

package struct AccessEnabledArguments: Codable, Sendable {
  package let enabled: Bool
}

package struct AccessGrantArguments: Codable, Sendable {
  package let identity: CodeSigningIdentity
  package let path: String
  package let scopes: [EndpointScope]
}

package struct AccessRevokeArguments: Codable, Sendable {
  package let id: String
  /// Nil revokes every scope.
  package let scopes: [EndpointScope]?
}

/// The result of `ojd access revoke`.
public struct AccessRevokeResult: Codable, Equatable, Sendable {
  public let id: String
  /// The grant left after the revoke; nil when no scope is left.
  public let grant: AccessGrantSummary?
  /// Live connections that were closed with `revoked`.
  public let closedConnections: Int

  public init(id: String, grant: AccessGrantSummary?, closedConnections: Int) {
    self.id = id
    self.grant = grant
    self.closedConnections = closedConnections
  }
}
