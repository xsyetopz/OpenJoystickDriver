import Foundation

/// Mach service name shared by the daemon and any client (GUI or CLI).
///
/// Both sides must use the same name to establish a connection.
public let xpcServiceName = "com.openjoystickdriver.xpc"

/// Which identity/protocol the user-space Compatibility virtual device should publish.
///
/// IMPORTANT:
/// - `sdl2-3` and `generic-hid` publish a browser-compatible Xbox 360 HID surface because
///   Safari's Gamepad API is GameController-backed and rejects OJD-owned virtual identities.
/// - `apple-gamecontroller` publishes the HID surface accepted by Apple's GameController.framework.
/// - `xone-hid` and `x360-hid` are hardware-spoof profiles. They are only correct for
///   consumers whose expected descriptor/report layout exactly matches the selected profile.
public enum CompatibilityIdentity: Codable, CaseIterable, Sendable, Equatable {
  case genericHID
  case sdl2_3
  case appleGameController
  case x360HID
  case xoneHID

  public static let allCases: [Self] = [
    .genericHID,
    .sdl2_3,
    .appleGameController,
    .x360HID,
    .xoneHID,
  ]

  public init?(rawValue: String) {
    switch rawValue {
    case "generic-hid":
      self = .genericHID
    case "sdl2-3":
      self = .sdl2_3
    case "apple-gamecontroller":
      self = .appleGameController
    case "x360-hid":
      self = .x360HID
    case "xone-hid":
      self = .xoneHID
    default:
      return nil
    }
  }

  public var rawValue: String {
    switch self {
    case .genericHID: "generic-hid"
    case .sdl2_3: "sdl2-3"
    case .appleGameController: "apple-gamecontroller"
    case .x360HID: "x360-hid"
    case .xoneHID: "xone-hid"
    }
  }

  public init(from decoder: Decoder) throws {
    let raw = try decoder.singleValueContainer().decode(String.self)
    guard let value = Self(rawValue: raw) else {
      throw DecodingError.dataCorrupted(
        .init(
          codingPath: decoder.codingPath,
          debugDescription: "Unknown compatibility identity: \(raw)"
        )
      )
    }
    self = value
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }

  public var disablesDriverKitMirror: Bool {
    switch self {
    case .genericHID, .sdl2_3:
      true
    case .appleGameController:
      false
    case .xoneHID, .x360HID:
      false
    }
  }

  public var seizesDriverKitInCompatibilityMode: Bool {
    true
  }
}

/// Which virtual device output path the daemon should actively drive.
///
/// - `auto`: prefer DriverKit, fall back to user-space only if DriverKit output is unstable.
/// - `driverKit`: send reports to the DriverKit dext only.
/// - `compatUserSpace`: create an IOHIDUserDevice and send reports to it only.
/// - `both`: send reports to both (developer-only; can cause double input).
public enum VirtualDeviceMode: String, Codable, CaseIterable, Sendable {
  case auto
  case driverKit
  case compatUserSpace
  case both
}

/// The contract between the daemon process and its clients (GUI app, CLI).
///
/// XPC (cross-process communication) lets the GUI and CLI talk to the daemon
/// without running in the same process. NSXPCConnection requires an Objective-C
/// compatible protocol, so all complex types are JSON-encoded as `Data`.
@objc public protocol OpenJoystickDriverXPCProtocol: AnyObject {
  /// Lists all connected controllers.
  /// Replies with an array of human-readable device description strings.
  func listDevices(reply: @escaping ([String]) -> Void)

  /// Queries the daemon for its current status.
  /// Replies with JSON-encoded ``XPCStatusPayload`` containing permission states
  /// and connected device descriptions.
  func getStatus(reply: @escaping (Data) -> Void)

  /// Requests Input Monitoring permission from the daemon process.
  /// Replies with the daemon's updated permission state.
  func requestInputMonitoringAccess(reply: @escaping (String) -> Void)

  /// Gets the latest input state (buttons, sticks, triggers) for a device.
  /// Replies with JSON-encoded ``DeviceInputState``, or nil if no input has been received yet.
  @objc func getDeviceInputState(vendorID: Int, productID: Int, reply: @escaping (Data?) -> Void)

  /// Gets the latest input state for a device, disambiguated by serial or location when present.
  @objc func getDeviceInputState(
    vendorID: Int,
    productID: Int,
    serialNumber: String?,
    locationID: Int,
    reply: @escaping (Data?) -> Void
  )

  /// Gets recent raw packets sent to or received from a device.
  /// Replies with a JSON-encoded array of ``PacketLogEntry``.
  @objc func getPacketLog(vendorID: Int, productID: Int, reply: @escaping (Data) -> Void)

  /// Gets recent raw packets for a device, disambiguated by serial or location when present.
  @objc func getPacketLog(
    vendorID: Int,
    productID: Int,
    serialNumber: String?,
    locationID: Int,
    reply: @escaping (Data) -> Void
  )

  /// Sends a short physical rumble command to a connected USB controller.
  @objc func sendPhysicalRumble(
    vendorID: Int,
    productID: Int,
    left: Int,
    right: Int,
    lt: Int,
    rt: Int,
    durationMs: Int,
    reply: @escaping (Bool) -> Void
  )

  /// Sends a physical rumble command to a device, disambiguated by serial or location when present.
  @objc func sendPhysicalRumble(
    vendorID: Int,
    productID: Int,
    serialNumber: String?,
    locationID: Int,
    left: Int,
    right: Int,
    lt: Int,
    rt: Int,
    durationMs: Int,
    reply: @escaping (Bool) -> Void
  )

  /// Enables or disables keyboard/mouse output from button mappings.
  /// Pass true to suppress output (useful during developer packet capture).
  /// Replies with true to confirm the change.
  @objc func setSuppressOutput(_ suppress: Bool, reply: @escaping (Bool) -> Void)

  /// Sets the daemon virtual device mode.
  ///
  /// Values: "driverKit", "compatUserSpace", or "both".
  @objc func setVirtualDeviceMode(_ modeRaw: String, reply: @escaping (Bool) -> Void)

  /// Gets the daemon virtual device mode.
  ///
  /// Values: "driverKit", "compatUserSpace", or "both".
  @objc func getVirtualDeviceMode(reply: @escaping (String) -> Void)

  /// Enables/disables the user-space virtual gamepad (IOHIDUserDevice).
  ///
  /// This is a no-reboot compatibility mode for apps that ignore DriverKit
  /// virtual HID devices.
  @objc func setUserSpaceVirtualDeviceEnabled(_ enabled: Bool, reply: @escaping (Bool) -> Void)

  /// Returns whether the user-space virtual gamepad is enabled.
  @objc func getUserSpaceVirtualDeviceEnabled(reply: @escaping (Bool) -> Void)

  /// Returns a short status string for the user-space virtual gamepad.
  @objc func getUserSpaceVirtualDeviceStatus(reply: @escaping (String) -> Void)

  /// Returns a diagnostics snapshot of HID gamepad devices as seen by IOKit.
  ///
  /// Reply is JSON-encoded ``XPCVirtualDeviceDiagnosticsPayload``.
  @objc func getVirtualDeviceDiagnostics(reply: @escaping (Data) -> Void)

  /// Sets which identity/protocol to emulate in Compatibility mode (user-space IOHIDUserDevice).
  ///
  /// Values: "generic-hid", "sdl2-3", "x360-hid", "xone-hid".
  @objc func setCompatibilityIdentity(_ raw: String, reply: @escaping (Bool) -> Void)

  /// Gets which identity/protocol is configured for Compatibility mode.
  @objc func getCompatibilityIdentity(reply: @escaping (String) -> Void)

  /// Sets the daemon output routing mode.
  ///
  /// Values: "primaryOnly", "secondaryOnly", or "both".
  @objc func setOutputMode(_ mode: String, reply: @escaping (Bool) -> Void)

  /// Gets the daemon output routing mode.
  ///
  /// Values: "primaryOnly", "secondaryOnly", or "both".
  @objc func getOutputMode(reply: @escaping (String) -> Void)

  /// Runs a short self-test that listens for input events on OJD virtual devices.
  ///
  /// Reply is JSON-encoded ``XPCVirtualDeviceSelfTestPayload``.
  @objc func runVirtualDeviceSelfTest(seconds: Int, reply: @escaping (Data) -> Void)

  /// Resets daemon persisted settings (mode/output/compat identity) to defaults.
  @objc func resetSettings(reply: @escaping (Bool) -> Void)
}
