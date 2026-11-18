public import Foundation

extension GameSirDriver {

  // Share is emitted but stays undeclared until per-model evidence confirms it.
  /// Keep-alives run on the USB and HID channels of the wired G7 Pro, and on the HID channel
  /// otherwise.
  public var sessionPlan: DriverSessionPlan {
    // The driver names the channels it keeps alive; the description's
    // `defaults.session.keepAlive` holds the interval.
    DriverSessionPlan(
      keepAliveChannels: gameSirProtocol == .g7ProUSB ? [.usb, .hid] : [.hid]
    ).withDefaults(of: .vendorGameSir)
  }

  /// Always nil: a GameSir controller reports no logical connection change.
  public func consumeInputConnectionStateChange() -> ControllerInputConnectionState? { nil }

  /// The controls of the description, with the inner grips added where the model has them.
  public var capabilities: ControllerCapabilities {
    // The wired G7 Pro telemetry always reports the inner grips.
    let innerGrips: Set<Control> =
      gameSirProtocol == .g7ProUSB || hasInnerGrips ? [.leftPaddle2, .rightPaddle2] : []
    // No motion: no source verifies the IMU scale, frame, or byte order.
    return PhysicalProtocolID.vendorGameSir.describedControls.union(
      ControllerCapabilities(controls: innerGrips)
    )
  }

  /// The battery and charging state of the latest telemetry; nil until a report carries one.
  public var power: ControllerConnectionState.Power? {
    storedPower

  }

  /// Decodes a wired G7 Pro or an enhanced HID report; nil for a report that carries no input.
  public func parse(report data: Data, receivedAt: MonotonicTimestamp) -> ControllerEvent? {
    let bytes = [UInt8](data)

    switch gameSirProtocol {
    case .g7ProUSB:
      if bytes.count == 20, bytes.prefix(2) == [0x00, 0x14] {
        sessionReady = true
        guard let standard = standardParser.decode(data) else { return nil }
        state.apply(changesFrom: standardState, to: standard)
        standardState = standard
        return ControllerEvent(timestamp: receivedAt, state: state)
      }
      return parseG7Telemetry(bytes, receivedAt: receivedAt)
    case .enhancedHID: return parseEnhanced(bytes, receivedAt: receivedAt)
    }
  }

  /// Clears the state of the session: both parsers, the sequence number, the readiness and the
  /// lighting state.
  public func resetProtocolState() {
    standardParser = XUSBDriver()
    state = .neutral
    standardState = .neutral
    telemetryExtras = .neutral
    sequence = 0
    sessionReady = false
    activeLightingSlot = nil
    lightingBrightness = 100
    storedPower = nil
  }

  /// The description's keep-alive for this variant: the enhanced HID heartbeat report, or the wired
  /// G7 packet with its running sequence number.
  public func keepAliveWrites() -> [PhysicalOutputWrite] {
    let variant: PhysicalProtocolVariantID = gameSirProtocol == .g7ProUSB ? .usb : .enhancedHID
    return PhysicalProtocolID.vendorGameSir.keepAliveWrites(variant: variant).map { write in
      write.output(
        defaultEndpoint: outEndpoint,
        defaultTimeoutMilliseconds: Int(usbTimeoutMilliseconds)
      ) { [self] _ in
        sequence &+= 1
        return sequence
      }
    }
  }

  /// Rumble on enhanced HID controllers, and brightness everywhere; color only on enhanced HID.
  public var outputCapabilities: PhysicalControllerOutputCapabilities {
    let lighting: [PhysicalLightingFeature] =
      switch gameSirProtocol {
      case .g7ProUSB: [.programmableBrightness]
      case .enhancedHID: [.programmableColor, .programmableBrightness]
      }
    return PhysicalControllerOutputCapabilities(
      rumbleMotors: gameSirProtocol == .enhancedHID
        ? rumbleTemplate.outputCapabilities.rumbleMotors : [],
      lightingFeatures: lighting
    )
  }

  /// The lightbar color a GameSir controller shows before the host sets one: light blue.
  public var defaultColor: ControllerColor? { ControllerColor(red: 0, green: 128, blue: 255) }

  /// Colour and brightness wait for the session and, on slot-based models, the active lighting
  /// slot.
  public func encode(
    _ command: ControllerOutputCommand
  ) throws(ControllerOutputError) -> PhysicalOutputPlan {
    switch command {
    case .setRumble, .stopRumble: return try rumbleTemplate.encode(command)
    case .setRGB(let color):
      guard gameSirProtocol == .enhancedHID else {
        throw .unsupportedCapability(command.capability)
      }
      guard let plan = colorPlan(red: color.red, green: color.green, blue: color.blue) else {
        throw .notReady
      }
      return plan
    case .setLightBrightness(let brightness):
      guard let plan = brightnessPlan(brightness.byte) else { throw .notReady }
      return plan
    default: throw .unsupportedCapability(command.capability)
    }
  }

  /// Nil until the session is ready and, on slot-based models, the active slot is known.
  private func colorPlan(red: UInt8, green: UInt8, blue: UInt8) -> PhysicalOutputPlan? {
    guard sessionReady else { return nil }
    if usesLightingSlots {
      guard let slot = activeLightingSlot, slot <= 4 else { return nil }
      let frame = Self.solidColorFrame(red: red, green: green, blue: blue)
      let record: [UInt8] =
        [0x01, 0x05, 0x14, lightingBrightness] + Array(repeating: frame, count: 8).flatMap { $0 }
      var reports = Self.bareWriteReports(
        bank: 0x20,
        address: 0x0001 + UInt16(slot) * 0x007C,
        data: record
      )
      reports += Self.bareWriteReports(bank: 0x20, address: 0x0000, data: [slot])
      return PhysicalOutputPlan(
        writes: reports.map { .hidOutput($0) },
        intervalNanoseconds: gameSirCommandIntervalNanoseconds
      )
    }
    let (hue, saturation) = Self.hueAndSaturation(red: red, green: green, blue: blue)
    let data = [UInt8(hue >> 8), UInt8(hue & 0xFF), saturation]
    let reports = [0x000C, 0x0010, 0x0014, 0x0018].flatMap {
      Self.bareWriteReports(bank: 0x20, address: UInt16($0), data: data)
    }
    return PhysicalOutputPlan(
      writes: reports.map { .hidOutput($0) },
      intervalNanoseconds: gameSirCommandIntervalNanoseconds
    )
  }

  /// Wired G7 Pro brightness goes to the bound USB endpoint; enhanced HID writes lighting memory
  /// and records the value the next colour record carries.
  ///
  /// Nil, changing nothing, until the session is ready and, on slot-based models, the active slot
  /// is known.
  private func brightnessPlan(_ brightness: UInt8) -> PhysicalOutputPlan? {
    guard sessionReady else { return nil }
    let value = UInt8((Double(brightness) * 100 / Double(UInt8.max)).rounded())
    if gameSirProtocol == .g7ProUSB {
      let packet = PhysicalUSBOutputPacket(
        endpoint: outEndpoint,
        bytes: g7Packet(command: 0x3C, payload: [0x03, 0x20, 0x01, 0xF9, 0x01, value]),
        timeoutMilliseconds: usbTimeoutMilliseconds
      )
      return PhysicalOutputPlan(writes: [.usb(packet)])
    }
    var address: UInt16 = 0x0001
    if usesLightingSlots {
      guard let slot = activeLightingSlot, slot <= 4 else { return nil }
      address = 0x0001 + UInt16(slot) * 0x007C + 3
    }
    lightingBrightness = value
    return PhysicalOutputPlan(
      writes: Self.bareWriteReports(bank: 0x20, address: address, data: [value]).map {
        .hidOutput($0)
      }
    )
  }

  /// Decodes a wired G7 Pro telemetry report; nil when it holds no input.
  private func parseG7Telemetry(
    _ bytes: [UInt8],
    receivedAt: MonotonicTimestamp
  ) -> ControllerEvent? {
    guard bytes.count == gameSirReportLength, bytes[0] == 0x10 else { return nil }
    if bytes[1] == 0x05, bytes[2] == 0x20, bytes[3] == 0, bytes[4] == 0, bytes[5] == 1,
      bytes[6] <= 4
    {
      activeLightingSlot = bytes[6]
      return nil
    }
    guard bytes[3] == 0x3C, bytes[4] == 0xE0 else { return nil }
    sessionReady = true
    updateBattery(percentage: bytes[33], charging: bytes[32] == 1)
    var extras = telemetryExtras
    setExtraButtons(bytes[60], includesInnerGrips: true, in: &extras)
    state.apply(changesFrom: telemetryExtras, to: extras)
    telemetryExtras = extras
    return ControllerEvent(timestamp: receivedAt, state: state)
  }

  /// Decodes an enhanced HID report; nil when it holds no input.
  private func parseEnhanced(_ bytes: [UInt8], receivedAt: MonotonicTimestamp) -> ControllerEvent? {
    guard bytes.count == gameSirReportLength else { return nil }
    if bytes[0] == 0x10, bytes[1] == 0x05, bytes[2] == 0x20, bytes[3] == 0, bytes[4] == 0,
      bytes[5] == 1, bytes[6] <= 4, usesLightingSlots
    {
      activeLightingSlot = bytes[6]
      return nil
    }
    guard bytes[0] == 0x12 else { return nil }
    sessionReady = true
    updateBattery(percentage: bytes[36], charging: bytes[35] & 1 != 0)
    var next = state
    let face = bytes[5]
    let meta = bytes[6]
    for (byte, mask, control) in [
      (face, 0x10, Control.west), (face, 0x20, .south), (face, 0x40, .east),
      (face, 0x80, .north), (meta, 0x01, .leftShoulder), (meta, 0x02, .rightShoulder),
      (meta, 0x10, .back), (meta, 0x20, .start), (meta, 0x40, .leftStickClick),
      (meta, 0x80, .rightStickClick),
    ] as [(UInt8, UInt8, Control)] { next.set(control, pressed: byte & mask != 0) }
    next.hat = Self.dpadDirection(face & 0x0F)
    next.leftStick = StickPosition(x: Self.axis(bytes[1]), y: -Self.axis(bytes[2]))
    next.rightStick = StickPosition(x: Self.axis(bytes[3]), y: -Self.axis(bytes[4]))
    next.leftTrigger = UnipolarValue(normalized: Float(bytes[8]) / 255)
    next.rightTrigger = UnipolarValue(normalized: Float(bytes[9]) / 255)
    setExtraButtons(bytes[60], includesInnerGrips: hasInnerGrips, in: &next)
    state = next
    return ControllerEvent(timestamp: receivedAt, state: next)
  }

  /// GameSir reports an exact percentage; charging implies wired power, its absence says nothing.
  private func updateBattery(percentage: UInt8, charging: Bool) {
    let exact = min(percentage, 100)
    storedPower = ControllerConnectionState.Power(
      charging: charging ? .charging : .discharging,
      battery: BatteryLevel(percentage: exact...exact),
      wiredPower: charging ? true : nil
    )
  }

  /// Applies the extra button byte: Guide, Capture, the back paddles and, where
  /// `includesInnerGrips` is true, the inner grips.
  private func setExtraButtons(
    _ value: UInt8,
    includesInnerGrips: Bool,
    in state: inout ControllerState
  ) {
    var table: [(UInt8, Control)] = [
      (0x01, .guide), (0x02, .capture), (0x08, .leftPaddle1), (0x10, .rightPaddle1),
      (0x20, .auxiliary1),
    ]
    if includesInnerGrips { table += [(0x40, .leftPaddle2), (0x80, .rightPaddle2)] }
    for (mask, control) in table { state.set(control, pressed: value & mask != 0) }
  }

  /// A wired G7 packet with the next sequence number, padded to the report length.
  private func g7Packet(command: UInt8, payload: [UInt8]) -> [UInt8] {
    sequence &+= 1
    return Self.padded([0x0F, 0x00, sequence, command] + payload)
  }

  /// A HID output report with ID `0x0F` carrying `bytes`, padded to the report length.
  private static func hidReport(_ bytes: [UInt8]) -> PhysicalHIDOutputReport {
    PhysicalHIDOutputReport(reportID: 0x0F, bytes: padded(bytes))
  }

  /// The HID reports that write `data` to `address` in memory bank `bank`, 48 bytes at a time.
  private static func bareWriteReports(
    bank: UInt8,
    address: UInt16,
    data: [UInt8]
  ) -> [PhysicalHIDOutputReport] {
    stride(from: 0, to: data.count, by: 48).map { offset in
      let chunk = Array(data[offset..<min(data.count, offset + 48)])
      let currentAddress = address + UInt16(offset)
      return hidReport(
        [
          0x0F, 0x03, bank, UInt8(currentAddress >> 8), UInt8(currentAddress & 0xFF),
          UInt8(chunk.count),
        ] + chunk
      )
    }
  }

  /// `bytes` zero-padded or cut to the report length.
  private static func padded(_ bytes: [UInt8]) -> [UInt8] {
    Array((bytes + Array(repeating: 0, count: gameSirReportLength)).prefix(gameSirReportLength))
  }

  /// The stick axis `value` as -1...1, centered on 128.
  static func axis(_ value: UInt8) -> Float {
    let centered = Float(Int(value) - 128)
    return max(-1, min(1, centered / (centered < 0 ? 128 : 127)))
  }

  /// The hat direction of the D-pad nibble.
  static func dpadDirection(_ value: UInt8) -> HatDirection {
    switch value {
    case 0: .north
    case 1: .northEast
    case 2: .east
    case 3: .southEast
    case 4: .south
    case 5: .southWest
    case 6: .west
    case 7: .northWest
    default: .neutral
    }
  }

  /// The hue in degrees and the saturation in percent of an RGB color.
  static func hueAndSaturation(red: UInt8, green: UInt8, blue: UInt8) -> (UInt16, UInt8) {
    let r = Double(red) / 255
    let g = Double(green) / 255
    let b = Double(blue) / 255
    let maximum = max(r, g, b)
    let minimum = min(r, g, b)
    let delta = maximum - minimum
    let saturation = maximum == 0 ? 0 : UInt8((delta / maximum * 100).rounded())
    guard delta > 0 else { return (0, saturation) }
    let rawHue: Double
    if maximum == r {
      rawHue = 60 * ((g - b) / delta).truncatingRemainder(dividingBy: 6)
    } else if maximum == g {
      rawHue = 60 * ((b - r) / delta + 2)
    } else {
      rawHue = 60 * ((r - g) / delta + 4)
    }
    return (UInt16((rawHue < 0 ? rawHue + 360 : rawHue).rounded()) % 360, saturation)
  }

  /// A lighting frame of five RGB triplets that all hold one color.
  static func solidColorFrame(red: UInt8, green: UInt8, blue: UInt8) -> [UInt8] {
    stride(from: 0, to: 15, by: 3).reduce(into: [UInt8](repeating: 0, count: 15)) {
      result,
      offset in
      result[offset] = red
      result[offset + 1] = green
      result[offset + 2] = blue
    }
  }
}

extension ControllerState {
  /// Applies every field that differs between `old` and `new`: the controls one report stream
  /// changed since its own last decode.
  mutating func apply(changesFrom old: ControllerState, to new: ControllerState) {
    for control in old.pressed.symmetricDifference(new.pressed) {
      set(control, pressed: new.pressed.contains(control))
    }
    if old.hat != new.hat { hat = new.hat }
    if old.leftStick != new.leftStick { leftStick = new.leftStick }
    if old.rightStick != new.rightStick { rightStick = new.rightStick }
    if old.leftTrigger != new.leftTrigger { leftTrigger = new.leftTrigger }
    if old.rightTrigger != new.rightTrigger { rightTrigger = new.rightTrigger }
  }
}
