import Foundation
import IOKit
import IOKit.hid
import OpenJoystickDriverKit
import OpenJoystickDriverRelay
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
  let driverKitDispatcher: DriverKitOutputDispatcher
  let userSpaceLock = NSLock()
  var userSpaceDispatcher: (any CompatibilityUserSpaceOutputDispatching)?
  var foregroundConsumerDispatcherPool: ForegroundConsumerCompatibilityDispatcherPool?
  var userSpaceEnabled: Bool
  var userSpaceStatus: String = "off"
  var compatibilityIdentity: CompatibilityIdentity
  var rpcServer: LocalServiceRPCServer?
  static let compatibilityIdentityDefaultsKey = "CompatibilityIdentity"

  struct UserSpaceDispatcherBuild {
    let dispatcher: any CompatibilityUserSpaceOutputDispatching
    let foregroundConsumerPool: ForegroundConsumerCompatibilityDispatcherPool?
    let status: String
  }

  /// Creates a server backed by the device manager, permissions, and output dispatchers.
  public init(
    deviceManager: DeviceManager,
    permissionManager: PermissionManager,
    dispatcher: CompatibilityOutputDispatcher,
    driverKitDispatcher: DriverKitOutputDispatcher
  ) {
    self.deviceManager = deviceManager
    self.permissionManager = permissionManager
    self.dispatcher = dispatcher
    self.driverKitDispatcher = driverKitDispatcher
    self.userSpaceEnabled = false
    let savedCompat = UserDefaults.standard.string(forKey: Self.compatibilityIdentityDefaultsKey)
    self.compatibilityIdentity = CompatibilityIdentity(rawValue: savedCompat ?? "") ?? .sdl2_3
    super.init()

    // Consumer routing used to be selectable. Discard every stale selection and always
    // initialize the sole supported consumer backend.
    UserDefaults.standard.removeObject(forKey: "UserSpaceVirtualDeviceEnabled")
    UserDefaults.standard.removeObject(forKey: "OutputMode")
    UserDefaults.standard.removeObject(forKey: "VirtualDeviceMode")
    _ = initializeCompatibilityBackend()
  }

  /// Starts the authenticated local RPC server used by GUI and headless clients.
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

  public func stop() {
    rpcServer?.stop()
    rpcServer = nil
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
    enum CompatError: Swift.Error, CustomStringConvertible, Sendable {
      case unsupported(String)
      var description: String {
        switch self {
        case .unsupported(let msg): return msg
        }
      }
    }

    let compatibilityProfile = CompatibilityOutputProfileCatalog.profile(for: identity)
    let profile = compatibilityProfile.deviceProfile
    let format: any VirtualGamepadReportFormat
    let primaryUsage: Int?
    switch identity {
    case .genericHID:
      format = OJDSDLGamepadFormat()
      primaryUsage = nil
    case .sdl2_3:
      format = OJDSDLGamepadFormat()
      primaryUsage = nil
    case .appleGameController:
      format = Xbox360MacHIDReportFormat(topLevelUsage: UInt8(kHIDUsage_GD_GamePad))
      primaryUsage = Int(kHIDUsage_GD_GamePad)
    case .xoneHID:
      primaryUsage = nil
      // Xbox One identity for SDL consumers:
      // - Prefer the physical HID report descriptor exposed by macOS for 045E:02EA (USB).
      //   This makes SDL treat the virtual device as a real Xbox controller.
      // - Fall back to a built-in descriptor if the physical device is not present.
      if let physical = HIDDescriptorReportFormat.copyPhysicalReportDescriptor(
        vendorID: profile.vendorID,
        productID: profile.productID,
        preferredTransport: "USB"
      ) {
        do {
          format = try HIDDescriptorReportFormat(
            descriptor: physical,
            outputReportID: VirtualRumbleOutputReportParser.xboxGIPReportID,
            outputReportPayloadSize: VirtualRumbleOutputReportParser
              .xboxGIPReportPayloadSizeWithoutReportID
          )
        } catch {
          // If parsing fails on this OS build, fall back to the built-in descriptor.
          format = try HIDDescriptorReportFormat(
            descriptor: XboxOneBluetoothHIDDescriptor.descriptor,
            outputReportID: VirtualRumbleOutputReportParser.xboxOneReportID,
            outputReportPayloadSize: VirtualRumbleOutputReportParser.xboxOneReportPayloadSize
          )
        }
      } else {
        format = try HIDDescriptorReportFormat(
          descriptor: XboxOneBluetoothHIDDescriptor.descriptor,
          outputReportID: VirtualRumbleOutputReportParser.xboxOneReportID,
          outputReportPayloadSize: VirtualRumbleOutputReportParser.xboxOneReportPayloadSize
        )
      }
    case .x360HID:
      format = Xbox360MacHIDReportFormat()
      primaryUsage = nil
    }

    let rumbleHandler: UserSpaceOutputDispatcher.RumbleCommandHandler = {
      [weak self] identifier, command in
      guard let self else { return }
      Task {
        _ = await self.deviceManager.sendRumble(
          for: identifier,
          left: command.left,
          right: command.right,
          lt: command.leftTrigger,
          rt: command.rightTrigger,
          durationMs: command.durationMs
        )
      }
    }

    let pool = try ForegroundConsumerCompatibilityDispatcherPool { routeToken in
      try UserSpaceOutputDispatcher(
        profile: profile,
        format: format,
        primaryUsage: primaryUsage,
        emitsXboxGuideReport: compatibilityProfile.emitsXboxGuideReport,
        routeToken: routeToken,
        onRumbleCommand: rumbleHandler
      )
    }
    return UserSpaceDispatcherBuild(
      dispatcher: pool,
      foregroundConsumerPool: pool,
      status: pool.status
    )
  }

  func initializeCompatibilityBackend() -> Bool {
    if userSpaceEnabled, userSpaceDispatcher != nil { return true }
    do {
      let build = try buildUserSpaceDispatcher(identity: compatibilityIdentity)
      userSpaceLock.withLock {
        userSpaceDispatcher = build.dispatcher
        foregroundConsumerDispatcherPool = build.foregroundConsumerPool
        dispatcher.setBackend(build.dispatcher)
        userSpaceEnabled = true
        userSpaceStatus = build.status
      }
      print("[ApplicationServiceServer] Compatibility virtual gamepad ready")
      primeUserSpaceDevices(build.dispatcher)
      return true
    } catch {
      userSpaceLock.withLock {
        dispatcher.setBackend(nil)
        userSpaceDispatcher = nil
        foregroundConsumerDispatcherPool = nil
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

  func primeUserSpaceDevices(_ ud: any CompatibilityUserSpaceOutputDispatching) {
    let dm = deviceManager
    Task {
      let identifiers = await dm.connectedDeviceIdentifiers()
      guard !identifiers.isEmpty else { return }
      for identifier in identifiers { await ud.dispatch(events: [], from: identifier) }
      userSpaceLock.withLock { if userSpaceDispatcher != nil { userSpaceStatus = ud.status } }
    }
  }

  func applyForegroundCompatibilityRoutingUpdate(
    frontmostBundleRootPath: String?,
    effectiveConsumerBundleRoots: Set<String>,
    observedConsumerBundleRoots: Set<String>,
    activeRouteToken: String?
  ) async {
    guard userSpaceEnabled else { return }
    guard let pool = userSpaceLock.withLock({ foregroundConsumerDispatcherPool }) else { return }

    let retainedBundleRoots = ForegroundConsumerRouteSelection.retainedDedicatedBundleRootPaths(
      frontmostBundleRootPath: frontmostBundleRootPath,
      effectiveConsumerBundleRoots: effectiveConsumerBundleRoots,
      observedConsumerBundleRoots: observedConsumerBundleRoots,
      activeRouteToken: activeRouteToken
    )

    if let activeBundleRootPath = retainedBundleRoots.first {
      do { try pool.ensureDedicatedRoute(forConsumerBundleRootPath: activeBundleRootPath) } catch {
        print(
          "[ApplicationServiceServer] Failed to create dedicated Compatibility route for "
            + "\(URL(fileURLWithPath: activeBundleRootPath).lastPathComponent): \(error)"
        )
      }
    }

    await pool.setActiveRouteToken(activeRouteToken)
    pool.retainDedicatedRoutes(forConsumerBundleRootPaths: retainedBundleRoots)
    userSpaceLock.withLock { userSpaceStatus = pool.status }
  }
}
