import Foundation

private let switch2StateReportID: UInt8 = 0x05
private let switch2StateReportLength = 64
private let switch2CommandOutEndpoint: UInt8 = 0x02
private let switch2CommandTimeoutMilliseconds: UInt32 = 1000
/// SDL `RUMBLE_INTERVAL`: the rumble packet is re-sent at this period while any motor runs.
let switch2RumbleIntervalNanoseconds: UInt64 = 12_000_000
/// SDL `RUMBLE_MAX`: the HD rumble amplitude cap.
private let switch2RumbleMaxAmplitude = 29_000
/// Zero-amplitude packets sent by the rumble refresh after a stop. A refresh built before the stop
/// can still arrive after it, and the next one must stop the motors again.
private let switch2TrailingStopPackets = 2

public enum Switch2ControllerLayout: Sendable {
  case pro
  case leftJoyCon
  case rightJoyCon
  case gameCube
}

/// The link a Switch 2 controller runs on. Both carry the same input report and command set.
/// Byte 2 of every command names the link: `0x00` USB, `0x01` Bluetooth LE.
public enum Switch2Link: Sendable {
  case usb
  case bluetoothLE

  var commandTransportByte: UInt8 { self == .usb ? 0x00 : 0x01 }
}

/// One stick axis from flash calibration. Zero fields mean no calibration, as in SDL.
struct Switch2AxisCalibration: Equatable {
  var neutral: UInt16 = 0
  var max: UInt16 = 0
  var min: UInt16 = 0

  /// SDL `MapJoystickAxis`: scales by the side's range around neutral, or maps `0...4096` to
  /// `-1...1` without calibration.
  func normalize(_ raw: UInt16) -> Float {
    guard neutral != 0, min != 0, max != 0 else { return Float(raw) / 2048 - 1 }
    let offset = Float(raw) - Float(neutral)
    return Swift.max(-1, Swift.min(1, offset / Float(offset < 0 ? min : max)))
  }
}

struct Switch2StickCalibration: Equatable {
  var x = Switch2AxisCalibration()
  var y = Switch2AxisCalibration()

  /// SDL `ParseStickCalibration`: three packed 12-bit pairs, neutral then max then min.
  init?(_ bytes: ArraySlice<UInt8>) {
    guard bytes.count >= 9 else { return nil }
    let values = Array(bytes.prefix(9))
    let pairs = stride(from: 0, to: 9, by: 3).map { Switch2Driver.twelveBitPair(values, at: $0) }
    x = Switch2AxisCalibration(neutral: pairs[0].x, max: pairs[1].x, min: pairs[2].x)
    y = Switch2AxisCalibration(neutral: pairs[0].y, max: pairs[1].y, min: pairs[2].y)
  }

  init() {}
}

/// Driver for the Switch 2 Pro Controller, Joy-Con 2, and NSO GameCube controller.
///
/// USB source: SDL `src/joystick/hidapi/SDL_hidapi_switch2.c`. Interface 0 is HID and carries the
/// 64-byte input report `0x05` and the rumble output reports. Interface 1 is a vendor bulk command
/// channel. The controller sends no input until the bulk init sequence runs, so startup reads the
/// stick calibration from flash and then sends SDL's init packets on that channel. A solo Joy-Con
/// uses the vertical half layout of ``Switch1Driver``. The IMU is not decoded.
///
/// Bluetooth LE source: ndeadly's `switch2_controller_research` and the joycon2cpp demo. SDL has
/// no Switch 2 BLE driver. The GATT link carries the same report and command bytes, so
/// ``Switch2BluetoothLEHub`` presents it as the HID and command-channel transports.
public final class Switch2Driver: PhysicalProtocolDriver {

  public let layout: Switch2ControllerLayout
  public let link: Switch2Link
  private var state = ControllerState.neutral
  private var leftStick = Switch2StickCalibration()
  private var rightStick = Switch2StickCalibration()
  private var leftTriggerZero: UInt8 = 0
  private var rightTriggerZero: UInt8 = 0
  private var rumbleLow: UInt16 = 0
  private var rumbleHigh: UInt16 = 0
  private var rumbleSequence: UInt8 = 0
  private var gameCubeRumbleError = 0
  private var pendingStopPackets = 0

  public init(layout: Switch2ControllerLayout = .pro, link: Switch2Link = .usb) {
    self.layout = layout
    self.link = link
  }

  public func resetProtocolState() { state = .neutral }

  public var capabilities: ControllerCapabilities {
    let controls: Set<ControlID>
    switch layout {
    case .pro:
      controls = ControlID.xboxLayout.subtracting([.leftTrigger, .rightTrigger]).union([
        .leftTriggerButton, .rightTriggerButton, .guide, .capture, .auxiliary1, .paddleLeft1,
        .paddleRight1,
      ])
    case .leftJoyCon:
      controls = [
        .dpad, .leftStickX, .leftStickY, .leftStickClick, .leftShoulder, .leftTriggerButton, .view,
        .capture, .auxiliary3, .auxiliary4,
      ]
    case .rightJoyCon:
      controls = [
        .faceSouth, .faceEast, .faceWest, .faceNorth, .rightStickX, .rightStickY, .rightStickClick,
        .rightShoulder, .rightTriggerButton, .menu, .guide, .auxiliary1, .auxiliary5, .auxiliary6,
      ]
    case .gameCube:
      controls = ControlID.xboxLayout.subtracting([.view, .leftStickClick, .rightStickClick]).union(
        [.leftTriggerButton, .rightTriggerButton, .guide, .capture, .auxiliary1])
    }
    return ControllerCapabilities(controls: controls)
  }

  /// SDL rumbles every model through both amplitudes; the GameCube controller's single motor runs
  /// at the larger of the two.
  public var outputCapabilities: PhysicalControllerOutputCapabilities {
    PhysicalControllerOutputCapabilities(
      rumbleMotors: [.leftMain, .rightMain],
      lightingFeatures: [.playerIndicator]
    )
  }

  public var defaultColor: ControllerColor? { nil }

  /// SDL reads USB replies of up to `0x50` bytes in 64-byte chunks, 100 ms each. A BLE reply
  /// waits for a connection interval, so its read timeout is longer.
  public var sessionPlan: DriverSessionPlan {
    DriverSessionPlan(
      hidKeepAliveIntervalNanoseconds: switch2RumbleIntervalNanoseconds,
      usbCommandChannel: USBCommandChannel(
        interfaceNumber: 1,
        outEndpoint: switch2CommandOutEndpoint,
        inEndpoint: 0x82,
        replyLength: 0x50,
        replyTimeoutMilliseconds: link == .usb ? 100 : 500
      )
    )
  }

  public func consumeInputConnectionStateChange() -> ControllerInputConnectionState? { nil }

  /// SDL `HIDAPI_DriverSwitch2_InitUSB`: flash reads for the stick and trigger calibration, then
  /// the init sequence. The last packet starts the input reports.
  ///
  /// Over BLE the console sends the first five of these packets, ending with the feature enable
  /// (ndeadly's captures and joycon2cpp's replay). The rest are the NFC, charging-grip, and USB
  /// input-selection commands, which a BLE link does not use.
  public func startupWrites() -> [PhysicalOutputWrite] {
    var addresses: [UInt32] = [0x13080, 0x130C0]
    if layout == .gameCube { addresses.append(0x13140) }
    addresses += [0x1FC040, 0x1FC080]
    let flashReads = addresses.map { address in
      [0x02, 0x91, 0x00, 0x01, 0x00, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
        + (0..<4).map { UInt8(truncatingIfNeeded: address >> ($0 * 8)) }
    }
    let sequence = link == .usb ? Self.initSequence : Self.bluetoothLEInitSequence
    return (flashReads + sequence).map(command)
  }

  static let bluetoothLEInitSequence = Array(initSequence.prefix(5))

  /// Payload lengths match byte 5, as SDL sends `pkt[5] + 8` bytes.
  static let initSequence: [[UInt8]] = [
    [0x07, 0x91, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00],
    [0x0C, 0x91, 0x00, 0x02, 0x00, 0x04, 0x00, 0x00, 0x27, 0x00, 0x00, 0x00],
    [0x11, 0x91, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00],
    [
      0x0A, 0x91, 0x00, 0x08, 0x00, 0x14, 0x00, 0x00, 0x01, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
      0xFF, 0xFF, 0x35, 0x00, 0x46, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    ], [0x0C, 0x91, 0x00, 0x04, 0x00, 0x04, 0x00, 0x00, 0x27, 0x00, 0x00, 0x00],
    [0x01, 0x91, 0x00, 0x0C, 0x00, 0x00, 0x00, 0x00],
    [0x01, 0x91, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00],
    [0x08, 0x91, 0x00, 0x02, 0x00, 0x04, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00],
    [0x03, 0x91, 0x00, 0x0A, 0x00, 0x04, 0x00, 0x00, 0x05, 0x00, 0x00, 0x00],
    [
      0x03, 0x91, 0x00, 0x0D, 0x00, 0x08, 0x00, 0x00, 0x01, 0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
      0xFF,
    ],
  ]

  /// Sets the link byte, so one packet table serves both links.
  func command(_ packet: [UInt8]) -> PhysicalOutputWrite {
    var bytes = packet
    bytes[2] = link.commandTransportByte
    return .usb(
      PhysicalUSBOutputPacket(
        endpoint: switch2CommandOutEndpoint,
        bytes: bytes,
        timeoutMilliseconds: switch2CommandTimeoutMilliseconds
      )
    )
  }

  /// A flash read reply: command `0x02` response, subcommand `0x01`, then the read length, the
  /// address, and the 64 data bytes from offset 16. Replies to other commands are ignored.
  public func consumeUSBCommandReply(_ bytes: [UInt8]) {
    guard bytes.count >= 0x50, bytes[0] == 0x02, bytes[1] == 0x01, bytes[3] == 0x01 else { return }
    let address = (0..<4).reduce(UInt32(0)) { $0 | (UInt32(bytes[12 + $1]) << ($1 * 8)) }
    let data = bytes[16..<0x50]
    let userCalibrationValid = data[16] == 0xB2 && data[17] == 0xA1
    switch address {
    case 0x13080: leftStick = Switch2StickCalibration(data.dropFirst(0x28)) ?? leftStick
    case 0x130C0: rightStick = Switch2StickCalibration(data.dropFirst(0x28)) ?? rightStick
    case 0x13140: (leftTriggerZero, rightTriggerZero) = (data[16], data[17])
    case 0x1FC040 where userCalibrationValid:
      leftStick = Switch2StickCalibration(data.dropFirst(2)) ?? leftStick
    case 0x1FC080 where userCalibrationValid:
      rightStick = Switch2StickCalibration(data.dropFirst(2)) ?? rightStick
    default: break
    }
  }

  public func encode(
    _ command: ControllerOutputCommand
  ) throws(ControllerOutputError) -> PhysicalOutputPlan {
    switch command {
    case .setRumble(let intensities, _):
      (rumbleLow, rumbleHigh) = (intensities.leftMain.rawValue, intensities.rightMain.rawValue)
    case .stopRumble: (rumbleLow, rumbleHigh) = (0, 0)
    case .setPlayerIndicator(let indicator):
      // SDL `UpdateSlotLED` patterns for the first four players.
      let patterns: [PhysicalPlayerIndicator: UInt8] = [
        .off: 0x00, .player1: 0x01, .player2: 0x03, .player3: 0x07, .player4: 0x0F,
      ]
      let led: [UInt8] = [0x09, 0x91, 0x00, 0x07, 0x00, 0x08, 0x00, 0x00, patterns[indicator] ?? 0]
      return PhysicalOutputPlan(writes: [self.command(led + [UInt8](repeating: 0, count: 7))])
    default: throw .unsupportedCapability(command.capability)
    }
    pendingStopPackets = rumbleLow == 0 && rumbleHigh == 0 ? switch2TrailingStopPackets : 0
    return PhysicalOutputPlan(writes: [.hidOutput(rumbleReport())])
  }

  /// SDL re-sends the rumble packet every 12 ms while a motor runs, and the GameCube motor's
  /// on/off dithering needs each packet.
  public func keepAliveWrites() -> [PhysicalOutputWrite] {
    if rumbleLow == 0, rumbleHigh == 0 {
      guard pendingStopPackets > 0 else { return [] }
      pendingStopPackets -= 1
    }
    return [.hidOutput(rumbleReport())]
  }

  /// SDL `UpdateRumble`. Joy-Con reports use ID 1 and the Pro Controller ID 2, with its second
  /// actuator's copy at `0x11`. The GameCube controller's ID 3 report carries on (1), off (0), or
  /// stop (2), dithered by an error accumulator.
  private func rumbleReport() -> PhysicalHIDOutputReport {
    var bytes = [UInt8](repeating: 0, count: 64)
    bytes[1] = 0x50 | (rumbleSequence & 0x0F)
    rumbleSequence &+= 1
    switch layout {
    case .gameCube:
      bytes[0] = 0x03
      let amplitude = Int(Swift.max(rumbleLow, rumbleHigh))
      if amplitude == 0 {
        bytes[2] = 2
        gameCubeRumbleError = 0
      } else if gameCubeRumbleError < amplitude {
        bytes[2] = 1
        gameCubeRumbleError += Int(UInt16.max) - amplitude
      } else {
        bytes[2] = 0
        gameCubeRumbleError -= amplitude
      }
    case .pro, .leftJoyCon, .rightJoyCon:
      bytes[0] = layout == .pro ? 0x02 : 0x01
      let scale = { (value: UInt16) in UInt16(Int(value) * switch2RumbleMaxAmplitude / 65_535) }
      let encoded = Self.hdRumble(
        highFrequency: 0x187,
        highAmplitude: scale(rumbleHigh),
        lowFrequency: 0x112,
        lowAmplitude: scale(rumbleLow)
      )
      bytes.replaceSubrange(2..<7, with: encoded)
      if layout == .pro { bytes.replaceSubrange(0x11..<0x17, with: bytes[1..<7]) }
    }
    return PhysicalHIDOutputReport(reportID: bytes[0], bytes: bytes)
  }

  /// SDL `EncodeHDRumble`.
  static func hdRumble(
    highFrequency: UInt16,
    highAmplitude: UInt16,
    lowFrequency: UInt16,
    lowAmplitude: UInt16
  ) -> [UInt8] {
    [
      UInt8(truncatingIfNeeded: highFrequency),
      UInt8(truncatingIfNeeded: ((highAmplitude >> 4) & 0xFC) | ((highFrequency >> 8) & 0x03)),
      UInt8(truncatingIfNeeded: (highAmplitude >> 12) | (lowFrequency << 4)),
      UInt8(truncatingIfNeeded: (lowAmplitude & 0xC0) | ((lowFrequency >> 4) & 0x3F)),
      UInt8(truncatingIfNeeded: lowAmplitude >> 8),
    ]
  }

  public func parse(report data: Data, receivedAt: MonotonicTimestamp) throws -> ControllerEvent? {
    let bytes = Array(data)
    guard bytes.count >= switch2StateReportLength, bytes[0] == switch2StateReportID else {
      return nil
    }
    let buttons = (0..<4).reduce(UInt32(0)) { $0 | (UInt32(bytes[5 + $1]) << ($1 * 8)) }
    var next = state
    for (mask, control) in buttonTable { next.set(control, pressed: buttons & mask != 0) }
    if layout != .rightJoyCon {
      next.hat = Self.hat(buttons >> 16)
      next.leftStick = stick(bytes, at: 11, leftStick)
    }
    if layout == .rightJoyCon {
      // SDL reads a solo right Joy-Con's stick with the primary (left) calibration slot.
      next.rightStick = stick(bytes, at: 14, leftStick)
    } else if layout != .leftJoyCon {
      next.rightStick = stick(bytes, at: 14, rightStick)
    }
    if layout == .gameCube {
      next.leftTrigger = Self.trigger(bytes[61], zero: leftTriggerZero)
      next.rightTrigger = Self.trigger(bytes[62], zero: rightTriggerZero)
    }
    state = next
    return ControllerEvent(timestamp: receivedAt, state: next)
  }

  /// SDL `HandleSwitchProState` bits as one word: bytes 5, 6, 7, and 8 from the low byte up.
  private var buttonTable: [(UInt32, ControlID)] {
    switch layout {
    case .pro: Self.proButtons
    case .leftJoyCon: Self.leftJoyConButtons
    case .rightJoyCon: Self.rightJoyConButtons
    case .gameCube: Self.gameCubeButtons
    }
  }

  private static let faceButtons: [(UInt32, ControlID)] = [
    (0x0000_0001, .faceWest), (0x0000_0002, .faceNorth), (0x0000_0004, .faceSouth),
    (0x0000_0008, .faceEast),
  ]
  private static let proButtons: [(UInt32, ControlID)] =
    faceButtons + [
      (0x0000_0040, .rightShoulder), (0x0000_0080, .rightTriggerButton), (0x0000_0100, .view),
      (0x0000_0200, .menu), (0x0000_0400, .rightStickClick), (0x0000_0800, .leftStickClick),
      (0x0000_1000, .guide), (0x0000_2000, .capture), (0x0000_4000, .auxiliary1),
      (0x0040_0000, .leftShoulder), (0x0080_0000, .leftTriggerButton), (0x0100_0000, .paddleRight1),
      (0x0200_0000, .paddleLeft1),
    ]
  /// SL and SR (byte 7 bits `0x20` and `0x10`) join the half layout as in ``Switch1Driver``.
  private static let leftJoyConButtons: [(UInt32, ControlID)] = [
    (0x0000_0100, .view), (0x0000_0800, .leftStickClick), (0x0000_2000, .capture),
    (0x0010_0000, .auxiliary4), (0x0020_0000, .auxiliary3), (0x0040_0000, .leftShoulder),
    (0x0080_0000, .leftTriggerButton),
  ]
  private static let rightJoyConButtons: [(UInt32, ControlID)] =
    faceButtons + [
      (0x0000_0010, .auxiliary6), (0x0000_0020, .auxiliary5), (0x0000_0040, .rightShoulder),
      (0x0000_0080, .rightTriggerButton), (0x0000_0200, .menu), (0x0000_0400, .rightStickClick),
      (0x0000_1000, .guide), (0x0000_4000, .auxiliary1),
    ]
  /// SDL `HandleGameCubeState`: `0x40` is the full-pull trigger click and `0x80` the shoulder
  /// (Z on the right, ZL on the left).
  private static let gameCubeButtons: [(UInt32, ControlID)] =
    faceButtons + [
      (0x0000_0040, .rightTriggerButton), (0x0000_0080, .rightShoulder), (0x0000_0200, .menu),
      (0x0000_1000, .guide), (0x0000_2000, .capture), (0x0000_4000, .auxiliary1),
      (0x0040_0000, .leftTriggerButton), (0x0080_0000, .leftShoulder),
    ]

  private func stick(
    _ bytes: [UInt8],
    at offset: Int,
    _ calibration: Switch2StickCalibration
  ) -> StickPosition {
    let raw = Self.twelveBitPair(bytes, at: offset)
    return StickPosition(x: calibration.x.normalize(raw.x), yDown: -calibration.y.normalize(raw.y))
  }

  /// SDL `MapTriggerAxis`: the analog value scaled from the flash zero point to 232.
  private static func trigger(_ value: UInt8, zero: UInt8) -> UnipolarValue {
    UnipolarValue(normalized: (Float(value) - Float(zero)) / (232 - Float(zero)))
  }

  static func twelveBitPair(_ bytes: [UInt8], at offset: Int) -> (x: UInt16, y: UInt16) {
    let x = UInt16(bytes[offset]) | (UInt16(bytes[offset + 1] & 0x0F) << 8)
    let y = (UInt16(bytes[offset + 1]) >> 4) | (UInt16(bytes[offset + 2]) << 4)
    return (x, y)
  }

  /// Byte 7: down `0x01`, up `0x02`, right `0x04`, left `0x08`.
  private static func hat(_ byte: UInt32) -> HatDirection {
    switch byte & 0x0F {
    case 0x02: .north
    case 0x06: .northEast
    case 0x04: .east
    case 0x05: .southEast
    case 0x01: .south
    case 0x09: .southWest
    case 0x08: .west
    case 0x0A: .northWest
    default: .neutral
    }
  }
}
