import Foundation

/// Report type byte for Xbox 360 input reports.
private let xbox360InputReportType: UInt8 = 0x00
/// Expected length byte and minimum size for a wired Xbox 360 input report.
private let xbox360InputReportLengthByte: UInt8 = 0x14
private let xbox360InputReportLength = 20
/// Maximum value for a trigger axis (UInt8).
private let xbox360TriggerMax: Float = 255
/// Maximum positive value for a signed stick axis.
private let xbox360StickMax = Float(Int16.max)

/// Xbox 360 ring-of-light LED patterns.
public enum Xbox360LEDPattern: UInt8, Sendable {
  case allOff = 0x00
  case allBlink = 0x01
  /// Player 1: flash then hold.
  case player1Flash = 0x02
  /// Player 2: flash then hold.
  case player2Flash = 0x03
  /// Player 3: flash then hold.
  case player3Flash = 0x04
  /// Player 4: flash then hold.
  case player4Flash = 0x05
  /// Player 1: steady on.
  case player1On = 0x06
  /// Player 2: steady on.
  case player2On = 0x07
  /// Player 3: steady on.
  case player3On = 0x08
  /// Player 4: steady on.
  case player4On = 0x09
  case rotate = 0x0A
  case blinkCurrent = 0x0B
  case slowBlinkCurrent = 0x0C
  case rotateTwo = 0x0D
  case blinkAll = 0x0E
  case blinkOnceThenRestore = 0x0F
}

/// Driver for Xbox 360 wired controllers (vendor-specific USB class 0xFF, interface 0) and one
/// slot of the Xbox 360 wireless receiver.
///
/// A wired controller needs no handshake: it begins sending 20-byte input reports immediately
/// after the interface is claimed. A receiver slot is asked for its presence at startup and
/// establishes presence from a connection notification or a valid input report. Wireless
/// reports carry a four-byte envelope and need only the 14 bytes containing controller state;
/// their inner length byte does not follow the wired report's length convention.
///
/// Input report layout (20 bytes, interrupt IN, EP 0x81):
/// ```
///   byte 0   : report type (0x00 = input; ignore others)
///   byte 1   : payload length (0x14 = 20)
///   bytes 2-3: button bitmask (UInt16 LE), matching Linux xpad
///              xbox360_process_packet: byte2 | (byte3 << 8)
///              bit 0  DPAD_UP      bit 8  LB
///              bit 1  DPAD_DOWN    bit 9  RB
///              bit 2  DPAD_LEFT    bit 10 GUIDE
///              bit 3  DPAD_RIGHT   bit 11 unused
///              bit 4  START        bit 12 A
///              bit 5  BACK         bit 13 B
///              bit 6  L3           bit 14 X
///              bit 7  R3           bit 15 Y
///   byte 4   : LT (0–255)
///   byte 5   : RT (0–255)
///   bytes 6-7: Left stick X  (Int16 LE)
///   bytes 8-9: Left stick Y  (Int16 LE, positive = up)
///   bytes 10-11: Right stick X (Int16 LE)
///   bytes 12-13: Right stick Y (Int16 LE, positive = up)
///   bytes 14-19: unused
/// ```
///
/// The rumble packet is the rumble template of the controller's variant (`wired` or `receiver`):
/// the record's when it sets one, otherwise the description's `defaults.variants`.
///
/// LED output report (3 bytes, interrupt OUT, EP 0x01):
/// ```
///   byte 0 : 0x01 (LED command)
///   byte 1 : 0x03 (length)
///   byte 2 : LED pattern (see Xbox360LEDPattern)
/// ```
public final class XUSBDriver: PhysicalProtocolDriver {
  private let outEndpoint: UInt8
  private let isWirelessReceiver: Bool
  private var receiverConnected = false
  private var pendingConnectionState: ControllerInputConnectionState?
  /// The timeout of one output packet that names none (`usbTransferTimeoutMs`).
  let usbTimeoutMilliseconds: Int
  /// The record's own startup packets; the description's when empty.
  private let recordStartup: [USBStartupWrite]
  /// The packet that carries the motor intensities.
  private let rumbleTemplate: RumbleOutputTemplate

  private var state = ControllerState.neutral
  private var lastRumble = RumbleIntensities.off

  /// Creates a new XUSBDriver.
  /// - Parameters:
  ///   - outEndpoint: Interrupt OUT endpoint address (default 0x01).
  ///   - isWirelessReceiver: Whether reports use the Xbox 360 receiver envelope.
  ///   - tuning: The effective tuning of the controller's record; the description's defaults
  ///     when nil.
  ///   - rumbleTemplate: The record's rumble template; the description's for the variant when
  ///     nil.
  public init(
    outEndpoint: UInt8 = 0x01,
    isWirelessReceiver: Bool = false,
    tuning: ControllerTuning? = nil,
    usbStartupWrites: [USBStartupWrite] = [],
    rumbleTemplate: RumbleOutputTemplate? = nil
  ) {
    self.outEndpoint = outEndpoint
    recordStartup = usbStartupWrites
    self.rumbleTemplate = PhysicalProtocolID.xboxXUSB.describedRumbleTemplate(
      variant: isWirelessReceiver ? .receiver : .wired,
      record: rumbleTemplate
    )
    self.isWirelessReceiver = isWirelessReceiver
    usbTimeoutMilliseconds = PhysicalProtocolID.xboxXUSB.described(
      \.usbTransferTimeoutMilliseconds,
      in: tuning
    )
  }

  /// Creates the driver for one Xbox 360 wireless receiver slot, or nil outside slots 0–3.
  /// - Parameters:
  ///   - outEndpoint: Interrupt OUT endpoint address (default 0x01).
  ///   - slotOrdinal: Zero-based receiver slot in interface order.
  public convenience init?(
    outEndpoint: UInt8 = 0x01,
    slotOrdinal: Int,
    tuning: ControllerTuning? = nil,
    usbStartupWrites: [USBStartupWrite] = [],
    rumbleTemplate: RumbleOutputTemplate? = nil
  ) {
    guard (0..<4).contains(slotOrdinal) else { return nil }
    self.init(
      outEndpoint: outEndpoint,
      isWirelessReceiver: true,
      tuning: tuning,
      usbStartupWrites: usbStartupWrites,
      rumbleTemplate: rumbleTemplate
    )
  }

  public var capabilities: ControllerCapabilities {
    PhysicalProtocolID.xboxXUSB.describedControls
  }

  public var sessionPlan: DriverSessionPlan {
    DriverSessionPlan(
      requiresInputConnectionBeforeOutput: isWirelessReceiver,
      assignsStartupPlayerIndicator: true
    ).withRumbleResend(of: rumbleTemplate)
  }

  /// The last rumble again while a motor runs, when the template names a resend interval. A
  /// receiver sends it only while its controller is connected.
  public func keepAliveWrites() -> [PhysicalOutputWrite] {
    guard !isWirelessReceiver || receiverConnected,
      let intensities = rumbleTemplate.resendIntensities(after: lastRumble)
    else { return [] }
    return [.usb(outputPacket(rumbleTemplate.reportBytes(intensities)))]
  }

  public func consumeInputConnectionStateChange() -> ControllerInputConnectionState? {
    defer { pendingConnectionState = nil }
    return pendingConnectionState
  }

  // MARK: - PhysicalProtocolDriver

  /// A wired Xbox 360 starts input without a handshake and sends no startup output. The manager
  /// assigns every wired pad and receiver slot its ring LED from one pool of free player slots,
  /// so two pads never both show player 1 (xpad numbers pads from one global `pad_nr` pool).
  /// A receiver slot asks for presence so a controller already paired before the interface
  /// opened reports itself (xpad.c:1845–1864). Either device that rejects its write still
  /// starts: xpad fails start only when it cannot submit the write (xpad.c:1473).
  public func startupWrites() -> [PhysicalOutputWrite] {
    presenceInquiryWrites
  }

  /// A new transport session learns receiver presence again from the device; the pipeline drops
  /// its own connection state with the old session.
  public func resetProtocolState() {
    state = .neutral
    lastRumble = .off
    guard isWirelessReceiver else { return }
    receiverConnected = false
    pendingConnectionState = nil
  }

  public func drainPendingWrites() -> [PhysicalOutputWrite] { [] }

  /// Parses either a wired report or an Xbox 360 wireless receiver envelope.
  public func parse(report data: Data, receivedAt: MonotonicTimestamp) throws -> ControllerEvent? {
    guard let state = decode(data) else { return nil }
    return ControllerEvent(timestamp: receivedAt, state: state)
  }

  /// The state after one report, or nil when the report carries no pad input.
  func decode(_ data: Data) -> ControllerState? {
    guard isWirelessReceiver else { return decodeWired(data) }
    guard data.count >= 2 else { return nil }

    let reportsPresence = data[0] & 0x08 != 0
    if reportsPresence { updateReceiverConnection(isConnected: data[1] & 0x80 != 0) }
    guard data[1] == 0x01, data.count >= 18, data[4] == xbox360InputReportType else {
      return nil
    }
    updateReceiverConnection(isConnected: true)
    return decodeState(Array(data.dropFirst(4)))
  }

  /// The presence inquiry: the description's startup write for a receiver slot (xpad.c:1449–1469).
  private var presenceInquiryWrites: [PhysicalOutputWrite] {
    PhysicalProtocolID.xboxXUSB.usbStartupWrites(
      recordWrites: recordStartup,
      variant: isWirelessReceiver ? .receiver : .wired,
      parameters: .none
    ).map {
      $0.write(defaultEndpoint: outEndpoint, defaultTimeoutMilliseconds: usbTimeoutMilliseconds)
    }
  }

  /// Decodes one wired-format Xbox 360 state report.
  private func decodeWired(_ data: Data) -> ControllerState? {
    guard !data.isEmpty, data[0] == xbox360InputReportType else { return nil }
    guard data.count >= xbox360InputReportLength, data[1] == xbox360InputReportLengthByte else {
      return nil
    }
    return decodeState(Array(data))
  }

  private func decodeState(_ bytes: [UInt8]) -> ControllerState {
    let buttons = UInt16(bytes[2]) | (UInt16(bytes[3]) << 8)
    let lsx = Int16(bitPattern: UInt16(bytes[6]) | (UInt16(bytes[7]) << 8))
    let lsy = Int16(bitPattern: UInt16(bytes[8]) | (UInt16(bytes[9]) << 8))
    let rsx = Int16(bitPattern: UInt16(bytes[10]) | (UInt16(bytes[11]) << 8))
    let rsy = Int16(bitPattern: UInt16(bytes[12]) | (UInt16(bytes[13]) << 8))

    var next = state
    for (bit, control) in Self.buttonTable { next.set(control, pressed: buttons & (1 << bit) != 0) }
    next.hat = mapDpad(buttons & 0x000F)
    next.leftTrigger = UnipolarValue(normalized: Float(bytes[4]) / xbox360TriggerMax)
    next.rightTrigger = UnipolarValue(normalized: Float(bytes[5]) / xbox360TriggerMax)
    next.leftStick = StickPosition(x: normalizeStick(lsx), y: -normalizeStick(lsy))
    next.rightStick = StickPosition(x: normalizeStick(rsx), y: -normalizeStick(rsy))
    state = next
    return next
  }

  /// Button bits (xpad xbox360_process_packet) and the standard-label controls they report.
  private static let buttonTable: [(UInt16, Control)] = [
    (4, .start), (5, .back), (6, .leftStickClick), (7, .rightStickClick), (8, .leftShoulder),
    (9, .rightShoulder), (10, .guide), (12, .south), (13, .east), (14, .west),
    (15, .north),
  ]

  // MARK: - Output

  public var outputCapabilities: PhysicalControllerOutputCapabilities {
    PhysicalControllerOutputCapabilities(
      rumbleMotors: rumbleTemplate.outputCapabilities.rumbleMotors,
      lightingFeatures: [.playerIndicator]
    )
  }

  public var defaultColor: ControllerColor? { nil }

  public func encode(
    _ command: ControllerOutputCommand
  ) throws(ControllerOutputError) -> PhysicalOutputPlan {
    let packet: PhysicalUSBOutputPacket
    switch command {
    case .setRumble(let intensities, _):
      lastRumble = intensities
      packet = outputPacket(rumbleTemplate.reportBytes(intensities))
    case .stopRumble:
      lastRumble = .off
      packet = outputPacket(rumbleTemplate.reportBytes(.off))
    case .setPlayerIndicator(let indicator):
      packet = ledOutputPacket(pattern: Self.ledPattern(for: indicator))
    default: throw .unsupportedCapability(command.capability)
    }
    return PhysicalOutputPlan(writes: [.usb(packet)])
  }

  func ledPacket(pattern: Xbox360LEDPattern) -> [UInt8] {
    isWirelessReceiver ? wirelessLEDPacket(pattern: pattern) : [0x01, 0x03, pattern.rawValue]
  }

  private func wirelessLEDPacket(pattern: Xbox360LEDPattern) -> [UInt8] {
    [0x00, 0x00, 0x08, 0x40 + pattern.rawValue, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
  }

  private func updateReceiverConnection(isConnected: Bool) {
    guard receiverConnected != isConnected else { return }
    receiverConnected = isConnected
    pendingConnectionState = isConnected ? .connected : .disconnected
    if !isConnected {
      state = .neutral
      lastRumble = .off
    }
  }

  static func ledPattern(for indicator: PhysicalPlayerIndicator) -> Xbox360LEDPattern {
    switch indicator {
    case .off: .allOff
    case .player1: .player1On
    case .player2: .player2On
    case .player3: .player3On
    case .player4: .player4On
    }
  }

  private func ledOutputPacket(pattern: Xbox360LEDPattern) -> PhysicalUSBOutputPacket {
    outputPacket(ledPacket(pattern: pattern))
  }

  private func outputPacket(_ bytes: [UInt8]) -> PhysicalUSBOutputPacket {
    PhysicalUSBOutputPacket(
      endpoint: outEndpoint,
      bytes: bytes,
      timeoutMilliseconds: UInt32(usbTimeoutMilliseconds)
    )
  }

  // MARK: - Private parsing

  private func normalizeStick(_ raw: Int16) -> Float {
    if raw == Int16.min { return -1.0 }
    return Float(raw) / xbox360StickMax
  }

  private func mapDpad(_ value: UInt16) -> HatDirection {
    // bits: up=1, down=2, left=4, right=8
    switch value {
    case 1: .north
    case 2: .south
    case 4: .west
    case 8: .east
    case 9: .northEast  // up + right
    case 5: .northWest  // up + left
    case 10: .southEast  // down + right
    case 6: .southWest  // down + left
    default: .neutral
    }
  }
}
