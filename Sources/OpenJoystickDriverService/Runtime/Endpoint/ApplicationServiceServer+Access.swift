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

  private func runningEndpoint() throws -> EndpointServer {
    guard let endpoint = rpcServerLock.withLock({ endpointServer }) else {
      throw AccessGrantStoreError.serviceStopped
    }
    return endpoint
  }
}
