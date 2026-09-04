import Foundation
import IOKit
import IOKit.hid
import OpenJoystickDriverKit
import Security

/// Wraps a non-Sendable asynchronous reply closure so it can cross Task boundary.
///
/// Safe because each local RPC request completes its reply exactly once.
struct SendableReply<T>: @unchecked Sendable { let call: (T) -> Void }

/// Owns runtime state and serves authenticated local RPC requests.
///
/// Call start() once; listener lives for process lifetime.
/// - Note: @unchecked Sendable: ApplicationServiceServer is thread-safe -
///   actor-isolated DeviceManager/PermissionManager handle
///   their own synchronization; reply blocks are dispatched
///   by the local RPC bridge.
@objc public final class ApplicationServiceServer: NSObject, @unchecked Sendable {
  let deviceManager: DeviceManager
  let permissionManager: PermissionManager
  let dispatcher: CompatibilityOutputDispatcher
  let remappingProfileLibrary: RemappingProfileLibrary
  let remappingRouter: RemappingOutputRouter
  let postEventAccess: CoreGraphicsPostEventAccess
  let remappingRequests: RemappingRequestCoordinator
  let compatibilityTransitionCoordinator = CompatibilityTransitionCoordinator()
  let compatibilityTransitionTimeouts: CompatibilityTransitionTimeouts
  let compatibilityTransitionClock: CompatibilityTransitionClock
  let connectedIdentifierProvider: @Sendable () async -> [DeviceIdentifier]
  let feedbackGate: CompatibilityFeedbackGate
  let userSpaceDispatcherBuilder:
    (@Sendable (CompatibilityIdentity) throws -> any CompatibilityUserSpaceOutputDispatching)?
  let userSpaceLock = NSLock()
  var userSpaceDispatcher: (any CompatibilityUserSpaceOutputDispatching)?
  var userSpaceEnabled: Bool
  var userSpaceStatus: String = "off"
  var compatibilityIdentity: CompatibilityIdentity
  var persistedCompatibilityIdentity: CompatibilityIdentity
  var compatibilityLiveIdentity: CompatibilityIdentity?
  var compatibilityRetrySnapshot: CompatibilityRetrySnapshot?
  var userSpaceCloseSlot: CompatibilityBackendCloseSlot?
  var userSpaceAutomaticGeneration: UUID?
  var pendingAutomaticTransitionGeneration: UUID?
  var rpcServer: LocalServiceRPCServer?
  var compatibilityServerStopped = false
  static let compatibilityIdentityDefaultsKey = "CompatibilityIdentity"
  static let compatibilityRetrySnapshotDefaultsKey = "CompatibilityRetrySnapshot"

  struct UserSpaceDispatcherBuild: Sendable {
    let dispatcher: any CompatibilityUserSpaceOutputDispatching
    let status: String
    let closeSlot: CompatibilityBackendCloseSlot
    let automaticGeneration: UUID?

    init(
      dispatcher: any CompatibilityUserSpaceOutputDispatching,
      status: String,
      closeSlot: CompatibilityBackendCloseSlot? = nil,
      automaticGeneration: UUID? = nil
    ) {
      self.dispatcher = dispatcher
      self.status = status
      self.closeSlot = closeSlot ?? CompatibilityBackendCloseSlot(dispatcher)
      self.automaticGeneration = automaticGeneration
    }
  }

  /// Creates a server backed by the device manager, permissions, and output dispatchers.
  init(
    deviceManager: DeviceManager,
    permissionManager: PermissionManager,
    dispatcher: CompatibilityOutputDispatcher,
    remappingProfileLibrary: RemappingProfileLibrary,
    remappingRouter: RemappingOutputRouter,
    postEventAccess: CoreGraphicsPostEventAccess,
    userSpaceDispatcherBuilder: (
      @Sendable (CompatibilityIdentity) throws -> any CompatibilityUserSpaceOutputDispatching
    )? = nil,
    connectedIdentifierProvider: (@Sendable () async -> [DeviceIdentifier])? = nil,
    compatibilityTransitionTimeouts: CompatibilityTransitionTimeouts = .standard,
    compatibilityTransitionClock: CompatibilityTransitionClock = .system,
    initializeCompatibilityBackend: Bool = true
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
    self.userSpaceDispatcherBuilder = userSpaceDispatcherBuilder
    self.connectedIdentifierProvider =
      connectedIdentifierProvider ?? { await deviceManager.connectedDeviceIdentifiers() }
    self.compatibilityTransitionTimeouts = compatibilityTransitionTimeouts
    self.compatibilityTransitionClock = compatibilityTransitionClock
    self.feedbackGate = CompatibilityFeedbackGate(deviceManager: deviceManager)
    self.userSpaceEnabled = false
    let savedCompat = UserDefaults.standard.string(forKey: Self.compatibilityIdentityDefaultsKey)
    let persistence = CompatibilityIdentity.persisted(from: savedCompat)
    if persistence.didRewrite {
      UserDefaults.standard.set(
        persistence.identity.rawValue,
        forKey: Self.compatibilityIdentityDefaultsKey
      )
    }
    self.compatibilityIdentity = persistence.identity
    self.persistedCompatibilityIdentity = persistence.identity
    self.compatibilityLiveIdentity = nil
    self.compatibilityRetrySnapshot = Self.loadCompatibilityRetrySnapshot()
    self.userSpaceCloseSlot = nil
    self.userSpaceAutomaticGeneration = nil
    self.pendingAutomaticTransitionGeneration = nil
    super.init()

    if initializeCompatibilityBackend { _ = self.initializeCompatibilityBackend() }
  }

  /// Starts the authenticated local RPC server used by the headless host and CLI.
  public func start() throws {
    let server = LocalServiceRPCServer(authentication: Self.isTrustedClient(processIdentifier:)) {
      [weak self] request, completion in
      guard let self else {
        completion(LocalServiceRPCResponse(result: nil, error: "Service stopped."))
        return
      }
      self.handleLocalRPC(request, completion: completion)
    }
    try server.start()
    rpcServer = server
    print("[ApplicationServiceServer] Listening on authenticated local RPC socket")
  }

  public func stop() async {
    rpcServer?.stop()
    rpcServer = nil
    userSpaceLock.withLock { compatibilityServerStopped = true }
    await compatibilityTransitionCoordinator.stop()
    let identifiers = await connectedIdentifierProvider()
    _ = await feedbackGate.quiesceAndNeutralize(
      identifiers,
      timeout: compatibilityTransitionTimeouts.feedbackNanoseconds,
      clock: compatibilityTransitionClock
    )
    let detached = userSpaceLock.withLock {
      () -> (
        backend: (any CompatibilityUserSpaceOutputDispatching)?,
        slot: CompatibilityBackendCloseSlot?
      ) in
      dispatcher.setBackend(nil)
      let old = userSpaceDispatcher
      let slot = userSpaceCloseSlot
      userSpaceDispatcher = nil
      userSpaceCloseSlot = nil
      userSpaceAutomaticGeneration = nil
      pendingAutomaticTransitionGeneration = nil
      userSpaceEnabled = false
      compatibilityLiveIdentity = nil
      userSpaceStatus = "off"
      return (old, slot)
    }
    _ = await closeCompatibilityBackend(detached.backend, slot: detached.slot)
  }

  private static func isTrustedClient(processIdentifier: Int32) -> Bool {
    guard let expected = signingIdentityForCurrentProcess() else { return false }
    let attributes = [kSecGuestAttributePid as String: processIdentifier] as CFDictionary
    var guestCode: SecCode?
    guard
      SecCodeCopyGuestWithAttributes(nil, attributes, SecCSFlags(), &guestCode) == errSecSuccess,
      let guestCode, let actual = signingIdentity(for: guestCode)
    else { return false }
    return actual == expected
  }

  private static func signingIdentityForCurrentProcess() -> SigningIdentity? {
    var currentCode: SecCode?
    guard SecCodeCopySelf(SecCSFlags(), &currentCode) == errSecSuccess, let currentCode else {
      return nil
    }
    return signingIdentity(for: currentCode)
  }

  private static func signingIdentity(for code: SecCode) -> SigningIdentity? {
    var staticCode: SecStaticCode?
    var information: CFDictionary?
    let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
    guard SecCodeCopyStaticCode(code, SecCSFlags(), &staticCode) == errSecSuccess, let staticCode,
      SecCodeCopySigningInformation(staticCode, flags, &information) == errSecSuccess,
      let values = information as? [String: Any],
      let identifier = values[kSecCodeInfoIdentifier as String] as? String
    else { return nil }
    return SigningIdentity(
      identifier: identifier,
      teamIdentifier: values[kSecCodeInfoTeamIdentifier as String] as? String
    )
  }

  private struct SigningIdentity: Equatable {
    let identifier: String
    let teamIdentifier: String?
  }

  // MARK: - Private

  func buildUserSpaceDispatcher(identity: CompatibilityIdentity) throws -> UserSpaceDispatcherBuild
  {
    if let userSpaceDispatcherBuilder {
      let dispatcher = try userSpaceDispatcherBuilder(identity)
      return UserSpaceDispatcherBuild(dispatcher: dispatcher, status: dispatcher.status)
    }
    if identity == .automatic {
      let generation = UUID()
      let automatic = AutomaticUserSpaceOutputDispatcher(
        deviceManager: deviceManager,
        consumerProvider: CompatibilityConsumerRouting.current,
        builder: { [weak self] identity in
          guard let self else { throw UserSpaceOutputDispatcher.CreationError.createFailed }
          return try self.buildUserSpaceDispatcher(identity: identity).dispatcher
        },
        transitionRequester: { [weak self] in
          self?.requestAutomaticCompatibilityTransition(generation: generation)
        }
      )
      return UserSpaceDispatcherBuild(
        dispatcher: automatic,
        status: automatic.status,
        automaticGeneration: generation
      )
    }
    let composition = try CompatibilityOutputCompositionFactory.make(identity: identity)
    let compatibilityProfile = composition.profile
    let profile = compatibilityProfile.deviceProfile
    let format = composition.format

    let rumbleHandler: UserSpaceOutputDispatcher.RumbleCommandHandler = {
      [weak self] identifier, command in
      guard let self else { return }
      self.feedbackGate.submit(identifier: identifier, command: command)
    }

    let output = try UserSpaceOutputDispatcher(
      profile: profile,
      format: format,
      emitsXboxGuideReport: compatibilityProfile.emitsXboxGuideReport,
      onRumbleCommand: rumbleHandler
    ) { [weak self] identifier in
      _ = await self?.feedbackGate.quiesceAndNeutralize(
        [identifier],
        timeout: self?.compatibilityTransitionTimeouts.feedbackNanoseconds
          ?? CompatibilityTransitionTimeouts.standard.feedbackNanoseconds,
        clock: self?.compatibilityTransitionClock ?? .system,
        resumeWhenComplete: true
      )
    }
    let gated = CompatibilityUserSpaceOutputDispatchingAdapter(
      backend: output,
      deviceManager: deviceManager,
      identity: identity
    ) { [weak self] in await self?.deviceManager.connectedDeviceDescriptions() ?? [] }
    return UserSpaceDispatcherBuild(dispatcher: gated, status: gated.status)
  }

  func initializeCompatibilityBackend() -> Bool {
    if userSpaceEnabled, userSpaceDispatcher != nil { return true }
    do {
      let build = try buildUserSpaceDispatcher(identity: compatibilityIdentity)
      userSpaceLock.withLock {
        userSpaceDispatcher = build.dispatcher
        userSpaceCloseSlot = build.closeSlot
        userSpaceAutomaticGeneration = build.automaticGeneration
        dispatcher.setBackend(build.dispatcher)
        userSpaceEnabled = true
        userSpaceStatus = build.status
        compatibilityLiveIdentity = compatibilityIdentity
      }
      print("[ApplicationServiceServer] Compatibility virtual gamepad ready")
      return true
    } catch {
      userSpaceLock.withLock {
        dispatcher.setBackend(nil)
        userSpaceDispatcher = nil
        userSpaceEnabled = false
        userSpaceStatus = "error: \(error)"
      }
      print("[ApplicationServiceServer] Compatibility virtual gamepad unavailable: \(error)")
      return false
    }
  }

  func currentUserSpaceStatus() -> String {
    userSpaceLock.withLock {
      guard let dispatcher = userSpaceDispatcher else { return userSpaceStatus }
      let rumble: String
      if dispatcher.lastRumbleStatus == "none" {
        rumble = ""
      } else {
        rumble = ", rumble: \(dispatcher.lastRumbleStatus)"
      }
      return "\(dispatcher.status)\(rumble)"
    }
  }

  struct UserSpaceStatusSnapshot: Sendable {
    let enabled: Bool
    let status: String
    let requestedIdentity: CompatibilityIdentity
    let liveIdentity: CompatibilityIdentity?
    let retrySnapshot: CompatibilityRetrySnapshot?
  }

  func userSpaceStatusSnapshot() -> UserSpaceStatusSnapshot {
    userSpaceLock.withLock {
      let status: String
      if let userSpaceDispatcher, userSpaceDispatcher.lastRumbleStatus != "none" {
        status = "\(userSpaceDispatcher.status), rumble: \(userSpaceDispatcher.lastRumbleStatus)"
      } else if let userSpaceDispatcher {
        status = userSpaceDispatcher.status
      } else {
        status = userSpaceStatus
      }
      return UserSpaceStatusSnapshot(
        enabled: userSpaceEnabled,
        status: status,
        requestedIdentity: compatibilityIdentity,
        liveIdentity: compatibilityLiveIdentity,
        retrySnapshot: compatibilityRetrySnapshot
      )
    }
  }

  func compatibilityTransitionSnapshot() -> CompatibilityTransitionSnapshot {
    userSpaceLock.withLock {
      if userSpaceCloseSlot == nil, let userSpaceDispatcher {
        userSpaceCloseSlot = CompatibilityBackendCloseSlot(userSpaceDispatcher)
      }
      return CompatibilityTransitionSnapshot(
        requestedIdentity: compatibilityIdentity,
        persistedIdentity: persistedCompatibilityIdentity,
        liveIdentity: compatibilityLiveIdentity,
        enabled: userSpaceEnabled,
        dispatcher: userSpaceDispatcher,
        closeSlot: userSpaceCloseSlot
      )
    }
  }

  func isCompatibilityServerStopped() -> Bool {
    userSpaceLock.withLock { compatibilityServerStopped }
  }

  func closeCompatibilityBackend(
    _ backend: (any CompatibilityUserSpaceOutputDispatching)?,
    slot: CompatibilityBackendCloseSlot? = nil,
    timeout: UInt64? = nil,
    error: CompatibilityTransitionError = .candidateCloseTimedOut
  ) async -> Bool {
    guard let backend else { return true }
    let closeSlot = userSpaceLock.withLock { () -> CompatibilityBackendCloseSlot in
      if let slot { return slot }
      if let userSpaceCloseSlot, userSpaceCloseSlot.backend === (backend as AnyObject) {
        return userSpaceCloseSlot
      }
      let slot = CompatibilityBackendCloseSlot(backend)
      if userSpaceDispatcher === backend { userSpaceCloseSlot = slot }
      return slot
    }
    return await closeSlot.close(
      timeout: timeout ?? compatibilityTransitionTimeouts.candidateCloseNanoseconds,
      clock: compatibilityTransitionClock,
      error: error
    )
  }

  func requestAutomaticCompatibilityTransition(generation: UUID) {
    let shouldSchedule = userSpaceLock.withLock { () -> Bool in
      guard compatibilityIdentity == .automatic, userSpaceAutomaticGeneration == generation,
        pendingAutomaticTransitionGeneration != generation
      else { return false }
      pendingAutomaticTransitionGeneration = generation
      return true
    }
    guard shouldSchedule else { return }
    Task { [weak self] in
      guard let self else { return }
      _ = await compatibilityTransitionCoordinator.enqueue { [weak self] in
        guard let self else { return false }
        defer {
          self.userSpaceLock.withLock {
            if self.pendingAutomaticTransitionGeneration == generation {
              self.pendingAutomaticTransitionGeneration = nil
            }
          }
        }
        guard
          self.userSpaceLock.withLock({
            self.compatibilityIdentity == .automatic
              && self.userSpaceAutomaticGeneration == generation
          })
        else { return false }
        return await self.performCompatibilityIdentityTransition(to: .automatic, force: true)
      }
    }
  }

  static func loadCompatibilityRetrySnapshot(defaults: UserDefaults = .standard)
    -> CompatibilityRetrySnapshot?
  {
    guard let data = defaults.data(forKey: compatibilityRetrySnapshotDefaultsKey) else {
      return nil
    }
    return try? JSONDecoder().decode(CompatibilityRetrySnapshot.self, from: data)
  }

  static func persistCompatibilityRetrySnapshot(
    _ snapshot: CompatibilityRetrySnapshot?,
    defaults: UserDefaults = .standard
  ) {
    guard let snapshot, let data = try? JSONEncoder().encode(snapshot) else {
      defaults.removeObject(forKey: compatibilityRetrySnapshotDefaultsKey)
      return
    }
    defaults.set(data, forKey: compatibilityRetrySnapshotDefaultsKey)
  }

}
