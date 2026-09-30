import Foundation

let steamDeckStateMessageID: UInt8 = 0x09
let steamDeckTriggerRumbleCommand: UInt8 = 0xEB
let steamDeckSmoothAbsoluteMouseSetting: UInt8 = 24
let steamDeckLeftTrackpadClickPressureSetting: UInt8 = 52
let steamDeckRightTrackpadClickPressureSetting: UInt8 = 53
let steamDeckWatchdogEnableSetting: UInt8 = 71
/// OJD's watchdog feed period. SDL feeds after 200 update passes and Linux disables the watchdog
/// instead; the Deck reports every 4 ms, so one second stays well inside SDL's cadence.
let steamDeckKeepAliveIntervalNanoseconds: UInt64 = 1_000_000_000

/// Driver for the Steam Deck's built-in controller (Neptune).
///
/// Sources: SDL `src/joystick/hidapi/SDL_hidapi_steamdeck.c` and `steam/controller_structs.h`
/// (`SteamDeckStatePacket_t`), and Linux `hid-steam.c` (`STEAM_QUIRK_DECK`). Input is the 64-byte
/// `0x01 0x00` state report with message type `0x09`. Settings and rumble travel as 64-byte
/// feature reports with report ID 0, as on the wired Steam Controller. The IMU runs by default.
public final class SteamDeckDriver: PhysicalProtocolDriver {

  var state = ControllerState.neutral
  var motionSamples = SteamMotionSamples(layout: .steamDeck)

  public init() {}

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

  public var sessionPlan: DriverSessionPlan {
    DriverSessionPlan(hidKeepAliveIntervalNanoseconds: steamDeckKeepAliveIntervalNanoseconds)
  }

  /// The Deck's controller is built in, so it has no logical connection state.
  public func consumeInputConnectionStateChange() -> ControllerInputConnectionState? { nil }

  public func resetProtocolState() {
    state = .neutral
    motionSamples.reset()
  }

  /// SDL `DisableDeckLizardMode`: clear the digital mappings, then trackpad mouse and haptic click
  /// off. Linux `steam_set_lizard_mode` also turns off the watchdog that restores lizard mode
  /// while Steam is not running.
  public func activationWrites() -> [PhysicalOutputWrite] {
    let settings: [(UInt8, UInt16)] = [
      (steamDeckSmoothAbsoluteMouseSetting, 0),
      (steamControllerLeftTrackpadModeSetting, UInt16(steamControllerTrackpadNone)),
      (steamControllerRightTrackpadModeSetting, UInt16(steamControllerTrackpadNone)),
      (steamDeckLeftTrackpadClickPressureSetting, 0xFFFF),
      (steamDeckRightTrackpadClickPressureSetting, 0xFFFF), (steamDeckWatchdogEnableSetting, 0),
    ]
    return [
      .hidFeature(Self.featureReport(steamControllerClearDigitalMappingsPayload)),
      .hidFeature(Self.settingsReport(settings)),
    ]
  }

  /// Linux `steam_set_lizard_mode(true)`: default digital mappings, then default settings.
  public func deactivationWrites() -> [PhysicalOutputWrite] {
    [
      .hidFeature(Self.featureReport(steamControllerDefaultDigitalMappingsPayload)),
      .hidFeature(Self.featureReport(steamControllerLoadDefaultSettingsPayload)),
    ]
  }

  /// SDL `FeedDeckLizardWatchdog`, for firmware that ignores the watchdog setting.
  public func keepAliveWrites() -> [PhysicalOutputWrite] {
    let rightTrackpadNone = [
      (steamControllerRightTrackpadModeSetting, UInt16(steamControllerTrackpadNone))
    ]
    return [
      .hidFeature(Self.featureReport(steamControllerClearDigitalMappingsPayload)),
      .hidFeature(Self.settingsReport(rightTrackpadNone)),
    ]
  }

  /// SDL `HIDAPI_DriverSteamDeck_RumbleJoystick`: `MsgSimpleRumbleCmd` with system intensity,
  /// low-frequency rumble on the left motor, and SDL's fixed gains.
  public func encode(
    _ command: ControllerOutputCommand
  ) throws(ControllerOutputError) -> PhysicalOutputPlan {
    let left: UInt16
    let right: UInt16
    switch command {
    case .setRumble(let intensities, _):
      (left, right) = (intensities.leftMain.rawValue, intensities.rightMain.rawValue)
    case .stopRumble: (left, right) = (0, 0)
    default: throw .unsupportedCapability(command.capability)
    }
    let rumble: [UInt8] = [
      steamDeckTriggerRumbleCommand, 0, 0, 0, 0, UInt8(truncatingIfNeeded: left),
      UInt8(truncatingIfNeeded: left >> 8), UInt8(truncatingIfNeeded: right),
      UInt8(truncatingIfNeeded: right >> 8), 2, 0,
    ]
    return PhysicalOutputPlan(writes: [.hidFeature(Self.featureReport(rumble))])
  }

  /// `ID_SET_SETTINGS_VALUES` with one 3-byte `ControllerSetting` per entry.
  static func settingsReport(_ settings: [(UInt8, UInt16)]) -> PhysicalHIDOutputReport {
    var command = [steamControllerSetSettingsValuesCommand, UInt8(settings.count * 3)]
    for (number, value) in settings {
      command += [number, UInt8(truncatingIfNeeded: value), UInt8(truncatingIfNeeded: value >> 8)]
    }
    return featureReport(command)
  }

  static func featureReport(_ command: [UInt8]) -> PhysicalHIDOutputReport {
    var bytes = [UInt8](repeating: 0, count: steamControllerReportLength)
    bytes.replaceSubrange(0..<command.count, with: command)
    return PhysicalHIDOutputReport(reportID: 0, bytes: bytes)
  }
}
