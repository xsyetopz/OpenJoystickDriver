import Foundation

extension SteamControllerDriver {

  /// The offsets of the fields in the 64-byte report.
  private enum ReportOffset {
    /// The message type.
    static let messageType = 2
    /// The wireless status.
    static let wirelessStatus = 4
    /// The first button byte.
    static let buttons0 = 8
    /// The second button byte.
    static let buttons1 = 9
    /// The third button byte.
    static let buttons2 = 10
    /// The left trigger.
    static let leftTrigger = 11
    /// The right trigger.
    static let rightTrigger = 12
    /// The left stick or left pad X.
    static let leftX = 16
    /// The left stick or left pad Y.
    static let leftY = 18
    /// The right pad X.
    static let rightPadX = 20
    /// The right pad Y.
    static let rightPadY = 22
  }

  /// The controls that the Steam Controller description gives every controller.
  public var capabilities: ControllerCapabilities {
    PhysicalProtocolID.valveSteamController.describedControls
  }

  /// Haptic pulses on both pads and programmable brightness.
  public var outputCapabilities: PhysicalControllerOutputCapabilities {
    PhysicalControllerOutputCapabilities(
      rumbleMotors: [.leftHaptic, .rightHaptic],
      lightingFeatures: [.programmableBrightness]
    )
  }

  /// None: the controller has no default color.
  public var defaultColor: ControllerColor? { nil }

  /// Output waits for a logical controller when the controller is behind a receiver.
  public var sessionPlan: DriverSessionPlan {
    DriverSessionPlan(requiresInputConnectionBeforeOutput: isWirelessReceiver)
  }

  /// Returns and clears the connection change that is pending.
  public func consumeInputConnectionStateChange() -> ControllerInputConnectionState? {
    let state = pendingConnectionStateChange
    pendingConnectionStateChange = nil
    return state
  }

  /// The description's activation reports for the transport.
  ///
  /// Over Bluetooth LE they also select wireless packet version 2, as SDL `ResetSteamController`
  /// does.
  public func activationWrites() -> [PhysicalOutputWrite] {
    PhysicalProtocolID.valveSteamController.protocolDescription.activationWrites(over: transport)
  }

  /// The description's deactivation reports for the transport.
  public func deactivationWrites() -> [PhysicalOutputWrite] {
    PhysicalProtocolID.valveSteamController.protocolDescription.deactivationWrites(over: transport)
  }

  /// The transport the controller is reached over.
  private var transport: PhysicalTransport { isBluetooth ? .bluetoothLE : .usb }

  /// A dongle controller connecting or disconnecting activates or deactivates it.
  public func inputConnectionWrites(
    for state: ControllerInputConnectionState
  ) -> [PhysicalOutputWrite] {
    switch state {
    case .connected: activationWrites()
    case .disconnected: deactivationWrites()
    }
  }

  /// Brightness as a settings feature report.
  ///
  /// Rumble is trackpad haptic pulses as feature reports, none while no logical controller is
  /// connected; a held pulse lasts 65 ms. Stop sends nothing: neither Linux `hid-steam.c` nor SDL
  /// documents a form that ends a running pulse train.
  public func encode(
    _ command: ControllerOutputCommand
  ) throws(ControllerOutputError) -> PhysicalOutputPlan {
    switch command {
    case .setLightBrightness(let brightness):
      let reports = steamFeatureReports([
        steamControllerSetSettingsValuesCommand, 3, steamControllerUserLEDBrightnessSetting,
        brightness.byte, 0,
      ])
      return PhysicalOutputPlan(writes: reports.map { .hidFeature($0) })
    case .setRumble(let intensities, let duration):
      let durationMs =
        switch duration {
        case .milliseconds(let milliseconds): milliseconds
        case .held: 0
        }
      return PhysicalOutputPlan(
        writes: hapticReports(
          left: intensities.leftHaptic.byte,
          right: intensities.rightHaptic.byte,
          durationMs: durationMs
        ).map { .hidFeature($0) }
      )
    case .stopRumble: return try encode(.setRumble(.off, duration: .held))
    default: throw .unsupportedCapability(command.capability)
    }
  }

  /// The pulse reports for a rumble of intensities `left` and `right` that lasts `durationMs`, none
  /// while no logical controller is connected.
  ///
  /// A duration of 0 stands for a held pulse.
  private func hapticReports(
    left: UInt8,
    right: UInt8,
    durationMs: Int
  ) -> [PhysicalHIDOutputReport] {
    guard isLogicalControllerConnected else { return [] }
    let effectiveDurationMs =
      durationMs > 0 ? min(durationMs, maxRumbleDurationMs) : steamControllerHeldPulseMilliseconds
    let totalMicroseconds = max(1, effectiveDurationMs * 1_000)
    let pulseDuration = min(totalMicroseconds, steamControllerMaximumPulseMicroseconds)
    let pulseCount = min(65_535, (totalMicroseconds + pulseDuration - 1) / pulseDuration)
    var reports: [PhysicalHIDOutputReport] = []
    if left > 0 {
      reports +=
        (hapticPulseReports(
          pad: 1,
          intensity: left,
          durationMicroseconds: pulseDuration,
          count: pulseCount
        ))
    }
    if right > 0 {
      reports +=
        (hapticPulseReports(
          pad: 0,
          intensity: right,
          durationMicroseconds: pulseDuration,
          count: pulseCount
        ))
    }
    return reports
  }

  /// The wireless-state query for a receiver; nil otherwise.
  public func presenceRequestWrite() -> PhysicalOutputWrite? {
    guard isWirelessReceiver else { return nil }
    return steamFeatureReports([steamControllerGetWirelessStateCommand]).first.map {
      .hidFeature($0)
    }
  }

  /// Decodes one Steam Controller state report; wireless status messages carry no input.
  public func parse(report data: Data, receivedAt: MonotonicTimestamp) throws -> ControllerEvent? {
    var bytes = Array(data)
    if isBluetooth {
      guard let packet = bluetoothAssembler.append(bytes),
        let wired = bluetoothState.wiredReport(from: packet)
      else { return nil }
      bytes = wired.report
      if let stick = wired.leftStick {
        leftStickRaw = (clampedInt16(stick.x), -clampedInt16(stick.y))
      }
    }
    guard bytes.count == steamControllerReportLength, bytes[0] == steamControllerReportPrefix0,
      bytes[1] == steamControllerReportPrefix1
    else { return nil }

    switch bytes[ReportOffset.messageType] {
    case steamControllerWirelessMessageID:
      parseWirelessStatus(bytes)
      return nil
    case steamControllerStatusMessageID:
      parseWirelessStatusFallback()
      return nil
    case steamControllerStateMessageID:
      guard isLogicalControllerConnected else { return nil }
      var next = decodeControllerState(bytes)
      var motion: [ControllerMotionSample] = []
      var touch: [ControllerTouchSample] = []
      if let sample = motionSamples.decode(bytes, receivedAt: receivedAt.nanoseconds) {
        motion = [sample]
        touch = touchSamples.decode(bytes, timestamp: sample.timestamp.monotonic)
      }
      next.recordTouch(touch)
      state = next
      return ControllerEvent(timestamp: receivedAt, state: next, motion: motion, touchFrames: touch)
    default: return nil
    }
  }

  /// Applies a wireless status message: a connected or disconnected value changes the logical
  /// controller connection and queues the change.
  ///
  /// Other values, and any message on a controller without a receiver, change nothing.
  private func parseWirelessStatus(_ bytes: [UInt8]) {
    guard isWirelessReceiver else { return }
    let nextConnected: Bool
    switch bytes[ReportOffset.wirelessStatus] {
    case steamControllerWirelessDisconnected: nextConnected = false
    case steamControllerWirelessConnected: nextConnected = true
    default: return
    }
    guard nextConnected != isLogicalControllerConnected else { return }
    isLogicalControllerConnected = nextConnected
    pendingConnectionStateChange = nextConnected ? .connected : .disconnected
    resetPreviousReportState()
  }

  /// Marks the logical controller connected when a status message arrives on a receiver that held
  /// it disconnected.
  private func parseWirelessStatusFallback() {
    guard isWirelessReceiver, !isLogicalControllerConnected else { return }
    isLogicalControllerConnected = true
    pendingConnectionStateChange = .connected
    resetPreviousReportState()
  }

  /// The state after the buttons, hat, triggers, sticks and right pad of the state report `bytes`.
  private func decodeControllerState(_ bytes: [UInt8]) -> ControllerState {
    let b1 = bytes[ReportOffset.buttons1]
    let b2 = bytes[ReportOffset.buttons2]
    let lpadTouched = (b2 & 0x08) != 0
    let lpadAndJoy = (b2 & 0x80) != 0
    let lx =
      lpadTouched
      ? (lpadAndJoy ? leftStickRaw.x : 0) : readInt16LE(bytes, offset: ReportOffset.leftX)
    let ly =
      lpadTouched
      ? (lpadAndJoy ? leftStickRaw.y : 0) : clampedNegatedInt16LE(bytes, offset: ReportOffset.leftY)
    leftStickRaw = (lx, ly)
    let rx = readInt16LE(bytes, offset: ReportOffset.rightPadX)
    let ry = clampedNegatedInt16LE(bytes, offset: ReportOffset.rightPadY)

    var next = state
    for (offset, mask, control) in Self.buttonTable {
      next.set(control, pressed: bytes[offset] & mask != 0)
    }
    next.hat = mapDpad(b1 & 0x0F)
    next.leftTrigger = UnipolarValue(
      normalized: Float(bytes[ReportOffset.leftTrigger]) / steamControllerTriggerMax
    )
    next.rightTrigger = UnipolarValue(
      normalized: Float(bytes[ReportOffset.rightTrigger]) / steamControllerTriggerMax
    )
    next.leftStick = StickPosition(x: normalizeAxis(lx), y: normalizeAxis(ly))
    next.rightStick = StickPosition(x: normalizeAxis(rx), y: normalizeAxis(ry))
    return next
  }

  /// Report byte, mask and standard-label control of each button.
  private static let buttonTable: [(Int, UInt8, Control)] = [
    (ReportOffset.buttons0, 0x01, .rightTrigger),
    (ReportOffset.buttons0, 0x02, .leftTrigger),
    (ReportOffset.buttons0, 0x04, .rightShoulder), (ReportOffset.buttons0, 0x08, .leftShoulder),
    (ReportOffset.buttons0, 0x10, .north), (ReportOffset.buttons0, 0x20, .east),
    (ReportOffset.buttons0, 0x40, .west), (ReportOffset.buttons0, 0x80, .south),
    (ReportOffset.buttons1, 0x10, .back), (ReportOffset.buttons1, 0x20, .guide),
    (ReportOffset.buttons1, 0x40, .start), (ReportOffset.buttons1, 0x80, .leftPaddle2),
    (ReportOffset.buttons2, 0x01, .rightPaddle2), (ReportOffset.buttons2, 0x02, .leftTrackpadClick),
    (ReportOffset.buttons2, 0x04, .rightTrackpadClick),
    (ReportOffset.buttons2, 0x40, .leftStickClick),
  ]

  /// The haptic pulse command for `pad` (1 left, 0 right) with a gain that grows with `intensity`.
  private func hapticPulseReports(
    pad: UInt8,
    intensity: UInt8,
    durationMicroseconds: Int,
    count: Int
  ) -> [PhysicalHIDOutputReport] {
    let gainDecibels = -24 + Int((Double(intensity) * 30.0 / 255.0).rounded())
    let gain = UInt8(bitPattern: Int8(clamping: gainDecibels))
    return steamFeatureReports([
      steamControllerHapticPulseCommand, steamControllerHapticPulsePayloadLength, pad,
      UInt8(truncatingIfNeeded: durationMicroseconds),
      UInt8(truncatingIfNeeded: durationMicroseconds >> 8), 0, 0, UInt8(truncatingIfNeeded: count),
      UInt8(truncatingIfNeeded: count >> 8), gain,
    ])
  }

  /// One unnumbered 64-byte report over USB; report-`0x03` segments over Bluetooth LE.
  private func steamFeatureReports(_ command: [UInt8]) -> [PhysicalHIDOutputReport] {
    if isBluetooth { return SteamBluetooth.featureReports(command) }
    var report = [UInt8](repeating: 0, count: steamControllerReportLength)
    for (index, byte) in command.prefix(steamControllerReportLength).enumerated() {
      report[index] = byte
    }
    return [PhysicalHIDOutputReport(reportID: 0, bytes: report)]
  }

  /// Clears the held input, motion time and Bluetooth LE framing.
  private func resetPreviousReportState() {
    motionSamples.reset()
    touchSamples = SteamTouchSamples()
    state = .neutral
    leftStickRaw = (0, 0)
    bluetoothAssembler.reset()
    bluetoothState = SteamBluetoothState()
  }

  /// The little-endian signed 16-bit value at `offset`, with `Int16.min` raised to `-Int16.max`.
  private func readInt16LE(_ bytes: [UInt8], offset: Int) -> Int16 {
    clampedInt16(Int16(bitPattern: UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)))
  }

  /// `value`, with `Int16.min` raised to `-Int16.max` so that it negates safely.
  private func clampedInt16(_ value: Int16) -> Int16 { value == Int16.min ? -Int16.max : value }

  /// The negated little-endian signed 16-bit value at `offset`.
  private func clampedNegatedInt16LE(_ bytes: [UInt8], offset: Int) -> Int16 {
    -readInt16LE(bytes, offset: offset)
  }

  /// `value` as -1...1.
  private func normalizeAxis(_ value: Int16) -> Float {
    let normalized = Float(value) / steamControllerStickMax
    return max(-1, min(1, normalized))
  }

  /// The hat direction of the D-pad bits: up 1, right 2, left 4, down 8.
  private func mapDpad(_ value: UInt8) -> HatDirection {
    let up = (value & 0x01) != 0
    let right = (value & 0x02) != 0
    let left = (value & 0x04) != 0
    let down = (value & 0x08) != 0

    switch (up, right, down, left) {
    case (true, false, false, false): return .north
    case (true, true, false, false): return .northEast
    case (false, true, false, false): return .east
    case (false, true, true, false): return .southEast
    case (false, false, true, false): return .south
    case (false, false, true, true): return .southWest
    case (false, false, false, true): return .west
    case (true, false, false, true): return .northWest
    default: return .neutral
    }
  }
}
