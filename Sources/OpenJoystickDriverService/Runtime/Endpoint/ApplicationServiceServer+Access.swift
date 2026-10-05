import Foundation
import OpenJoystickDriverKit

extension ApplicationServiceServer {
  /// The endpoint, its grants, and the clients it refused recently.
  func getAccessStatus() throws -> AccessStatusPayload { try runningEndpoint().status() }

  /// Turns the endpoint on or off and returns its state afterward.
  func setAccessEnabled(_ enabled: Bool) throws -> AccessStatusPayload {
    let endpoint = try runningEndpoint()
    try endpoint.setEnabled(enabled)
    return try endpoint.status()
  }

  func grantAccess(_ arguments: AccessGrantArguments) throws -> AccessGrantSummary {
    try runningEndpoint().grant(arguments.identity, path: arguments.path, scopes: arguments.scopes)
  }

  func revokeAccess(_ arguments: AccessRevokeArguments) throws -> AccessRevokeResult {
    try runningEndpoint().revoke(id: arguments.id, scopes: arguments.scopes)
  }

  func grantTokenAccess(_ arguments: AccessTokenGrantArguments) throws -> AccessTokenGrantResult {
    try runningEndpoint().grantToken(
      name: arguments.name,
      origins: arguments.origins,
      scopes: arguments.scopes
    )
  }

  /// Turns the WebSocket on or off and returns the endpoint's state afterward.
  func setWebAccess(_ arguments: AccessWebArguments) throws -> AccessStatusPayload {
    if let port = arguments.port, !AccessWebSettings.ports.contains(port) {
      throw AccessGrantStoreError.portUnavailable(port)
    }
    let endpoint = try runningEndpoint()
    try endpoint.setWebEnabled(arguments.enabled, port: arguments.port)
    return try endpoint.status()
  }

  private func runningEndpoint() throws -> EndpointServer {
    guard let endpoint = rpcServerLock.withLock({ endpointServer }) else {
      throw AccessGrantStoreError.serviceStopped
    }
    return endpoint
  }
}
