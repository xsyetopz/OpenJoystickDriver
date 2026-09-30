import Foundation

let steamTritonFeatureReportID: UInt8 = 0x01
let steamTritonFeatureReportLength = 64
let steamTritonSetSettingsValuesCommand: UInt8 = 0x87
let steamTritonLizardModeSetting: UInt8 = 9
let steamTritonIMUModeSetting: UInt8 = 48
/// `SETTING_GYRO_MODE_SEND_RAW_ACCEL | SETTING_GYRO_MODE_SEND_RAW_GYRO`.
let steamTritonRawIMUMode: UInt8 = 0x18
let steamTritonRumbleReportID: UInt8 = 0x80
let steamTritonRumbleReportLength = 10
/// SDL `TRITON_RUMBLE_RESEND_INTERVAL_MS`: the firmware drops a rumble it does not hear again.
let steamTritonKeepAliveIntervalNanoseconds: UInt64 = 40_000_000
/// SDL resends lizard-mode-off every 3000 ms; the firmware watchdog restores lizard mode.
let steamTritonLizardResendTicks = 75

/// Driver for the 2026 Steam Controller (Triton) over USB, Bluetooth LE, and its dongles.
///
/// Source: SDL `src/joystick/hidapi/SDL_hidapi_steam_triton.c` and `steam/controller_structs.h`
/// at `release-3.4.16`. Inputs arrive as report `0x42` (USB and dongle), `0x45` (Bluetooth), or
/// `0x47` (16-bit timestamps). Settings travel as 64-byte feature reports with report ID 1, and
/// rumble as the 10-byte output report `0x80`, which must repeat while it runs. A dongle
/// interface has no controller until a wireless status or state report says so.
public final class SteamTritonDriver: PhysicalProtocolDriver {

  var state = ControllerState.neutral
  var imuClock: SonySensorClock?
  var lastIMUCounter: UInt32?
  var storedPower: ControllerConnectionState.Power?
  let isDongle: Bool
  var isLogicalControllerConnected: Bool
  var pendingConnectionStateChange: ControllerInputConnectionState?
  var rumble: (left: UInt16, right: UInt16) = (0, 0)
  var keepAliveTick = 0

  /// Creates a Triton driver; `isDongle` starts with no controller connected.
  public init(isDongle: Bool = false) {
    self.isDongle = isDongle
    isLogicalControllerConnected = !isDongle
  }

  public var capabilities: ControllerCapabilities {
    let extra: Set<ControlID> = [
      .guide, .auxiliary1, .leftTriggerButton, .rightTriggerButton, .paddleLeft1, .paddleLeft2,
      .paddleRight1, .paddleRight2, .leftStickTouch, .rightStickTouch, .leftTrackpadClick,
      .rightTrackpadClick, .leftTrackpadTouch, .rightTrackpadTouch,
    ]
    return ControllerCapabilities(
      controls: ControlID.xboxLayout.union(extra),
      touchContactCount: 1,
      motion: true
    )
  }

  /// SDL declares rumble only: no LED, no trigger rumble.
  public var outputCapabilities: PhysicalControllerOutputCapabilities {
    PhysicalControllerOutputCapabilities(
      rumbleMotors: [.leftMain, .rightMain],
      lightingFeatures: []
    )
  }

  public var defaultColor: ControllerColor? { nil }

  public var power: ControllerConnectionState.Power? { storedPower }

  public var sessionPlan: DriverSessionPlan {
    DriverSessionPlan(
      requiresInputConnectionBeforeOutput: isDongle,
      hidKeepAliveIntervalNanoseconds: steamTritonKeepAliveIntervalNanoseconds
    )
  }

  public func resetProtocolState() {
    state = .neutral
    imuClock?.reset()
    lastIMUCounter = nil
  }

  public func consumeInputConnectionStateChange() -> ControllerInputConnectionState? {
    let change = pendingConnectionStateChange
    pendingConnectionStateChange = nil
    return change
  }

  /// Lizard mode off and raw IMU on; the keep-alive repeats lizard mode off.
  public func activationWrites() -> [PhysicalOutputWrite] {
    keepAliveTick = 0
    return [
      .hidFeature(Self.setting(steamTritonLizardModeSetting, value: 0)),
      .hidFeature(Self.setting(steamTritonIMUModeSetting, value: UInt16(steamTritonRawIMUMode))),
    ]
  }

  /// IMU off. SDL sends no lizard-mode-on: the firmware restores it once the resends stop.
  public func deactivationWrites() -> [PhysicalOutputWrite] {
    rumble = (0, 0)
    return [.hidFeature(Self.setting(steamTritonIMUModeSetting, value: 0))]
  }

  public func inputConnectionWrites(
    for state: ControllerInputConnectionState
  ) -> [PhysicalOutputWrite] {
    switch state {
    case .connected: return activationWrites()
    case .disconnected:
      rumble = (0, 0)
      return []
    }
  }

  /// One 40 ms tick: lizard mode off every 3 s, and the running rumble again.
  public func keepAliveWrites() -> [PhysicalOutputWrite] {
    guard isLogicalControllerConnected else { return [] }
    var writes: [PhysicalOutputWrite] = []
    if keepAliveTick.isMultiple(of: steamTritonLizardResendTicks) {
      writes.append(.hidFeature(Self.setting(steamTritonLizardModeSetting, value: 0)))
    }
    keepAliveTick += 1
    if rumble != (0, 0) { writes.append(.hidOutput(rumbleReport())) }
    return writes
  }

  /// Low-frequency rumble drives the left motor and high-frequency the right, as in SDL.
  public func encode(
    _ command: ControllerOutputCommand
  ) throws(ControllerOutputError) -> PhysicalOutputPlan {
    switch command {
    case .setRumble(let intensities, _):
      rumble = (intensities.leftMain.rawValue, intensities.rightMain.rawValue)
    case .stopRumble: rumble = (0, 0)
    default: throw .unsupportedCapability(command.capability)
    }
    guard isLogicalControllerConnected else { return PhysicalOutputPlan(writes: []) }
    return PhysicalOutputPlan(writes: [.hidOutput(rumbleReport())])
  }

  /// `MsgHapticRumble`: type, intensity, then speed and gain per side.
  func rumbleReport() -> PhysicalHIDOutputReport {
    var bytes = [UInt8](repeating: 0, count: steamTritonRumbleReportLength)
    bytes[0] = steamTritonRumbleReportID
    bytes[4] = UInt8(truncatingIfNeeded: rumble.left)
    bytes[5] = UInt8(truncatingIfNeeded: rumble.left >> 8)
    bytes[7] = UInt8(truncatingIfNeeded: rumble.right)
    bytes[8] = UInt8(truncatingIfNeeded: rumble.right >> 8)
    return PhysicalHIDOutputReport(reportID: steamTritonRumbleReportID, bytes: bytes)
  }

  /// `ID_SET_SETTINGS_VALUES` with one `ControllerSetting` (number, 16-bit value).
  static func setting(_ number: UInt8, value: UInt16) -> PhysicalHIDOutputReport {
    var bytes = [UInt8](repeating: 0, count: steamTritonFeatureReportLength)
    bytes[0] = steamTritonFeatureReportID
    bytes[1] = steamTritonSetSettingsValuesCommand
    bytes[2] = 3
    bytes[3] = number
    bytes[4] = UInt8(truncatingIfNeeded: value)
    bytes[5] = UInt8(truncatingIfNeeded: value >> 8)
    return PhysicalHIDOutputReport(reportID: steamTritonFeatureReportID, bytes: bytes)
  }
}
