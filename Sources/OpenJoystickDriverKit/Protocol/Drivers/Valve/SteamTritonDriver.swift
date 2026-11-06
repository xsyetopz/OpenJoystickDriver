import Foundation

/// The report ID of the rumble output report.
let steamTritonRumbleReportID: UInt8 = 0x80
/// The length of the rumble output report in bytes.
let steamTritonRumbleReportLength = 10

/// Driver for the 2026 Steam Controller (Triton) over USB, Bluetooth LE, and its dongles.
///
/// Source: SDL `src/joystick/hidapi/SDL_hidapi_steam_triton.c` and `steam/controller_structs.h`
/// at `release-3.4.16`. Inputs arrive as report `0x42` (USB and dongle), `0x45` (Bluetooth), or
/// `0x47` (16-bit timestamps). Settings travel as 64-byte feature reports with report ID 1, and
/// rumble as the 10-byte output report `0x80`, which must repeat while it runs. A dongle
/// interface has no controller until a wireless status or state report says so.
public final class SteamTritonDriver: PhysicalProtocolDriver {

  /// The state after the latest state report.
  var state = ControllerState.neutral
  /// Converts the IMU counter to sample time; nil until the first IMU sample.
  var imuClock: SonySensorClock?
  /// The IMU counter of the latest sample; a repeated counter is skipped.
  var lastIMUCounter: UInt32?
  /// The battery and charging state from the latest battery report.
  var storedPower: ControllerConnectionState.Power?
  /// Whether the interface is a dongle's, which has no controller until a report shows one.
  let isDongle: Bool
  /// Whether a logical controller is connected; always true unless a dongle says otherwise.
  var isLogicalControllerConnected: Bool
  /// The connection change that ``consumeInputConnectionStateChange()`` has not returned.
  var pendingConnectionStateChange: ControllerInputConnectionState?
  /// The latest rumble levels, left and right.
  var rumble: (left: UInt16, right: UInt16) = (0, 0)
  /// The number of keep-alive ticks since activation.
  var keepAliveTick = 0
  /// Keep-alive ticks between lizard-mode-off resends (`lizardResendTicks`): SDL resends every
  /// 3000 ms, and the firmware watchdog restores lizard mode if the resends stop.
  let lizardResendTicks: Int

  /// Creates a Triton driver; `isDongle` starts with no controller connected. `tuning` is the
  /// effective tuning of the controller's record; the description's defaults when nil.
  public init(isDongle: Bool = false, tuning: ControllerTuning? = nil) {
    self.isDongle = isDongle
    lizardResendTicks = PhysicalProtocolID.valveSteamTriton.described(
      \.lizardResendTicks,
      in: tuning
    )
    isLogicalControllerConnected = !isDongle
  }

  /// The controls of the description.
  public var capabilities: ControllerCapabilities {
    PhysicalProtocolID.valveSteamTriton.describedControls
  }

  /// SDL declares rumble only: no LED, no trigger rumble.
  public var outputCapabilities: PhysicalControllerOutputCapabilities {
    PhysicalControllerOutputCapabilities(
      rumbleMotors: [.lowFrequency, .highFrequency],
      lightingFeatures: []
    )
  }

  /// No default colour: the controller has no light to restore.
  public var defaultColor: ControllerColor? { nil }

  /// The battery state of the latest report.
  public var power: ControllerConnectionState.Power? { storedPower }

  /// The description's keep-alive interval is SDL `TRITON_RUMBLE_RESEND_INTERVAL_MS`: the firmware
  /// drops a rumble it does not hear again.
  public var sessionPlan: DriverSessionPlan {
    DriverSessionPlan(
      requiresInputConnectionBeforeOutput: isDongle,
      keepAliveChannels: [.hid]
    ).withKeepAlive(of: .valveSteamTriton)
  }

  /// Clears the state and the motion clock, so the next report starts from neutral.
  public func resetProtocolState() {
    state = .neutral
    imuClock?.reset()
    lastIMUCounter = nil
  }

  /// Returns the pending connection change and clears it.
  public func consumeInputConnectionStateChange() -> ControllerInputConnectionState? {
    let change = pendingConnectionStateChange
    pendingConnectionStateChange = nil
    return change
  }

  /// Lizard mode off and raw IMU on; the keep-alive repeats lizard mode off.
  public func activationWrites() -> [PhysicalOutputWrite] {
    keepAliveTick = 0
    return PhysicalProtocolID.valveSteamTriton.protocolDescription.activationWrites(over: nil)
  }

  /// IMU off.
  ///
  /// SDL sends no lizard-mode-on: the firmware restores it once the resends stop.
  public func deactivationWrites() -> [PhysicalOutputWrite] {
    rumble = (0, 0)
    return PhysicalProtocolID.valveSteamTriton.protocolDescription.deactivationWrites(over: nil)
  }

  /// The writes that follow a change of the controller's connection: activation on connect; on
  /// disconnect the rumble is cleared and nothing is written.
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
    var writes = PhysicalProtocolID.valveSteamTriton.keepAliveWrites(variant: nil)
      .filter { $0.isDue(tick: keepAliveTick, resendTicks: lizardResendTicks) }
      .map { $0.output(defaultEndpoint: 0, defaultTimeoutMilliseconds: 0) }
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
      rumble = (intensities.lowFrequency.rawValue, intensities.highFrequency.rawValue)
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
}
