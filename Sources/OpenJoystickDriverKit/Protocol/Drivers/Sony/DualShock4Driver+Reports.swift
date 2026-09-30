import Foundation

extension DualShock4Driver {
  public var defaultColor: ControllerColor? { ControllerColor(red: 0, green: 0, blue: 64) }

  public var outputCapabilities: PhysicalControllerOutputCapabilities {
    PhysicalControllerOutputCapabilities(
      rumbleMotors: [.leftMain, .rightMain],
      lightingFeatures: [.programmableColor]
    )
  }

  public var capabilities: ControllerCapabilities {
    ControllerCapabilities(
      controls: ControlID.xboxLayout.union([
        .guide, .touchpadClick, .leftTriggerButton, .rightTriggerButton,
      ]),
      touchContactCount: 2,
      motion: true
    )
  }

  enum ReportOffset {
    static let leftStickX: Int = 0
    static let leftStickY: Int = 1
    static let rightStickX: Int = 2
    static let rightStickY: Int = 3
    static let buttons0: Int = 4
    static let buttons1: Int = 5
    static let buttons2: Int = 6
    static let l2Trigger: Int = 7
    static let r2Trigger: Int = 8
  }

  private var usesBluetoothStartup: Bool { isBluetoothVariant || transport == .bluetooth }

  public func startupFeatureReads() -> [PhysicalHIDFeatureReadRequest] {
    if usesBluetoothStartup { return [PhysicalHIDFeatureReadRequest(reportID: 5, length: 41)] }
    return [PhysicalHIDFeatureReadRequest(reportID: 2, length: 37)]
  }

  public func startupWrites() -> [PhysicalOutputWrite] {
    guard usesBluetoothStartup else { return [] }
    return [.hidOutput(makeOutputReport(validFlags: ds4OutputValidFlagMotor))]
  }

  public func consumeFeatureReply(_ data: Data, request: PhysicalHIDFeatureReadRequest) -> Bool {
    let bluetooth = usesBluetoothStartup
    guard request.length == data.count, data.first == request.reportID else { return false }
    let bytes = Array(data)
    guard bytes.count == (bluetooth ? 41 : 37), request.reportID == (bluetooth ? 5 : 2) else {
      return false
    }

    if bluetooth, !SonyBluetoothCRC32.isValid(seed: 0xA3, report: bytes) { return false }
    guard usesFactoryCalibration else { return true }
    guard
      let calibrated = SonyMotionCalibration.dualShock4Factory(
        bytes,
        bluetooth: bluetooth,
        groupsGyroEndpoints: bluetooth || model == .wirelessAdapter
      )
    else { return false }

    motionCalibration = model.scaled(calibrated).installed(after: motionCalibration)
    return true
  }

  /// Decodes one DS4 HID input report into the full controller state and its samples.
  public func parse(report data: Data, receivedAt: MonotonicTimestamp) throws -> ControllerEvent? {
    let bytes = try reportPayload(from: data)
    guard bytes.count >= 9, acceptsAdapterReport(bytes, receivedAt: receivedAt.nanoseconds) else {
      return nil
    }
    let timestamp = bytes.count >= 11 ? UInt16(bytes[9]) | (UInt16(bytes[10]) << 8) : nil
    let isFresh =
      timestamp.map { current in
        guard let previousSensorTimestamp else { return true }
        let advance = current &- previousSensorTimestamp
        return advance > 0 && advance < 0x8000
      } ?? false
    previousSensorTimestamp = timestamp
    updatePower(from: bytes)

    var next = state
    next.leftStick = StickPosition(x: Self.normalize(bytes[0]), yDown: Self.normalize(bytes[1]))
    next.rightStick = StickPosition(x: Self.normalize(bytes[2]), yDown: Self.normalize(bytes[3]))
    next.leftTrigger = UnipolarValue(normalized: Float(bytes[7]) / ds4TriggerMax)
    next.rightTrigger = UnipolarValue(normalized: Float(bytes[8]) / ds4TriggerMax)
    next.hat = Self.direction(for: bytes[4] & 0x0F)
    for (offset, mask, control) in Self.buttonTable {
      next.set(control, pressed: bytes[offset] & mask != 0)
    }
    let samples = SonySensorSamples.dualShock4(
      bytes,
      bluetooth: transport == .bluetooth,
      receivedAt: receivedAt.nanoseconds,
      clock: &sensorClock,
      calibration: motionCalibration
    )
    next.recordTouch(samples.touch)
    state = next
    return ControllerEvent(
      timestamp: receivedAt,
      state: next,
      motion: samples.motion,
      touchFrames: samples.touch,
      isFresh: isFresh
    )
  }

  /// Payload byte, mask and PlayStation-label control of each button.
  private static let buttonTable: [(Int, UInt8, ControlID)] = [
    (4, 0x10, .faceWest), (4, 0x20, .faceSouth), (4, 0x40, .faceEast), (4, 0x80, .faceNorth),
    (5, 0x01, .leftShoulder), (5, 0x02, .rightShoulder), (5, 0x04, .leftTriggerButton),
    (5, 0x08, .rightTriggerButton), (5, 0x10, .view), (5, 0x20, .menu), (5, 0x40, .leftStickClick),
    (5, 0x80, .rightStickClick), (6, 0x01, .guide), (6, 0x02, .touchpadClick),
  ]

  private static func normalize(_ raw: UInt8) -> Float {
    (Float(raw) - ds4AxisCenter) / ds4AxisCenter
  }

  private static func direction(for hat: UInt8) -> HatDirection {
    switch hat {
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

  public func encode(
    _ command: ControllerOutputCommand
  ) throws(ControllerOutputError) -> PhysicalOutputPlan {
    let report: PhysicalHIDOutputReport
    switch command {
    case .setRumble(let intensities, _):
      report = makeOutputReport(
        validFlags: ds4OutputValidFlagMotor,
        leftMotor: intensities.leftMain.byte,
        rightMotor: intensities.rightMain.byte
      )
    case .stopRumble: report = makeOutputReport(validFlags: ds4OutputValidFlagMotor)
    case .setRGB(let color):
      report = makeOutputReport(
        validFlags: ds4OutputValidFlagColor,
        red: color.red,
        green: color.green,
        blue: color.blue
      )
    default: throw .unsupportedCapability(command.capability)
    }
    return PhysicalOutputPlan(writes: [.hidOutput(report)])
  }

  private func makeOutputReport(
    validFlags: UInt8,
    leftMotor: UInt8 = 0,
    rightMotor: UInt8 = 0,
    red: UInt8 = 0,
    green: UInt8 = 0,
    blue: UInt8 = 0
  ) -> PhysicalHIDOutputReport {
    switch transport {
    case .usb:
      var bytes = [UInt8](repeating: 0, count: ds4USBOutputReportLength)
      bytes[0] = ds4USBOutputReportID
      bytes[1] = validFlags
      bytes[4] = rightMotor
      bytes[5] = leftMotor
      bytes[6] = red
      bytes[7] = green
      bytes[8] = blue
      return PhysicalHIDOutputReport(reportID: ds4USBOutputReportID, bytes: bytes)
    case .bluetooth:
      var bytes = [UInt8](repeating: 0, count: ds4BluetoothOutputReportLength)
      bytes[0] = ds4BluetoothOutputReportID
      bytes[1] = ds4BluetoothOutputHIDAndCRCFlag | ds4BluetoothOutputPollInterval
      bytes[3] = validFlags
      bytes[6] = rightMotor
      bytes[7] = leftMotor
      bytes[8] = red
      bytes[9] = green
      bytes[10] = blue
      SonyBluetoothCRC32.writeTrailer(seed: ds4BluetoothHIDOutputHeader, report: &bytes)
      return PhysicalHIDOutputReport(reportID: ds4BluetoothOutputReportID, bytes: bytes)
    }
  }

  private func reportPayload(from data: Data) throws -> [UInt8] {
    let bytes = Array(data)
    if bytes.first == ds4USBInputReportID, bytes.count == 64 {
      transport = .usb
      latestInputReportFormat = "ds4-usb-0x01"
      return Array(bytes.dropFirst())
    }
    if bytes.first == ds4USBInputReportID, bytes.count == 10 {
      transport = .bluetooth
      latestInputReportFormat = "ds4-bluetooth-minimal-0x01"
      return Array(bytes.dropFirst())
    }
    if bytes.first == ds4BluetoothHIDInputTransaction,
      bytes.dropFirst().first == ds4USBInputReportID, bytes.count == 11
    {
      transport = .bluetooth
      latestInputReportFormat = "ds4-bluetooth-minimal-0x01"
      return Array(bytes.dropFirst(2))
    }
    if bytes.first == ds4BluetoothHIDInputTransaction,
      bytes.dropFirst().first == ds4BluetoothInputReportID, bytes.count == 79
    {
      try validateBluetoothInputCRC(Array(bytes.dropFirst()))
      transport = .bluetooth
      latestInputReportFormat = "ds4-bluetooth-complete-0x11"
      return Array(bytes.dropFirst(4).dropLast(4))
    }
    if bytes.first == ds4BluetoothInputReportID, bytes.count == 78 {
      try validateBluetoothInputCRC(bytes)
      transport = .bluetooth
      latestInputReportFormat = "ds4-bluetooth-complete-0x11"
      return Array(bytes.dropFirst(3).dropLast(4))
    }
    throw DualShock4DriverError.invalidReportFraming
  }

  private func validateBluetoothInputCRC(_ report: [UInt8]) throws {
    guard report.count == 78 else { throw DualShock4DriverError.invalidReportFraming }
    guard SonyBluetoothCRC32.isValid(seed: ds4BluetoothHIDInputTransaction, report: report) else {
      throw DualShock4DriverError.invalidBluetoothCRC
    }
  }

  /// DS4 reports charge in 10% buckets (`0...9`), `10` for full charge, and `11` for a full
  /// battery on wired power.
  private func updatePower(from bytes: [UInt8]) {
    guard bytes.count > 29 else { return }
    let level = bytes[29] & 0x0F
    let wired = bytes[29] & 0x10 != 0
    let bucket = level * 10
    let (charging, percentage): (ControllerConnectionState.Charging, ClosedRange<UInt8>?) =
      switch level {
      case 0...10: (wired ? .charging : .discharging, bucket...min(bucket + 9, 100))
      case 11 where wired: (.full, 100...100)
      default: (.unknown, nil)
      }
    power = ControllerConnectionState.Power(
      charging: charging,
      battery: BatteryLevel(percentage: percentage),
      wiredPower: wired
    )
  }
}
