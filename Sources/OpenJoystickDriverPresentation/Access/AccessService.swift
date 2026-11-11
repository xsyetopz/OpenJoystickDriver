import Foundation
import OpenJoystickDriverKit

/// A failure of an access operation: the message to show and the error code `ojd explain` knows.
struct AccessFailure: Error, Equatable {
  /// The message to show.
  let message: String
  /// The error code that `ojd explain` knows, or nil when there is none.
  let code: ErrorCode?

  /// Creates a failure from a message and an optional error code.
  init(message: String, code: ErrorCode?) {
    self.message = message
    self.code = code
  }

  /// The failure that reports `error` from a service request.
  init(_ error: any Error) {
    switch error {
    case let failure as Self: self = failure
    case ApplicationServiceClientError.notConnected:
      self.init(
        message: OJDLocalized.string("ui.access.error.serviceUnavailable"),
        code: .serviceUnavailable
      )
    case ApplicationServiceClientError.timeout:
      self.init(
        message: OJDLocalized.string("ui.access.error.serviceTimeout"),
        code: .serviceTimeout
      )
    case LocalServiceRPCError.peerRejected:
      self.init(
        message: OJDLocalized.string("ui.access.error.peerRejected"),
        code: .peerRejected
      )
    case let rejection as ApplicationServiceRemappingRPCError:
      self.init(message: rejection.localizedDescription, code: rejection.code.errorCode)
    case LocalServiceRPCError.remote(let message)
    where ErrorCode(rawValue: String(message.prefix(5))) == .unsupportedAPIVersion:
      self.init(message: message, code: .unsupportedAPIVersion)
    default:
      self.init(
        message: OJDLocalized.formatted(
          "ui.access.error.requestFailed",
          error.localizedDescription
        ),
        code: .serviceRequestFailed
      )
    }
  }
}

/// The endpoint requests of `ojd access`.
protocol AccessService: Sendable {
  /// Returns the access status.
  func status() async throws -> AccessStatusPayload
  /// Turns the local endpoint on or off and returns the access status.
  func setEnabled(_ enabled: Bool) async throws -> AccessStatusPayload
  /// Turns the WebSocket on or off, on `port` when given, and returns the access status.
  func setWeb(enabled: Bool, port: Int?) async throws -> AccessStatusPayload
  /// Grants the program with the signature access with the scopes and returns the grant.
  func grant(
    _ identity: CodeSigningIdentity,
    path: String,
    scopes: [EndpointScope]
  ) async throws -> AccessGrantSummary
  /// Creates a token for the web origins with the scopes and returns it.
  func grantToken(
    name: String,
    origins: [String],
    scopes: [EndpointScope]
  ) async throws -> AccessTokenGrantResult
  /// Removes `scopes` of the grant, or the whole grant when `scopes` is nil.
  func revoke(id: String, scopes: [EndpointScope]?) async throws -> AccessRevokeResult
}

/// The service over its local socket; each request opens a connection and closes it.
struct ApplicationServiceAccessService: AccessService {
  /// Opens a connection to the service, runs `body` on it and closes the connection.
  /// - Throws: ``ApplicationServiceClientError/notConnected`` when the service does not answer.
  private func request<T: Sendable>(
    _ body: @Sendable (ApplicationServiceClient) async throws -> T
  ) async throws -> T {
    let client = ApplicationServiceClient()
    await client.connect(timeoutSeconds: 0)
    defer { client.disconnect() }
    guard client.isConnected else { throw ApplicationServiceClientError.notConnected }
    return try await body(client)
  }

  /// Returns the access status.
  func status() async throws -> AccessStatusPayload {
    try await request { try await $0.accessStatus() }
  }

  /// Turns the local endpoint on or off and returns the access status.
  func setEnabled(_ enabled: Bool) async throws -> AccessStatusPayload {
    try await request { try await $0.setAccessEnabled(enabled) }
  }

  /// Turns the WebSocket on or off, on `port` when given, and returns the access status.
  func setWeb(enabled: Bool, port: Int?) async throws -> AccessStatusPayload {
    try await request { try await $0.setWebAccess(enabled: enabled, port: port) }
  }

  /// Grants the program with the signature access with the scopes and returns the grant.
  func grant(
    _ identity: CodeSigningIdentity,
    path: String,
    scopes: [EndpointScope]
  ) async throws -> AccessGrantSummary {
    try await request { try await $0.grantAccess(identity, path: path, scopes: scopes) }
  }

  /// Creates a token for the web origins with the scopes and returns it.
  func grantToken(
    name: String,
    origins: [String],
    scopes: [EndpointScope]
  ) async throws -> AccessTokenGrantResult {
    try await request {
      try await $0.grantTokenAccess(name: name, origins: origins, scopes: scopes)
    }
  }

  /// Removes `scopes` of the grant, or the whole grant when `scopes` is nil.
  func revoke(id: String, scopes: [EndpointScope]?) async throws -> AccessRevokeResult {
    try await request { try await $0.revokeAccess(id: id, scopes: scopes) }
  }
}
