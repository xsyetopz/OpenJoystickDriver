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
  let userSpaceLock = NSLock()
  var userSpaceDispatcher: (any CompatibilityUserSpaceOutputDispatching)?
  var userSpaceEnabled: Bool
  var userSpaceStatus: String = "off"
  var compatibilityIdentity: CompatibilityIdentity
  var rpcServer: LocalServiceRPCServer?
  static let compatibilityIdentityDefaultsKey = "CompatibilityIdentity"

  struct UserSpaceDispatcherBuild {
    let dispatcher: any CompatibilityUserSpaceOutputDispatching
    let status: String
  }

  /// Creates a server backed by the device manager, permissions, and output dispatchers.
  init(
    deviceManager: DeviceManager,
    permissionManager: PermissionManager,
    dispatcher: CompatibilityOutputDispatcher,
    remappingProfileLibrary: RemappingProfileLibrary,
    remappingRouter: RemappingOutputRouter,
    postEventAccess: CoreGraphicsPostEventAccess
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
    self.userSpaceEnabled = false
    let savedCompat = UserDefaults.standard.string(forKey: Self.compatibilityIdentityDefaultsKey)
    self.compatibilityIdentity =
      CompatibilityIdentity(rawValue: savedCompat ?? "") ?? .appleGameController
    super.init()

    // Consumer routing used to be selectable. Discard every stale selection and always
    // initialize the sole supported consumer backend.
    UserDefaults.standard.removeObject(forKey: "UserSpaceVirtualDeviceEnabled")
    UserDefaults.standard.removeObject(forKey: "OutputMode")
    UserDefaults.standard.removeObject(forKey: "VirtualDeviceMode")
    _ = initializeCompatibilityBackend()
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
    let compatibilityProfile = CompatibilityOutputProfileCatalog.profile(for: identity)
    let profile = compatibilityProfile.deviceProfile
    let format: any VirtualGamepadReportFormat
    switch identity {
    case .genericHID: format = OJDSDLGamepadFormat()
    case .sdl2_3: format = Xbox360MacHIDReportFormat()
    case .appleGameController:
      format = Xbox360MacHIDReportFormat(topLevelUsage: UInt8(kHIDUsage_GD_GamePad))
    case .xoneHID:
      // Xbox One identity for XInput/XUSB-style consumers:
      // - Prefer the physical HID report descriptor exposed by macOS for 045E:02EA (USB).
      // - Fall back to a built-in descriptor if the physical device is not present.
      let physicalDescriptor: [UInt8]?
      if #available(macOS 15, *) {
        physicalDescriptor = nil
      } else {
        physicalDescriptor = HIDDescriptorReportFormat.copyPhysicalReportDescriptor(
          vendorID: profile.vendorID,
          productID: profile.productID,
          preferredTransport: "USB"
        )
      }
      if let physical = physicalDescriptor {
        do {
          format = try HIDDescriptorReportFormat(
            descriptor: physical,
            outputReportID: VirtualRumbleOutputReportParser.xboxGIPReportID,
            outputReportPayloadSize: VirtualRumbleOutputReportParser
              .xboxGIPReportPayloadSizeWithoutReportID
          )
        } catch {
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

    let output = try UserSpaceOutputDispatcher(
      profile: profile,
      format: format,
      emitsXboxGuideReport: compatibilityProfile.emitsXboxGuideReport,
      onRumbleCommand: rumbleHandler
    )
    return UserSpaceDispatcherBuild(dispatcher: output, status: output.status)
  }

  func initializeCompatibilityBackend() -> Bool {
    if userSpaceEnabled, userSpaceDispatcher != nil { return true }
    do {
      let build = try buildUserSpaceDispatcher(identity: compatibilityIdentity)
      userSpaceLock.withLock {
        userSpaceDispatcher = build.dispatcher
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

}
