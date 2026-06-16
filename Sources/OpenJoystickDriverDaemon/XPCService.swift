import Foundation
import IOKit
import IOKit.hid
import OpenJoystickDriverKit

/// Wraps non-Sendable XPC reply closure so it can cross Task boundary.
///
/// Safe because XPC dispatches reply blocks on its own serial queue.
struct SendableReply<T>: @unchecked Sendable { let call: (T) -> Void }

/// NSXPCListener server that exposes DeviceManager state to GUI/CLI over Mach IPC.
///
/// Call start() once; listener lives for process lifetime.
/// - Note: @unchecked Sendable: XPCService is thread-safe -
///   actor-isolated DeviceManager/PermissionManager handle
///   their own synchronization; reply blocks are dispatched
///   by XPC runtime.
@objc
public final class XPCService: NSObject, NSXPCListenerDelegate, OpenJoystickDriverXPCProtocol,
  @unchecked Sendable
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
  var listener: NSXPCListener?
  static let userSpaceEnabledDefaultsKey = "UserSpaceVirtualDeviceEnabled"
  static let compatibilityIdentityDefaultsKey = "CompatibilityIdentity"
  static let outputModeDefaultsKey = "OutputMode"
  static let virtualDeviceModeDefaultsKey = "VirtualDeviceMode"

  struct UserSpaceDispatcherBuild {
    let dispatcher: any CompatibilityUserSpaceOutputDispatching
    let foregroundConsumerPool: ForegroundConsumerCompatibilityDispatcherPool?
    let status: String
  }

  /// Creates an XPCService backed by the given device manager, permission manager, and output dispatcher.
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

  /// Register Mach service and start accepting connections.
  public func start() {
    let xpcListener = NSXPCListener(machServiceName: xpcServiceName)
    xpcListener.delegate = self
    xpcListener.resume()
    listener = xpcListener
    print("[XPCService] Listening on \(xpcServiceName)")
  }

  // MARK: - NSXPCListenerDelegate

  /// Configures and resumes each incoming XPC connection.
  public func listener(
    _ listener: NSXPCListener,
    shouldAcceptNewConnection connection: NSXPCConnection
  ) -> Bool {
    connection.exportedInterface = NSXPCInterface(with: OpenJoystickDriverXPCProtocol.self)
    connection.exportedObject = self
    connection.resume()
    print("[XPCService] Accepted new connection")
    return true
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
        // (common after daemon restart). Fall through to create it.
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
        print("[XPCService] Enabled user-space virtual gamepad")
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
        print("[XPCService] Failed to enable user-space virtual gamepad: \(error)")
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
      print("[XPCService] Disabled user-space virtual gamepad")
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
    print("[XPCService] Auto-fallback: DriverKit unstable -> user-space only")
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

    let routeBundleRoots = observedConsumerBundleRoots.union(effectiveConsumerBundleRoots)
    let prioritizedRouteBundleRoots = routeBundleRoots.sorted {
      switch ($0 == frontmostBundleRootPath, $1 == frontmostBundleRootPath) {
      case (true, false): return true
      case (false, true): return false
      default:
        return $0 < $1
      }
    }

    for bundleRootPath in prioritizedRouteBundleRoots {
      do {
        try await pool.ensureDedicatedRoute(forConsumerBundleRootPath: bundleRootPath)
      } catch {
        print(
          "[XPCService] Failed to create dedicated Compatibility route for "
            + "\(URL(fileURLWithPath: bundleRootPath).lastPathComponent): \(error)"
        )
      }
    }

    await pool.setActiveRouteToken(activeRouteToken)
    userSpaceLock.withLock {
      userSpaceStatus = pool.status
    }
  }
}
