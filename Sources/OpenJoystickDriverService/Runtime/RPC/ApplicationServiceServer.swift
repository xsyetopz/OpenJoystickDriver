import Foundation
import OpenJoystickDriverKit
import Security

/// Owns runtime state and serves authenticated local RPC requests.
///
/// Call start() once; listener lives for process lifetime.
/// - Note: `@unchecked Sendable` because the mutable fields are guarded by `NSLock`s (named on each
///   field) that the compiler cannot check; every other stored property is an immutable `let` of a
///   `Sendable` type. An actor would force the synchronous output and builder callbacks to hop.
public final class ApplicationServiceServer: @unchecked Sendable {
  let deviceManager: DeviceManager
  let permissionManager: PermissionManager
  let dispatcher: VirtualOutputRouter
  let remappingProfileLibrary: RemappingProfileLibrary
  let remappingRouter: RemappingOutputRouter
  let postEventAccess: CoreGraphicsPostEventAccess
  let remappingRequests: RemappingRequestCoordinator
  let virtualOutputTransitionCoordinator = VirtualOutputTransitionCoordinator()
  let virtualOutputTransitionTimeouts: VirtualOutputTransitionTimeouts
  let virtualOutputTransitionClock: VirtualOutputTransitionClock
  let connectedIdentifierProvider: @Sendable () async -> [DeviceIdentifier]
  let feedbackGate: VirtualOutputFeedbackGate
  /// Service settings storage; also backs `virtualHIDProfileOverrides`.
  let defaults: UserDefaults
  let launchAtLogin: LaunchAtLoginControl
  let virtualHIDProfileOverrides: VirtualHIDProfileOverrideStore
  let userSpaceDispatcherFactory: UserSpaceDispatcherFactory
  let virtualFeeds: VirtualFeedRegistry
  /// Guards `userSpaceDispatcher`, `userSpaceEnabled`, `userSpaceStatus`, `userSpaceCloseSlot`,
  /// and `virtualOutputServerStopped`.
  let userSpaceLock = NSLock()
  var userSpaceDispatcher: (any VirtualOutputDispatching)?
  var userSpaceEnabled: Bool
  var userSpaceStatus: VirtualOutputBackendStatus = .off
  var userSpaceCloseSlot: VirtualOutputBackendCloseSlot?
  /// Guards `rpcServer` and `endpointServer`.
  let rpcServerLock = NSLock()
  var rpcServer: LocalServiceRPCServer?
  var endpointServer: EndpointServer?
  var virtualOutputServerStopped = false

  /// Creates a server backed by the device manager, permissions, and output dispatchers.
  ///
  /// `userSpaceDispatcherFactory` builds each user-space dispatcher candidate; the composition
  /// root supplies the concrete one. `virtualFeeds` defaults to feeds that publish IOHID-backed
  /// devices.
  init(
    deviceManager: DeviceManager,
    permissionManager: PermissionManager,
    dispatcher: VirtualOutputRouter,
    remappingProfileLibrary: RemappingProfileLibrary,
    remappingRouter: RemappingOutputRouter,
    postEventAccess: CoreGraphicsPostEventAccess,
    userSpaceDispatcherFactory: @escaping UserSpaceDispatcherFactory,
    virtualFeeds: VirtualFeedRegistry? = nil,
    connectedIdentifierProvider: (@Sendable () async -> [DeviceIdentifier])? = nil,
    virtualOutputTransitionTimeouts: VirtualOutputTransitionTimeouts = .standard,
    virtualOutputTransitionClock: VirtualOutputTransitionClock = .system,
    defaults: UserDefaults = .standard,
    launchAtLogin: LaunchAtLoginControl = .system
  ) {
    self.deviceManager = deviceManager
    self.permissionManager = permissionManager
    self.dispatcher = dispatcher
    self.remappingProfileLibrary = remappingProfileLibrary
    self.remappingRouter = remappingRouter
    self.postEventAccess = postEventAccess
    self.remappingRequests = RemappingRequestCoordinator(
      library: remappingProfileLibrary,
      router: remappingRouter,
      postEventAccess: postEventAccess
    )
    self.userSpaceDispatcherFactory = userSpaceDispatcherFactory
    self.virtualFeeds =
      virtualFeeds ?? VirtualFeedRegistry(factory: ApplicationServiceRuntime.makeVirtualFeedDevice)
    self.connectedIdentifierProvider =
      connectedIdentifierProvider ?? { await deviceManager.activeDeviceIdentifiers() }
    self.virtualOutputTransitionTimeouts = virtualOutputTransitionTimeouts
    self.virtualOutputTransitionClock = virtualOutputTransitionClock
    self.feedbackGate = VirtualOutputFeedbackGate(deviceManager: deviceManager)
    self.defaults = defaults
    self.launchAtLogin = launchAtLogin
    self.virtualHIDProfileOverrides = VirtualHIDProfileOverrideStore(defaults: defaults)
    self.userSpaceEnabled = false
    self.userSpaceCloseSlot = nil
  }

  /// Starts the authenticated local RPC server used by the headless host and CLI.
  public func start() throws {
    let server = LocalServiceRPCServer(authentication: Self.isTrustedClient(peer:)) {
      [weak self] request, completion in
      guard let self else {
        completion(LocalServiceRPCResponse(result: nil, error: "Service stopped."))
        return
      }
      Task { completion(await self.handleLocalRPC(request)) }
    }
    try server.start()
    let endpoint = EndpointServer(source: ApplicationServiceWatchSource(server: self))
    endpoint.start()
    rpcServerLock.withLock {
      rpcServer = server
      endpointServer = endpoint
    }
    print("[ApplicationServiceServer] Listening on authenticated local RPC socket")
  }
}

extension ApplicationServiceServer {

  struct UserSpaceDispatcherBuild: Sendable {
    let dispatcher: any VirtualOutputDispatching
    let status: VirtualOutputBackendStatus
    let closeSlot: VirtualOutputBackendCloseSlot

    init(
      dispatcher: any VirtualOutputDispatching,
      status: VirtualOutputBackendStatus,
      closeSlot: VirtualOutputBackendCloseSlot? = nil
    ) {
      self.dispatcher = dispatcher
      self.status = status
      self.closeSlot = closeSlot ?? VirtualOutputBackendCloseSlot(dispatcher)
    }
  }

  public func stop() async {
    let (server, endpoint) = rpcServerLock.withLock {
      () -> (LocalServiceRPCServer?, EndpointServer?) in
      defer {
        rpcServer = nil
        endpointServer = nil
      }
      return (rpcServer, endpointServer)
    }
    endpoint?.stop()
    server?.stop()
    userSpaceLock.withLock { virtualOutputServerStopped = true }
    await virtualFeeds.stop()
    await virtualOutputTransitionCoordinator.stop()
    let identifiers = await connectedIdentifierProvider()
    _ = await feedbackGate.quiesceAndNeutralize(
      identifiers,
      timeout: virtualOutputTransitionTimeouts.feedbackNanoseconds,
      clock: virtualOutputTransitionClock
    )
    let slot = userSpaceLock.withLock { () -> VirtualOutputBackendCloseSlot? in
      dispatcher.setBackend(nil)
      let slot = userSpaceCloseSlot
      userSpaceDispatcher = nil
      userSpaceCloseSlot = nil
      userSpaceEnabled = false
      userSpaceStatus = .off
      return slot
    }
    _ = await closeVirtualOutputBackend(slot)
  }

  static func isTrustedClient(peer: LocalSocketPeer) -> Bool {
    // The app's own UI calls this service over the socket. Security cannot resolve a running
    // process's code once its bundle is replaced on disk (a rebuild or an update before relaunch),
    // which would reject the app's own calls and freeze its controller list.
    if peer.processIdentifier == getpid() { return true }
    guard let expected = CodeSigningIdentity.current else { return false }
    if let requirement = expected.requirement { return peer.satisfies(requirement) }
    // An ad-hoc development build has no signer to require; compare its signing details.
    guard peer.satisfies(nil), let code = peer.code() else { return false }
    return CodeSigningIdentity.of(code) == expected
  }

  // MARK: - Private

  func buildUserSpaceDispatcher() throws -> UserSpaceDispatcherBuild {
    let dispatcher = try userSpaceDispatcherFactory(
      UserSpaceDispatcherFactoryContext(
        deviceManager: deviceManager,
        feedbackGate: feedbackGate,
        profileOverrides: virtualHIDProfileOverrides,
        timeouts: virtualOutputTransitionTimeouts,
        clock: virtualOutputTransitionClock
      )
    )
    return UserSpaceDispatcherBuild(dispatcher: dispatcher, status: dispatcher.status)
  }

  func currentUserSpaceStatus() -> VirtualOutputBackendStatus { userSpaceStatusSnapshot().status }

  struct UserSpaceStatusSnapshot: Sendable {
    let enabled: Bool
    let status: VirtualOutputBackendStatus
  }

  /// A recorded activation error stays the status and carries the live backend status as
  /// context; otherwise the live backend status is reported, with the last rumble summary.
  func userSpaceStatusSnapshot() -> UserSpaceStatusSnapshot {
    userSpaceLock.withLock {
      guard let dispatcher = userSpaceDispatcher else {
        return UserSpaceStatusSnapshot(enabled: userSpaceEnabled, status: userSpaceStatus)
      }
      var live = dispatcher.status
      if let rumble = dispatcher.lastRumbleStatus {
        switch live {
        case .error(let message): live = .error("\(message), rumble: \(rumble)")
        case .off, .backend: live = .backend("\(live.wireValue), rumble: \(rumble)")
        }
      }
      let status: VirtualOutputBackendStatus
      if case .error(let message) = userSpaceStatus {
        status = .error("\(message); live: \(live.wireValue)")
      } else {
        status = live
      }
      return UserSpaceStatusSnapshot(enabled: userSpaceEnabled, status: status)
    }
  }

  func isVirtualOutputServerStopped() -> Bool {
    userSpaceLock.withLock { virtualOutputServerStopped }
  }

  /// Closes the backend that `slot` owns within the candidate-close timeout; true when it closed.
  func closeVirtualOutputBackend(_ slot: VirtualOutputBackendCloseSlot?) async -> Bool {
    guard let slot else { return true }
    return await slot.close(
      timeout: virtualOutputTransitionTimeouts.candidateCloseNanoseconds,
      clock: virtualOutputTransitionClock
    )
  }
}
