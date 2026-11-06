import Foundation

/// The message type of a Steam Deck state report.
let steamDeckStateMessageID: UInt8 = 0x09
/// The command byte of the simple rumble feature report.
let steamDeckTriggerRumbleCommand: UInt8 = 0xEB

/// Driver for the Steam Deck's built-in controller (Neptune).
///
/// Sources: SDL `src/joystick/hidapi/SDL_hidapi_steamdeck.c` and `steam/controller_structs.h`
/// (`SteamDeckStatePacket_t`), and Linux `hid-steam.c` (`STEAM_QUIRK_DECK`). Input is the 64-byte
/// `0x01 0x00` state report with message type `0x09`. Settings and rumble travel as 64-byte
/// feature reports with report ID 0, as on the wired Steam Controller. The IMU runs by default.
public final class SteamDeckDriver: PhysicalProtocolDriver {

  /// The state after the latest state report.
  var state = ControllerState.neutral
  /// Decodes the IMU sample of each state report.
  var motionSamples = SteamMotionSamples(layout: .steamDeck)

  /// Creates the driver for the Steam Deck's built-in controller.
  public init() {}

  /// The controls of the description.
  public var capabilities: ControllerCapabilities {
    PhysicalProtocolID.valveSteamDeck.describedControls
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

  /// The description's keep-alive interval is OJD's watchdog feed period.
  ///
  /// SDL feeds after 200 update passes and Linux disables the watchdog instead; the Deck reports
  /// every 4 ms, so one second stays well inside SDL's cadence.
  public var sessionPlan: DriverSessionPlan {
    DriverSessionPlan(
      keepAliveChannels: [.hid]
    ).withKeepAlive(of: .valveSteamDeck)
  }

  /// The Deck's controller is built in, so it has no logical connection state.
  public func consumeInputConnectionStateChange() -> ControllerInputConnectionState? { nil }

  /// Clears the state and the motion samples, so the next report starts from neutral.
  public func resetProtocolState() {
    state = .neutral
    motionSamples.reset()
  }

  /// SDL `DisableDeckLizardMode`: clear the digital mappings, then trackpad mouse and haptic click
  /// off.
  ///
  /// Linux `steam_set_lizard_mode` also turns off the watchdog that restores lizard mode while
  /// Steam is not running.
  public func activationWrites() -> [PhysicalOutputWrite] {
    PhysicalProtocolID.valveSteamDeck.protocolDescription.activationWrites(over: nil)
  }

  /// Linux `steam_set_lizard_mode(true)`: default digital mappings, then default settings.
  public func deactivationWrites() -> [PhysicalOutputWrite] {
    PhysicalProtocolID.valveSteamDeck.protocolDescription.deactivationWrites(over: nil)
  }

  /// SDL `FeedDeckLizardWatchdog`, for firmware that ignores the watchdog setting.
  public func keepAliveWrites() -> [PhysicalOutputWrite] {
    PhysicalProtocolID.valveSteamDeck.keepAliveWrites(variant: nil).map {
      $0.output(defaultEndpoint: 0, defaultTimeoutMilliseconds: 0)
    }
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
      (left, right) = (intensities.lowFrequency.rawValue, intensities.highFrequency.rawValue)
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

  /// A 64-byte feature report with report ID 0 that carries `command`, zero-padded.
  static func featureReport(_ command: [UInt8]) -> PhysicalHIDOutputReport {
    var bytes = [UInt8](repeating: 0, count: steamControllerReportLength)
    bytes.replaceSubrange(0..<command.count, with: command)
    return PhysicalHIDOutputReport(reportID: 0, bytes: bytes)
  }
}
