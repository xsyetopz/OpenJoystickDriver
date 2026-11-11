import Foundation

/// The length of a GameSir report in bytes.
let gameSirReportLength = 64
/// The spacing of lighting commands: the description's default output interval.
let gameSirCommandIntervalNanoseconds =
  DriverSessionPlan().withDefaults(of: .vendorGameSir).minimumHIDOutputIntervalNanoseconds

/// GameSir protocol families backed by the vendor's observed report streams.
public enum GameSirProtocol: Sendable, Equatable {
  /// The wired G7 Pro over raw USB.
  case g7ProUSB
  /// The enhanced HID report stream.
  case enhancedHID
}

/// Driver for source-backed GameSir controller identities.
public final class GameSirDriver: PhysicalProtocolDriver {
  /// The report stream of the bound controller.
  let gameSirProtocol: GameSirProtocol
  /// Enhanced HID extras report the inner grips (parameter `innerGrips`).
  let hasInnerGrips: Bool
  /// Enhanced HID lighting memory is slot-based (parameter `lightingMemory: ProfileSlots`).
  let usesLightingSlots: Bool
  /// The interrupt OUT endpoint of the bound USB interface.
  let outEndpoint: UInt8
  /// The enhanced HID rumble report.
  ///
  /// The wired G7 Pro encodes it too but advertises no rumble.
  let rumbleTemplate: RumbleOutputTemplate
  /// Raw-USB command timeout (`usbCommandTimeoutMs`).
  let usbTimeoutMilliseconds: UInt32
  /// The decoder of the standard XUSB reports of the wired G7.
  var standardParser = XUSBDriver()
  /// The state after the latest report.
  var state = ControllerState.neutral
  /// The wired G7 splits input over two streams, standard XUSB reports and telemetry; each applies
  /// only the controls it changed, measured against its own last decode.
  var standardState = ControllerState.neutral
  /// The controls that the telemetry stream last reported.
  var telemetryExtras = ControllerState.neutral
  /// The sequence byte of the latest command.
  var sequence: UInt8 = 0
  /// Whether the controller has completed its startup handshake.
  var sessionReady = false
  /// The lighting slot that the controller reported active.
  var activeLightingSlot: UInt8?
  /// The lighting brightness, 100 until set.
  var lightingBrightness: UInt8 = 100
  /// The battery state of the latest report.
  var storedPower: ControllerConnectionState.Power?

  /// Creates a driver for the report stream `gameSirProtocol`.
  ///
  /// - Parameters:
  ///   - gameSirProtocol: The report stream of the bound controller.
  ///   - hasInnerGrips: Whether the controller reports the inner grips.
  ///   - usesLightingSlots: Whether the lighting memory is slot-based.
  ///   - outEndpoint: Interrupt OUT endpoint of the bound USB interface, for keep-alive and
  ///     brightness.
  ///   - tuning: The effective tuning of the controller's record; the description's defaults
  ///     when nil.
  ///   - rumbleTemplate: The record's rumble template; the description's for enhanced HID when
  ///     nil.
  public init(
    protocol gameSirProtocol: GameSirProtocol,
    hasInnerGrips: Bool = false,
    usesLightingSlots: Bool = false,
    outEndpoint: UInt8 = 0x02,
    tuning: ControllerTuning? = nil,
    rumbleTemplate: RumbleOutputTemplate? = nil
  ) {
    self.gameSirProtocol = gameSirProtocol
    self.hasInnerGrips = hasInnerGrips
    self.usesLightingSlots = usesLightingSlots
    self.outEndpoint = outEndpoint
    self.rumbleTemplate = PhysicalProtocolID.vendorGameSir.describedRumbleTemplate(
      variant: .enhancedHID,
      record: rumbleTemplate
    )
    usbTimeoutMilliseconds = UInt32(
      PhysicalProtocolID.vendorGameSir.described(\.usbCommandTimeoutMilliseconds, in: tuning)
    )
  }
}
