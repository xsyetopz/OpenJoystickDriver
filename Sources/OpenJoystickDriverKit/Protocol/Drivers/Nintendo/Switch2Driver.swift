import Foundation

/// The report ID of the state report.
private let switch2StateReportID: UInt8 = 0x05
/// The shortest state report that is decoded.
private let switch2StateReportLength = 64
/// SDL `RUMBLE_MAX`: the HD rumble amplitude cap.
private let switch2RumbleMaxAmplitude = 29_000

/// The shape of the Switch 2 controller that the driver decodes.
public enum Switch2ControllerLayout: Sendable {
  /// A Switch 2 Pro Controller.
  case pro
  /// A left Joy-Con 2.
  case leftJoyCon
  /// A right Joy-Con 2.
  case rightJoyCon
  /// An NSO GameCube controller.
  case gameCube

  /// The description's `layout` parameter value for this layout.
  var parameter: ProtocolParameters.Layout {
    switch self {
    case .pro: .pro
    case .leftJoyCon: .joyConLeft
    case .rightJoyCon: .joyConRight
    case .gameCube: .gameCube
    }
  }
}

/// The link a Switch 2 controller runs on.
///
/// Both carry the same input report and command set. Byte 2 of every command names the link: `0x00`
/// USB, `0x01` Bluetooth LE.
public enum Switch2Link: Sendable {
  /// The USB link.
  case usb
  /// The Bluetooth LE link.
  case bluetoothLE

  /// The value of byte 2 of every command on this link.
  var commandTransportByte: UInt8 { self == .usb ? 0x00 : 0x01 }
}

/// One stick axis from flash calibration.
///
/// Zero fields mean no calibration, as in SDL.
struct Switch2AxisCalibration: Equatable {
  /// The raw value at the stick's center.
  var neutral: UInt16 = 0
  /// The raw value at the stick's maximum.
  var max: UInt16 = 0
  /// The raw value at the stick's minimum.
  var min: UInt16 = 0

  /// SDL `MapJoystickAxis`: scales by the side's range around neutral, or maps `0...4096` to
  /// `-1...1` without calibration.
  func normalize(_ raw: UInt16) -> Float {
    guard neutral != 0, min != 0, max != 0 else { return Float(raw) / 2048 - 1 }
    let offset = Float(raw) - Float(neutral)
    return Swift.max(-1, Swift.min(1, offset / Float(offset < 0 ? min : max)))
  }
}

/// The flash calibration of both axes of one stick.
struct Switch2StickCalibration: Equatable {
  /// The calibration of the horizontal axis.
  var x = Switch2AxisCalibration()
  /// The calibration of the vertical axis.
  var y = Switch2AxisCalibration()

  /// SDL `ParseStickCalibration`: three packed 12-bit pairs, neutral then max then min.
  init?(_ bytes: ArraySlice<UInt8>) {
    guard bytes.count >= 9 else { return nil }
    let values = Array(bytes.prefix(9))
    let pairs = stride(from: 0, to: 9, by: 3).map { Switch2Driver.twelveBitPair(values, at: $0) }
    x = Switch2AxisCalibration(neutral: pairs[0].x, max: pairs[1].x, min: pairs[2].x)
    y = Switch2AxisCalibration(neutral: pairs[0].y, max: pairs[1].y, min: pairs[2].y)
  }

  /// Creates a stick calibration without calibration data.
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

  /// The shape of the controller that the driver decodes.
  public let layout: Switch2ControllerLayout
  /// The link the controller runs on.
  public let link: Switch2Link
  /// The state after the latest report.
  private var state = ControllerState.neutral
  /// The calibration of the left stick.
  private var leftStick = Switch2StickCalibration()
  /// The calibration of the right stick.
  private var rightStick = Switch2StickCalibration()
  /// The flash zero point of the left analog trigger.
  private var leftTriggerZero: UInt8 = 0
  /// The flash zero point of the right analog trigger.
  private var rightTriggerZero: UInt8 = 0
  /// The low-frequency rumble amplitude.
  private var rumbleLow: UInt16 = 0
  /// The high-frequency rumble amplitude.
  private var rumbleHigh: UInt16 = 0
  /// The rolling sequence number of the rumble reports.
  private var rumbleSequence: UInt8 = 0
  /// The error accumulator that dithers the GameCube rumble motor.
  private var gameCubeRumbleError = 0
  /// The number of stop packets still to send after rumble ends.
  private var pendingStopPackets = 0

  /// Bulk command timeout (`usbCommandTimeoutMs`).
  let commandTimeoutMilliseconds: UInt32
  /// The record's own startup packets; the description's when empty.
  private let recordStartup: [USBStartupWrite]

  /// The command channel's OUT endpoint, from the description.
  static var commandOutEndpoint: UInt8 {
    PhysicalProtocolID.nintendoSwitch2.descriptionOutputEndpoint
  }

  /// The USB interface that carries commands and replies, from the description.
  ///
  /// Loading refuses a NintendoSwitch2 description without one, so the guard cannot fail.
  static var commandChannel: ProtocolDescription.CommandChannel {
    guard let channel = PhysicalProtocolID.nintendoSwitch2.protocolDescription.commandChannel
    else {
      preconditionFailure("nintendo-switch2.json sets no commandChannel")
    }
    return channel
  }

  /// `tuning` is the effective tuning of the controller's record; the description's defaults
  /// when nil.
  public init(
    layout: Switch2ControllerLayout = .pro,
    link: Switch2Link = .usb,
    tuning: ControllerTuning? = nil,
    usbStartupWrites: [USBStartupWrite] = []
  ) {
    self.layout = layout
    self.link = link
    recordStartup = usbStartupWrites
    commandTimeoutMilliseconds = UInt32(
      PhysicalProtocolID.nintendoSwitch2.described(\.usbCommandTimeoutMilliseconds, in: tuning)
    )
  }

  /// Clears the state, so the next report starts from neutral.
  public func resetProtocolState() { state = .neutral }

  /// The controls of the layout, with digital triggers.
  public var capabilities: ControllerCapabilities {
    let controls: Set<Control>
    switch layout {
    case .pro:
      controls = Control.xboxLayout.subtracting([.leftTrigger, .rightTrigger]).union([
        .leftTrigger, .rightTrigger, .guide, .capture, .auxiliary1, .leftPaddle1,
        .rightPaddle1,
      ])
    case .leftJoyCon:
      controls = [
        .dpadUp, .dpadDown, .dpadLeft, .dpadRight, .leftStickX, .leftStickY, .leftStickClick,
        .leftShoulder, .leftTrigger, .back,
        .capture, .auxiliary3, .auxiliary4,
      ]
    case .rightJoyCon:
      controls = [
        .south, .east, .west, .north, .rightStickX, .rightStickY, .rightStickClick,
        .rightShoulder, .rightTrigger, .start, .guide, .auxiliary1, .auxiliary5, .auxiliary6,
      ]
    case .gameCube:
      controls = Control.xboxLayout.subtracting([.back, .leftStickClick, .rightStickClick]).union(
        [.leftTrigger, .rightTrigger, .guide, .capture, .auxiliary1])
    }
    return ControllerCapabilities(
      controls: controls,
      digitalTriggers: controls.intersection([.leftTrigger, .rightTrigger])
    )
  }

  /// SDL rumbles every model through both amplitudes; the GameCube controller's single motor runs
  /// at the larger of the two.
  public var outputCapabilities: PhysicalControllerOutputCapabilities {
    PhysicalControllerOutputCapabilities(
      rumbleMotors: [.lowFrequency, .highFrequency],
      lightingFeatures: [.playerIndicator]
    )
  }

  /// No default colour: the controller has no light to restore.
  public var defaultColor: ControllerColor? { nil }

  /// SDL reads USB replies of up to `0x50` bytes in 64-byte chunks, 100 ms each.
  ///
  /// A BLE reply waits for a connection interval, so its read timeout is longer. The description's
  /// command channel sets both. SDL `RUMBLE_INTERVAL`: the description's keep-alive interval is the
  /// period the rumble packet is re-sent while any motor runs.
  public var sessionPlan: DriverSessionPlan {
    let channel = Self.commandChannel
    return DriverSessionPlan(
      keepAliveChannels: [.hid],
      usbCommandChannel: USBCommandChannel(
        interfaceNumber: channel.interface,
        outEndpoint: Self.commandOutEndpoint,
        inEndpoint: channel.inEndpoint,
        replyLength: channel.replyLength,
        replyTimeoutMilliseconds: link == .usb
          ? channel.usbReplyTimeoutMilliseconds : channel.bluetoothLEReplyTimeoutMilliseconds
      )
    ).withKeepAlive(of: .nintendoSwitch2)
  }

  /// Always nil: the state report carries no logical connection.
  public func consumeInputConnectionStateChange() -> ControllerInputConnectionState? { nil }

  /// SDL `HIDAPI_DriverSwitch2_InitUSB`: flash reads for the stick and trigger calibration, then
  /// the init sequence.
  ///
  /// The last packet starts the input reports. The packets are the description's startup writes for
  /// this link and layout; the driver stamps each one's link byte.
  ///
  /// Over BLE the console sends the first five of the init packets, ending with the feature
  /// enable (ndeadly's captures and joycon2cpp's replay). The rest are the NFC, charging-grip,
  /// and USB input-selection commands, which a BLE link does not use.
  public func startupWrites() -> [PhysicalOutputWrite] {
    let linkByte = link.commandTransportByte
    let session: ([UInt8]) -> UInt8 = { _ in linkByte }
    return PhysicalProtocolID.nintendoSwitch2.usbStartupWrites(
      recordWrites: recordStartup,
      variant: link == .usb ? .usb : .bluetoothLE,
      parameters: ProtocolParameters(layout: layout.parameter)
    ).map { write in
      write.write(
        defaultEndpoint: Self.commandOutEndpoint,
        defaultTimeoutMilliseconds: Int(commandTimeoutMilliseconds),
        session: session
      )
    }
  }

  /// Sets the link byte, so one packet table serves both links.
  func command(_ packet: [UInt8]) -> PhysicalOutputWrite {
    var bytes = packet
    bytes[2] = link.commandTransportByte
    return .usb(
      PhysicalUSBOutputPacket(
        endpoint: Self.commandOutEndpoint,
        bytes: bytes,
        timeoutMilliseconds: commandTimeoutMilliseconds
      )
    )
  }

  /// A flash read reply: command `0x02` response, subcommand `0x01`, then the read length, the
  /// address, and the 64 data bytes from offset 16.
  ///
  /// Replies to other commands are ignored.
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

  /// Encodes a rumble or player indicator command; any other command is rejected as unsupported.
  public func encode(
    _ command: ControllerOutputCommand
  ) throws(ControllerOutputError) -> PhysicalOutputPlan {
    switch command {
    case .setRumble(let intensities, _):
      (rumbleLow, rumbleHigh) = (
        intensities.lowFrequency.rawValue, intensities.highFrequency.rawValue
      )
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
    pendingStopPackets =
      rumbleLow == 0 && rumbleHigh == 0
      ? PhysicalProtocolID.nintendoSwitch2.described(limit: \.trailingStopPackets) : 0
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

  /// SDL `UpdateRumble`.
  ///
  /// Joy-Con reports use ID 1 and the Pro Controller ID 2, with its second actuator's copy at
  /// `0x11`. The GameCube controller's ID 3 report carries on (1), off (0), or stop (2), dithered
  /// by an error accumulator.
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

  /// Decodes a `0x05` state report of at least 64 bytes; any other report is ignored.
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
  private var buttonTable: [(UInt32, Control)] {
    switch layout {
    case .pro: Self.proButtons
    case .leftJoyCon: Self.leftJoyConButtons
    case .rightJoyCon: Self.rightJoyConButtons
    case .gameCube: Self.gameCubeButtons
    }
  }

  /// The button masks shared by the face buttons.
  private static let faceButtons: [(UInt32, Control)] = [
    (0x0000_0001, .west), (0x0000_0002, .north), (0x0000_0004, .south),
    (0x0000_0008, .east),
  ]
  /// The button masks of a Pro Controller.
  private static let proButtons: [(UInt32, Control)] =
    faceButtons + [
      (0x0000_0040, .rightShoulder), (0x0000_0080, .rightTrigger), (0x0000_0100, .back),
      (0x0000_0200, .start), (0x0000_0400, .rightStickClick), (0x0000_0800, .leftStickClick),
      (0x0000_1000, .guide), (0x0000_2000, .capture), (0x0000_4000, .auxiliary1),
      (0x0040_0000, .leftShoulder), (0x0080_0000, .leftTrigger), (0x0100_0000, .rightPaddle1),
      (0x0200_0000, .leftPaddle1),
    ]
  /// SL and SR (byte 7 bits `0x20` and `0x10`) join the half layout as in ``Switch1Driver``.
  private static let leftJoyConButtons: [(UInt32, Control)] = [
    (0x0000_0100, .back), (0x0000_0800, .leftStickClick), (0x0000_2000, .capture),
    (0x0010_0000, .auxiliary4), (0x0020_0000, .auxiliary3), (0x0040_0000, .leftShoulder),
    (0x0080_0000, .leftTrigger),
  ]
  /// The button masks of a right Joy-Con 2.
  private static let rightJoyConButtons: [(UInt32, Control)] =
    faceButtons + [
      (0x0000_0010, .auxiliary6), (0x0000_0020, .auxiliary5), (0x0000_0040, .rightShoulder),
      (0x0000_0080, .rightTrigger), (0x0000_0200, .start), (0x0000_0400, .rightStickClick),
      (0x0000_1000, .guide), (0x0000_4000, .auxiliary1),
    ]
  /// SDL `HandleGameCubeState`: `0x40` is the full-pull trigger click and `0x80` the shoulder
  /// (Z on the right, ZL on the left).
  private static let gameCubeButtons: [(UInt32, Control)] =
    faceButtons + [
      (0x0000_0040, .rightTrigger), (0x0000_0080, .rightShoulder), (0x0000_0200, .start),
      (0x0000_1000, .guide), (0x0000_2000, .capture), (0x0000_4000, .auxiliary1),
      (0x0040_0000, .leftTrigger), (0x0080_0000, .leftShoulder),
    ]

  /// Reads the stick at `offset` and normalizes it with `calibration`; the vertical axis is
  /// inverted.
  private func stick(
    _ bytes: [UInt8],
    at offset: Int,
    _ calibration: Switch2StickCalibration
  ) -> StickPosition {
    let raw = Self.twelveBitPair(bytes, at: offset)
    return StickPosition(x: calibration.x.normalize(raw.x), y: -calibration.y.normalize(raw.y))
  }

  /// SDL `MapTriggerAxis`: the analog value scaled from the flash zero point to 232.
  private static func trigger(_ value: UInt8, zero: UInt8) -> UnipolarValue {
    UnipolarValue(normalized: (Float(value) - Float(zero)) / (232 - Float(zero)))
  }

  /// Reads two packed 12-bit values at `offset`.
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
