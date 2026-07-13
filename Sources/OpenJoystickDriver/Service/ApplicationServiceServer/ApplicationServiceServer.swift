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
@objc
public final class ApplicationServiceServer: NSObject, @unchecked Sendable
{
  let deviceManager: DeviceManager
  let permissionManager: PermissionManager
  let dispatcher: CompositeOutputDispatcher
  let dextDispatcher: DextOutputDispatcher
  let userSpaceLock = NSLock()
  var userSpaceDispatcher: (any CompatibilityUserSpaceOutputDispatching)?
  var foregroundConsumerDispatcherPool: ForegroundConsumerCompatibilityDispatcherPool?
  var userSpaceEnabled: Bool
  var userSpaceStatus: String = "off"
  var compatibilityIdentity: CompatibilityIdentity
  var virtualDeviceMode: VirtualDeviceMode
  /// Actual routing mode currently applied.
  var effectiveOutputMode: CompositeOutputDispatcher.Mode
  var rpcServer: LocalServiceRPCServer?
  static let userSpaceEnabledDefaultsKey = "UserSpaceVirtualDeviceEnabled"
  static let compatibilityIdentityDefaultsKey = "CompatibilityIdentity"
  static let outputModeDefaultsKey = "OutputMode"
  static let virtualDeviceModeDefaultsKey = "VirtualDeviceMode"

  struct UserSpaceDispatcherBuild {
    let dispatcher: any CompatibilityUserSpaceOutputDispatching
    let foregroundConsumerPool: ForegroundConsumerCompatibilityDispatcherPool?
    let status: String
  }

  /// Creates a server backed by the device manager, permissions, and output dispatchers.
  public init(
    deviceManager: DeviceManager,
    permissionManager: PermissionManager,
    dispatcher: CompositeOutputDispatcher,
    dextDispatcher: DextOutputDispatcher
  ) {
    self.deviceManager = deviceManager
    self.permissionManager = permissionManager
    self.dispatcher = dispatcher
    self.dextDispatcher = dextDispatcher
    self.userSpaceEnabled = UserDefaults.standard.bool(forKey: Self.userSpaceEnabledDefaultsKey)
    let savedCompat = UserDefaults.standard.string(forKey: Self.compatibilityIdentityDefaultsKey)
    self.compatibilityIdentity = CompatibilityIdentity(rawValue: savedCompat ?? "") ?? .sdl2_3
    let savedVirtual = UserDefaults.standard.string(forKey: Self.virtualDeviceModeDefaultsKey)
    if let raw = savedVirtual, let mode = VirtualDeviceMode(rawValue: raw) {
      self.virtualDeviceMode = mode
    } else {
      // Migration from previous routing keys (OutputMode + userSpaceEnabled).
      let savedMode = UserDefaults.standard.string(forKey: Self.outputModeDefaultsKey)
      let parsed = CompositeOutputDispatcher.Mode(rawValue: savedMode ?? "")
      if parsed == .both {
        self.virtualDeviceMode = .both
      } else if userSpaceEnabled {
        self.virtualDeviceMode = .compatUserSpace
      } else {
        // Default to Compatibility-first so SDL/IOKit apps work without requiring a reboot.
        self.virtualDeviceMode = .compatUserSpace
      }
    }
    self.effectiveOutputMode = .primaryOnly

    super.init()

    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleDextUnstable(_:)),
      name: DextOutputDispatcher.dextUnstableNotification,
      object: nil
    )

    applyMode(virtualDeviceMode)
  }

  func applyMode(_ mode: VirtualDeviceMode) {
    virtualDeviceMode = mode
    UserDefaults.standard.set(mode.rawValue, forKey: Self.virtualDeviceModeDefaultsKey)

    switch mode {
    case .auto:
      // Prefer DriverKit, but allow an automatic one-way fall back to user-space if DriverKit
      // output becomes unstable (during sysext replacement/upgrade, or if the dext isn't ready).
      dextDispatcher.setCompatibilitySeizeEnabled(false)
      dextDispatcher.setEnabled(true)
      _ = setUserSpaceVirtualDeviceEnabledInternal(false)
      effectiveOutputMode = .primaryOnly
      dispatcher.setMode(.primaryOnly)
      UserDefaults.standard.set(
        CompositeOutputDispatcher.Mode.primaryOnly.rawValue,
        forKey: Self.outputModeDefaultsKey
      )
    case .driverKit:
      dextDispatcher.setCompatibilitySeizeEnabled(false)
      dextDispatcher.setEnabled(true)
      _ = setUserSpaceVirtualDeviceEnabledInternal(false)
      effectiveOutputMode = .primaryOnly
      dispatcher.setMode(.primaryOnly)
      UserDefaults.standard.set(
        CompositeOutputDispatcher.Mode.primaryOnly.rawValue,
        forKey: Self.outputModeDefaultsKey
      )
    case .compatUserSpace:
      // Compatibility is user-requested. Do not rewrite the requested mode on failures.
      //
      // If user-space creation fails, keep DriverKit enabled as a fallback but keep the
      // requested mode as Compatibility and show an explicit error string.
      if setUserSpaceVirtualDeviceEnabledInternal(true) {
        dextDispatcher.setCompatibilitySeizeEnabled(
          compatibilityIdentity.seizesDriverKitInCompatibilityMode
        )
        dextDispatcher.setEnabled(false)
        effectiveOutputMode = .secondaryOnly
        dispatcher.setMode(.secondaryOnly)
        UserDefaults.standard.set(
          CompositeOutputDispatcher.Mode.secondaryOnly.rawValue,
          forKey: Self.outputModeDefaultsKey
        )
      } else {
        dextDispatcher.setCompatibilitySeizeEnabled(false)
        dextDispatcher.setEnabled(true)
        effectiveOutputMode = .primaryOnly
        dispatcher.setMode(.primaryOnly)
        UserDefaults.standard.set(
          CompositeOutputDispatcher.Mode.primaryOnly.rawValue,
          forKey: Self.outputModeDefaultsKey
        )
        if !userSpaceStatus.hasPrefix("error:") {
          userSpaceStatus =
            "error: Compatibility backend failed to start. Still using DriverKit output."
        } else {
          userSpaceStatus += " (still using DriverKit output)"
        }
      }
    case .both:
      dextDispatcher.setCompatibilitySeizeEnabled(false)
      dextDispatcher.setEnabled(true)
      if compatibilityIdentity.disablesDriverKitMirror {
        _ = setUserSpaceVirtualDeviceEnabledInternal(false)
        effectiveOutputMode = .primaryOnly
        dispatcher.setMode(.primaryOnly)
        userSpaceStatus =
          "off (\(compatibilityIdentity.rawValue) Compatibility disabled while DriverKit " +
          "output is active)"
        return
      }
      if setUserSpaceVirtualDeviceEnabledInternal(true) {
        effectiveOutputMode = .both
        dispatcher.setMode(.both)
        UserDefaults.standard.set(
          CompositeOutputDispatcher.Mode.both.rawValue,
          forKey: Self.outputModeDefaultsKey
        )
      } else {
        dextDispatcher.setEnabled(true)
        effectiveOutputMode = .primaryOnly
        dispatcher.setMode(.primaryOnly)
        UserDefaults.standard.set(
          CompositeOutputDispatcher.Mode.primaryOnly.rawValue,
          forKey: Self.outputModeDefaultsKey
        )
        if !userSpaceStatus.hasPrefix("error:") {
          userSpaceStatus =
            "error: Compatibility backend failed to start. Still using DriverKit output."
        } else {
          userSpaceStatus += " (still using DriverKit output)"
        }
      }
    }
  }

  /// Starts the authenticated local RPC server used by GUI and headless clients.
  public func start() throws {
    let server = LocalServiceRPCServer(
      authentication: Self.isTrustedClient(processIdentifier:)
    ) { [weak self] request, completion in
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
    let attributes = [
      kSecGuestAttributePid as String: processIdentifier,
    ] as CFDictionary
    var guestCode: SecCode?
    guard
      SecCodeCopyGuestWithAttributes(nil, attributes, SecCSFlags(), &guestCode) == errSecSuccess,
      let guestCode,
      let actual = signingIdentity(for: guestCode)
    else {
      return false
    }
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
    guard
      SecCodeCopyStaticCode(code, SecCSFlags(), &staticCode) == errSecSuccess,
      let staticCode,
      SecCodeCopySigningInformation(staticCode, flags, &information) == errSecSuccess,
      let values = information as? [String: Any],
      let identifier = values[kSecCodeInfoIdentifier as String] as? String
    else {
      return nil
    }
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

  func buildUserSpaceDispatcher(
    identity: CompatibilityIdentity
  ) throws -> UserSpaceDispatcherBuild {
    enum CompatError: Swift.Error, CustomStringConvertible, Sendable {
      case unsupported(String)
      var description: String {
        switch self {
        case .unsupported(let msg):
          return msg
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
            outputReportPayloadSize:
              VirtualRumbleOutputReportParser.xboxGIPReportPayloadSizeWithoutReportID
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

  func setUserSpaceVirtualDeviceEnabledInternal(_ enabled: Bool) -> Bool {
    if enabled == userSpaceEnabled {
      if enabled && userSpaceDispatcher == nil {
        // Persisted state says enabled, but the user-space device isn't actually created
        // (common after application service restart). Fall through to create it.
      } else if !enabled && userSpaceDispatcher != nil {
        // Persisted state says disabled, but dispatcher still exists; fall through to disable.
      } else {
        return true
      }
    }

    if enabled {
      do {
        let build = try buildUserSpaceDispatcher(identity: compatibilityIdentity)
        userSpaceLock.withLock {
          userSpaceDispatcher = build.dispatcher
          foregroundConsumerDispatcherPool = build.foregroundConsumerPool
          dispatcher.setSecondary(build.dispatcher)
          userSpaceEnabled = true
          userSpaceStatus = build.status
        }
        UserDefaults.standard.set(true, forKey: Self.userSpaceEnabledDefaultsKey)
        print("[ApplicationServiceServer] Enabled user-space virtual gamepad")
        primeUserSpaceDevices(build.dispatcher)
        return true
      } catch {
        userSpaceLock.withLock {
          dispatcher.setSecondary(nil)
          userSpaceDispatcher = nil
          foregroundConsumerDispatcherPool = nil
          userSpaceEnabled = false
          userSpaceStatus = "error: \(error)"
        }
        UserDefaults.standard.set(false, forKey: Self.userSpaceEnabledDefaultsKey)
        print("[ApplicationServiceServer] Failed to enable user-space virtual gamepad: \(error)")
        return false
      }
    } else {
      userSpaceLock.withLock {
        dispatcher.setSecondary(nil)
        userSpaceDispatcher?.close()
        userSpaceDispatcher = nil
        foregroundConsumerDispatcherPool = nil
        userSpaceEnabled = false
        userSpaceStatus = "off"
      }
      UserDefaults.standard.set(false, forKey: Self.userSpaceEnabledDefaultsKey)
      print("[ApplicationServiceServer] Disabled user-space virtual gamepad")
      return true
    }
  }

  func setOutputModeInternal(_ modeRaw: String) -> Bool {
    guard let newMode = CompositeOutputDispatcher.Mode(rawValue: modeRaw) else { return false }
    switch newMode {
    case .primaryOnly: applyMode(.driverKit); return true
    case .secondaryOnly: applyMode(.compatUserSpace); return true
    case .both: applyMode(.both); return true
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
      for identifier in identifiers {
        await ud.dispatch(events: [], from: identifier)
      }
      userSpaceLock.withLock {
        if userSpaceDispatcher != nil {
          userSpaceStatus = ud.status
        }
      }
    }
  }

  @objc func handleDextUnstable(_ note: Notification) {
    // If DriverKit injection is unstable during sysext replacement/upgrade,
    // fall back to user-space-only when possible (no reboot).
    guard virtualDeviceMode == .auto || virtualDeviceMode == .both else { return }
    guard effectiveOutputMode != .secondaryOnly else { return }
    if userSpaceDispatcher == nil {
      guard setUserSpaceVirtualDeviceEnabledInternal(true) else { return }
    }
    effectiveOutputMode = .secondaryOnly
    dispatcher.setMode(.secondaryOnly)
    userSpaceStatus = "on (auto: DriverKit unstable, using user-space only until reboot)"
    print("[ApplicationServiceServer] Auto-fallback: DriverKit unstable -> user-space only")
  }

  func applyForegroundCompatibilityRoutingUpdate(
    frontmostBundleRootPath: String?,
    effectiveConsumerBundleRoots: Set<String>,
    observedConsumerBundleRoots: Set<String>,
    activeRouteToken: String?
  ) async {
    guard virtualDeviceMode == .compatUserSpace else { return }
    guard userSpaceEnabled else { return }
    guard
      let pool = userSpaceLock.withLock({ foregroundConsumerDispatcherPool })
    else { return }

    let retainedBundleRoots =
      ForegroundConsumerRouteSelection.retainedDedicatedBundleRootPaths(
        frontmostBundleRootPath: frontmostBundleRootPath,
        effectiveConsumerBundleRoots: effectiveConsumerBundleRoots,
        observedConsumerBundleRoots: observedConsumerBundleRoots,
        activeRouteToken: activeRouteToken
      )

    if let activeBundleRootPath = retainedBundleRoots.first {
      do {
        try pool.ensureDedicatedRoute(
          forConsumerBundleRootPath: activeBundleRootPath
        )
      } catch {
        print(
          "[ApplicationServiceServer] Failed to create dedicated Compatibility route for "
            + "\(URL(fileURLWithPath: activeBundleRootPath).lastPathComponent): \(error)"
        )
      }
    }

    await pool.setActiveRouteToken(activeRouteToken)
    pool.retainDedicatedRoutes(forConsumerBundleRootPaths: retainedBundleRoots)
    userSpaceLock.withLock {
      userSpaceStatus = pool.status
    }
  }
}
