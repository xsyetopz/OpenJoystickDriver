import Foundation
import OpenJoystickDriverKit

/// The outcome of a remapping request: the value or the RPC error.
typealias RemappingRequestResult<Value: Sendable> = Result<
  Value, ApplicationServiceRemappingRPCError
>

/// Serializes profile mutations, route refreshes, and the snapshot returned to RPC clients.
actor RemappingRequestCoordinator {
  /// Runs before a mutation response is accepted, so tests can observe the point.
  typealias MutationResponseAcceptanceHook =
    @Sendable (ApplicationServiceRemappingSnapshotPayload) async throws -> Void

  /// The remapping profiles on disk.
  let library: RemappingProfileLibrary
  /// The router that applies the active profiles to the controllers.
  let router: RemappingOutputRouter
  /// The connected controllers that controller references resolve against.
  let connectedControllers: @Sendable () async -> [ConnectedController]
  /// The access to posting system input events.
  let postEventAccess: CoreGraphicsPostEventAccess
  /// The largest response payload, in bytes.
  let maximumResponseBytes: Int
  /// The largest transport frame of a response, in bytes.
  let maximumTransportFrameBytes: Int
  /// Runs before a mutation response is accepted.
  let beforeMutationResponseAcceptance: MutationResponseAcceptanceHook
  /// The last queued operation, which the next one waits for.
  var operationTail: (id: UUID, task: Task<Void, Never>)?

  /// Creates a coordinator over `library` and `router`.
  init(
    library: RemappingProfileLibrary,
    router: RemappingOutputRouter,
    connectedControllers: @escaping @Sendable () async -> [ConnectedController],
    postEventAccess: CoreGraphicsPostEventAccess,
    maximumResponseBytes: Int = ApplicationServiceRemappingRPC.maximumPayloadBytes,
    maximumTransportFrameBytes: Int = ApplicationServiceRemappingRPC.maximumTransportFrameBytes,
    beforeMutationResponseAcceptance: @escaping MutationResponseAcceptanceHook = { _ in }
  ) {
    self.library = library
    self.router = router
    self.connectedControllers = connectedControllers
    self.postEventAccess = postEventAccess
    self.maximumResponseBytes = maximumResponseBytes
    self.maximumTransportFrameBytes = maximumTransportFrameBytes
    self.beforeMutationResponseAcceptance = beforeMutationResponseAcceptance
  }
}
