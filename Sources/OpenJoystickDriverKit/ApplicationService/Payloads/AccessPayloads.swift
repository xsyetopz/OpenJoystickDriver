import CryptoKit
import Foundation

/// What an endpoint client may do: `Read` controller events, or `Control` a virtual gamepad.
public enum EndpointScope: String, Codable, CaseIterable, Comparable, Sendable {
  /// The client may receive controller events.
  case read = "Read"
  /// The client may drive a virtual gamepad.
  case control = "Control"

  /// The scope on the command line: the lowercase kebab-case form of its name, such as `read`.
  public var commandLineName: String { CommandLineName.kebab(rawValue) }

  /// Whether `lhs` ranks below `rhs`: `Read` is below `Control`.
  public static func < (lhs: Self, rhs: Self) -> Bool {
    lhs.declarationIndex < rhs.declarationIndex
  }

  /// The position of this scope in `allCases`.
  private var declarationIndex: Int {
    guard let index = Self.allCases.firstIndex(of: self) else {
      preconditionFailure("every case of a CaseIterable enum is in allCases")
    }
    return index
  }
}

extension CodeSigningIdentity {
  /// The short ID that `ojd access` shows for a client: the first 8 hex digits of the SHA-256 of
  /// its publisher kind, publisher ID, and signing identifier.
  public var accessID: String {
    let key = "\(kind.rawValue)\n\(publisherID ?? "")\n\(identifier)"
    return SHA256.hash(data: Data(key.utf8)).prefix(4).map { unsafe String(format: "%02x", $0) }
      .joined()
  }
}

/// A client the user allowed to use the endpoint, as stored in `AccessGrants.plist`.
public struct AccessGrant: Codable, Equatable, Sendable {
  /// How the client is signed.
  public let kind: CodeSigningIdentity.Kind
  /// The client's signing identifier.
  public let identifier: String
  /// The publisher's ID; nil when the signing kind has none.
  public let publisherID: String?
  /// Sorted, without repeats.
  public let scopes: [EndpointScope]
  /// ISO 8601 time of the latest `ojd access grant` for this client.
  public let grantedAt: String
  /// Where the client was when it was granted; for display only.
  public let path: String
  /// Set whenever the grant holds `control`, marking it as granted after the scope worked; a file
  /// with a `control` scope but no mark is damaged.
  public let controlGrantedAt: String?

  /// The keys of the JSON encoding.
  private enum CodingKeys: String, CodingKey, CaseIterable {
    /// The `publisher` key.
    case publisher
    /// The `identifier` key.
    case identifier
    /// The `scopes` key.
    case scopes
    /// The `grantedAt` key.
    case grantedAt
    /// The `path` key.
    case path
    /// The `controlGrantedAt` key.
    case controlGrantedAt
  }

  /// The `publisher` object of a stored grant.
  private struct StoredPublisher: Codable {
    /// How the client is signed.
    let kind: CodeSigningIdentity.Kind
    /// The publisher's ID; nil when the signing kind has none.
    let id: String?

    /// The keys of the JSON encoding.
    private enum CodingKeys: String, CodingKey, CaseIterable {
      /// The `kind` key.
      case kind
      /// The `id` key.
      case id
    }

    /// Creates the stored publisher from its values.
    init(kind: CodeSigningIdentity.Kind, id: String?) {
      self.kind = kind
      self.id = id
    }

    /// Decodes the value from `decoder`.
    init(from decoder: any Decoder) throws {
      try decoder.rejectUnknownKeys(CodingKeys.self)
      let container = try decoder.container(keyedBy: CodingKeys.self)
      kind = try container.decode(CodeSigningIdentity.Kind.self, forKey: .kind)
      id = try container.decodeIfPresent(String.self, forKey: .id)
    }
  }

  /// Decodes the value from `decoder`.
  public init(from decoder: any Decoder) throws {
    try decoder.rejectUnknownKeys(CodingKeys.self)
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let publisher = try container.decode(StoredPublisher.self, forKey: .publisher)
    kind = publisher.kind
    publisherID = publisher.id
    identifier = try container.decode(String.self, forKey: .identifier)
    scopes = try container.decode([EndpointScope].self, forKey: .scopes)
    grantedAt = try container.decode(String.self, forKey: .grantedAt)
    path = try container.decode(String.self, forKey: .path)
    controlGrantedAt = try container.decodeIfPresent(String.self, forKey: .controlGrantedAt)
  }

  /// Encodes the value into `encoder`.
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(StoredPublisher(kind: kind, id: publisherID), forKey: .publisher)
    try container.encode(identifier, forKey: .identifier)
    try container.encode(scopes, forKey: .scopes)
    try container.encode(grantedAt, forKey: .grantedAt)
    try container.encode(path, forKey: .path)
    try container.encodeIfPresent(controlGrantedAt, forKey: .controlGrantedAt)
  }

  /// Creates a grant for the client `identity`.
  ///
  /// The grant keeps `scopes` sorted and without repeats, and sets ``controlGrantedAt`` when they
  /// include `control`.
  public init(
    identity: CodeSigningIdentity,
    scopes: [EndpointScope],
    grantedAt: String,
    path: String
  ) {
    kind = identity.kind
    identifier = identity.identifier
    publisherID = identity.publisherID
    self.scopes = Array(Set(scopes)).sorted()
    self.grantedAt = grantedAt
    self.path = path
    controlGrantedAt = scopes.contains(.control) ? grantedAt : nil
  }

  /// The signing identity of the client.
  public var identity: CodeSigningIdentity {
    CodeSigningIdentity(kind: kind, identifier: identifier, publisherID: publisherID)
  }
}

/// Who published a client: how it was signed, and the publisher's ID when it has one.
public struct AccessPublisher: Codable, Equatable, Sendable {
  /// How the client is signed.
  public let kind: CodeSigningIdentity.Kind
  /// The publisher's ID; nil when the signing kind has none.
  public let id: String?

  /// Creates a publisher from its values.
  public init(kind: CodeSigningIdentity.Kind, id: String?) {
    self.kind = kind
    self.id = id
  }
}

/// A grant as `ojd access` prints it, with its client ID.
public struct AccessGrantSummary: Codable, Equatable, Sendable {
  /// The client ID, the short ID that `ojd access` shows.
  public let id: String
  /// The publisher, a sub-object because every `--json` document has its own `kind`.
  public let publisher: AccessPublisher
  /// The client's signing identifier.
  public let identifier: String
  /// What the client may do.
  public let scopes: [EndpointScope]
  /// RFC 3339 time of the latest grant.
  public let grantTime: String
  /// Where the client was when it was granted.
  public let path: String

  /// Creates the summary of `grant`.
  public init(_ grant: AccessGrant) {
    id = grant.identity.accessID
    publisher = AccessPublisher(kind: grant.kind, id: grant.publisherID)
    identifier = grant.identifier
    scopes = grant.scopes
    grantTime = grant.grantedAt
    path = grant.path
  }
}

/// A client the endpoint refused in the last 24 hours.
public struct AccessRefusedClient: Codable, Equatable, Sendable {
  /// The client ID, the short ID that `ojd access` shows.
  public let id: String
  /// Who published the client.
  public let publisher: AccessPublisher
  /// The client's signing identifier.
  public let identifier: String
  /// The client's executable, when the service could read it.
  public let path: String?
  /// What the client asked for.
  public let scopes: [EndpointScope]
  /// The error code the client got, such as `E1002`.
  public let reason: String
  /// RFC 3339 time of the latest refusal.
  public let refusalTime: String

  /// Creates a refused-client entry for `identity`; `scopes` is sorted and without repeats.
  public init(
    identity: CodeSigningIdentity,
    path: String?,
    scopes: [EndpointScope],
    reason: String,
    refusalTime: String
  ) {
    id = identity.accessID
    publisher = AccessPublisher(kind: identity.kind, id: identity.publisherID)
    identifier = identity.identifier
    self.path = path
    self.scopes = Array(Set(scopes)).sorted()
    self.reason = reason
    self.refusalTime = refusalTime
  }

  /// The signing identity of the refused client.
  public var identity: CodeSigningIdentity {
    CodeSigningIdentity(
      kind: publisher.kind,
      identifier: identifier,
      publisherID: publisher.id
    )
  }
}

/// How a client reaches the endpoint: the Unix socket, or the WebSocket on `127.0.0.1`.
public enum AccessTransport: String, Codable, Sendable {
  /// The client connected through the Unix socket.
  case socket = "Socket"
  /// The client connected through the WebSocket.
  case web = "Web"
}

/// A client connected to the endpoint.
public struct AccessConnection: Codable, Equatable, Sendable {
  /// The client ID, or `token:NAME` for a token client.
  public let id: String
  /// The signing identifier, or the token name.
  public let identifier: String
  /// What the client may do.
  public let scopes: [EndpointScope]
  /// How the client reached the endpoint.
  public let transport: AccessTransport

  /// Creates a connection entry from its values.
  public init(id: String, identifier: String, scopes: [EndpointScope], transport: AccessTransport) {
    self.id = id
    self.identifier = identifier
    self.scopes = scopes
    self.transport = transport
  }

  /// Creates the entry of a socket client signed as `identity`.
  public init(identity: CodeSigningIdentity, scopes: [EndpointScope]) {
    self.init(
      id: identity.accessID,
      identifier: identity.identifier,
      scopes: scopes,
      transport: .socket
    )
  }
}

/// A token grant as `ojd access` prints it; the token itself is shown only when it is granted.
public struct AccessTokenSummary: Codable, Equatable, Sendable {
  /// `token:NAME`.
  public let id: String
  /// The name of the token grant.
  public let name: String
  /// The web origins, as `scheme://host[:port]`, whose pages may use the token on the WebSocket.
  public let origins: [String]
  /// What the token may do.
  public let scopes: [EndpointScope]
  /// RFC 3339 time of the latest grant.
  public let grantTime: String

  /// Creates a token summary whose ID is `token:` followed by `name`.
  public init(name: String, origins: [String], scopes: [EndpointScope], grantTime: String) {
    id = "token:\(name)"
    self.name = name
    self.origins = origins
    self.scopes = scopes
    self.grantTime = grantTime
  }
}

/// A `hello` with a token that the endpoint refused in the last 24 hours.
public struct AccessRefusedToken: Codable, Equatable, Sendable {
  /// The grant the token belongs to; nil for a token that matches no grant.
  public let name: String?
  /// The page's origin; WebSocket only.
  public let origin: String?
  /// How the client reached the endpoint.
  public let transport: AccessTransport
  /// What the client asked for; sorted and without repeats.
  public let scopes: [EndpointScope]
  /// Why the endpoint refused the token.
  public let reason: String
  /// RFC 3339 time of the latest refusal.
  public let refusalTime: String

  /// Creates a refused-token entry from its values; `scopes` is sorted and without repeats.
  public init(
    name: String?,
    origin: String?,
    transport: AccessTransport,
    scopes: [EndpointScope],
    reason: String,
    refusalTime: String
  ) {
    self.name = name
    self.origin = origin
    self.transport = transport
    self.scopes = Array(Set(scopes)).sorted()
    self.reason = reason
    self.refusalTime = refusalTime
  }
}

/// The WebSocket and the overlay pages on `127.0.0.1`.
public struct AccessWebStatus: Codable, Equatable, Sendable {
  /// Whether the user turned the WebSocket on.
  public let enabled: Bool
  /// Whether the WebSocket accepts connections now.
  public let listening: Bool
  /// Nil until the first `ojd access web enable`, which picks a free port unless one is given.
  public let port: Int?
  /// `ws://127.0.0.1:PORT/endpoint`; nil without a port.
  public let url: String?
  /// `http://127.0.0.1:PORT/`, where the overlay pages are served; nil without a port.
  public let pagesURL: String?
  /// The folder the overlay pages are served from.
  public let pagesPath: String

  /// Creates the status; the URLs follow from `port`.
  public init(enabled: Bool, listening: Bool, port: Int?, pagesPath: String) {
    self.enabled = enabled
    self.listening = listening
    self.port = port
    url = port.map { "ws://127.0.0.1:\($0)/endpoint" }
    pagesURL = port.map { "http://127.0.0.1:\($0)/" }
    self.pagesPath = pagesPath
  }
}

/// The endpoint's state, its grants, and the clients it refused recently.
public struct AccessStatusPayload: Codable, Equatable, Sendable {
  /// Whether the endpoint is turned on.
  public let enabled: Bool
  /// Where the endpoint listens while it is enabled.
  public let socketPath: String
  /// The clients connected now.
  public let connections: [AccessConnection]
  /// The clients the user allowed.
  public let grants: [AccessGrantSummary]
  /// The clients the endpoint refused in the last 24 hours.
  public let refused: [AccessRefusedClient]
  /// The state of the WebSocket.
  public let web: AccessWebStatus
  /// The token grants.
  public let tokens: [AccessTokenSummary]
  /// The tokens the endpoint refused in the last 24 hours.
  public let refusedTokens: [AccessRefusedToken]

  /// Creates the status from its values.
  public init(
    enabled: Bool,
    socketPath: String,
    connections: [AccessConnection],
    grants: [AccessGrantSummary],
    refused: [AccessRefusedClient],
    web: AccessWebStatus,
    tokens: [AccessTokenSummary],
    refusedTokens: [AccessRefusedToken]
  ) {
    self.enabled = enabled
    self.socketPath = socketPath
    self.connections = connections
    self.grants = grants
    self.refused = refused
    self.web = web
    self.tokens = tokens
    self.refusedTokens = refusedTokens
  }
}

/// The result of `ojd access grant --token`: the token, which is shown only this once.
public struct AccessTokenGrantResult: Codable, Equatable, Sendable {
  /// The token, which the service does not keep.
  public let token: String
  /// The grant the token belongs to.
  public let grant: AccessTokenSummary

  /// Creates the result from its values.
  public init(token: String, grant: AccessTokenSummary) {
    self.token = token
    self.grant = grant
  }
}

/// The arguments of `setAccessEnabled`.
package struct AccessEnabledArguments: Codable, Sendable {
  /// Whether to turn the endpoint on.
  package let enabled: Bool
}

/// The arguments of `grantAccess`.
package struct AccessGrantArguments: Codable, Sendable {
  /// The signing identity of the client to allow.
  package let identity: CodeSigningIdentity
  /// Where the client is; for display only.
  package let path: String
  /// The scopes to add to the client's grant.
  package let scopes: [EndpointScope]
}

/// The arguments of `grantTokenAccess`.
package struct AccessTokenGrantArguments: Codable, Sendable {
  /// The name of the token grant.
  package let name: String
  /// The web origins whose pages may use the token.
  package let origins: [String]
  /// The scopes of the token.
  package let scopes: [EndpointScope]
}

/// The arguments of `setWebAccess`.
package struct AccessWebArguments: Codable, Sendable {
  /// Whether to turn the WebSocket on.
  package let enabled: Bool
  /// Nil keeps the saved port; 0 lets the system pick a free port.
  package let port: Int?
}

/// The arguments of `revokeAccess`.
package struct AccessRevokeArguments: Codable, Sendable {
  /// The client ID or `token:NAME` of the grant.
  package let id: String
  /// Nil revokes every scope.
  package let scopes: [EndpointScope]?
}

/// The result of `ojd access revoke`.
public struct AccessRevokeResult: Codable, Equatable, Sendable {
  /// The ID of the client or token that was revoked.
  public let id: String
  /// The client grant left after the revoke; nil when no scope is left or `id` is a token.
  public let grant: AccessGrantSummary?
  /// The token grant left after the revoke; nil when no scope is left or `id` is a client.
  public let token: AccessTokenSummary?
  /// Live connections that were closed with `E1005`.
  public let closedConnections: Int

  /// Creates the result from its values.
  public init(
    id: String,
    grant: AccessGrantSummary?,
    token: AccessTokenSummary? = nil,
    closedConnections: Int
  ) {
    self.id = id
    self.grant = grant
    self.token = token
    self.closedConnections = closedConnections
  }
}
