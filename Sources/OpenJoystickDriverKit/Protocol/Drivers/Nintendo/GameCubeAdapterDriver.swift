public import Foundation

/// The report ID of the adapter's input report, which carries all four ports (Dolphin
/// `GCAdapter.cpp`, SDL `SDL_hidapi_gamecube.c`).
private let gameCubeInputReportID: UInt8 = 0x21
/// The length of the input report, its report ID included.
private let gameCubeInputReportLength = 37
/// The report ID of the output report that starts input polling.
private let gameCubeStartReportID: UInt8 = 0x13
/// The report ID of the output report that carries one rumble byte per port.
private let gameCubeRumbleReportID: UInt8 = 0x11
/// The number of controller ports on the adapter.
private let gameCubePortCount = 4
/// The number of bytes each port takes in the input report.
private let gameCubePortStride = 9
/// The raw value of a centered stick axis.
private let gameCubeAxisCenter: UInt8 = 128
/// The distance from the center that SDL takes as full deflection until it sees a wider value.
private let gameCubeAxisInitialReach: UInt8 = 88
/// The raw trigger value that SDL takes as rest until it sees a lower one.
private let gameCubeTriggerInitialRest: UInt8 = 40
/// The interval at which a port resends the shared rumble bytes while any motor runs.
private let gameCubeRumbleResendNanoseconds: UInt64 = 500_000_000

/// The rumble bytes that the four ports of one GameCube adapter share.
///
/// The adapter takes all four motors in one output report, so each port's driver writes the
/// bytes of every port. The bank keeps them, and every driver of one adapter must share one bank.
public final class GameCubeAdapterRumbleBank: Sendable {
  /// The motor byte of each port, and whether a resend is still owed since the last change.
  private let motors = Locked(
    (bytes: [UInt8](repeating: 0, count: gameCubePortCount), dirty: false)
  )

  /// Creates a bank with every motor off.
  public init() {}

  /// Sets the motor of `port` and returns the rumble report for all four ports.
  func set(port: Int, on: Bool) -> PhysicalHIDOutputReport {
    let bytes = motors.withLock { motors in
      let value: UInt8 = on ? 1 : 0
      if motors.bytes[port] != value {
        motors.bytes[port] = value
        motors.dirty = true
      }
      return motors.bytes
    }
    return Self.report(bytes)
  }

  /// Turns the motor of `port` off without writing; the next resend carries the change.
  func clear(port: Int) {
    motors.withLock { motors in
      guard motors.bytes[port] != 0 else { return }
      motors.bytes[port] = 0
      motors.dirty = true
    }
  }

  /// The rumble report to resend: present while any motor runs, and once after the last change.
  ///
  /// Each port writes through its own output queue, so two ports' writes can land out of order;
  /// the resend restores the latest bytes.
  func resend() -> PhysicalHIDOutputReport? {
    let bytes: [UInt8]? = motors.withLock { motors in
      guard motors.dirty || motors.bytes.contains(where: { $0 != 0 }) else { return nil }
      motors.dirty = false
      return motors.bytes
    }
    return bytes.map(Self.report)
  }

  /// The rumble output report that carries `bytes`.
  private static func report(_ bytes: [UInt8]) -> PhysicalHIDOutputReport {
    PhysicalHIDOutputReport(
      reportID: gameCubeRumbleReportID,
      bytes: [gameCubeRumbleReportID] + bytes
    )
  }
}

/// Driver for one port of the Nintendo Wii U GameCube Controller Adapter (`057E:0337`).
///
/// The adapter is one HID device with four controller ports. Each port runs its own driver; all
/// four read the same input report and share one ``GameCubeAdapterRumbleBank``. The layout follows
/// Dolphin `GCAdapter.cpp` and SDL `SDL_hidapi_gamecube.c`: report `0x21` holds nine bytes per
/// port at `1 + 9 * port`, which are status, two button bytes, the main stick, the C stick and the
/// two analog triggers. Status bit `0x10` is a wired pad and `0x20` a wireless one, and bit `0x04`
/// says the second USB cable powers rumble.
///
/// The button names follow SDL's GameCube mapping (`SDL_gamepad.c`), which maps by position: A is
/// south, X east, B west and Y north. Z is the right shoulder, and the full-press clicks of L and R
/// are the digital triggers. The axes scale like SDL's: each starts with a range of 88 around the
/// center (triggers from 40) and widens to the extremes it sees, and the stick Y axes are inverted.
public final class GameCubeAdapterDriver: PhysicalProtocolDriver {

  /// The masks of the first button byte.
  private enum FirstButtonMask {
    /// The A button.
    static let a: UInt8 = 0x01
    /// The B button.
    static let b: UInt8 = 0x02
    /// The X button.
    static let x: UInt8 = 0x04
    /// The Y button.
    static let y: UInt8 = 0x08
    /// D-pad left.
    static let left: UInt8 = 0x10
    /// D-pad right.
    static let right: UInt8 = 0x20
    /// D-pad down.
    static let down: UInt8 = 0x40
    /// D-pad up.
    static let up: UInt8 = 0x80
  }

  /// The masks of the second button byte.
  private enum SecondButtonMask {
    /// The Start button.
    static let start: UInt8 = 0x01
    /// The Z button.
    static let z: UInt8 = 0x02
    /// The full-press click of the R trigger.
    static let rightClick: UInt8 = 0x04
    /// The full-press click of the L trigger.
    static let leftClick: UInt8 = 0x08
  }

  /// The masks of the port status byte.
  private enum StatusMask {
    /// A wired controller is plugged in.
    static let wired: UInt8 = 0x10
    /// A wireless controller is paired.
    static let wireless: UInt8 = 0x20
    /// The second USB cable powers rumble.
    static let rumblePower: UInt8 = 0x04
  }

  /// The observed range of each axis: main X, main Y, C X, C Y, left trigger, right trigger.
  private struct AxisRanges {
    /// The lowest raw value of each axis.
    var minimum: [UInt8]
    /// The highest raw value of each axis.
    var maximum: [UInt8]

    /// SDL's starting ranges.
    static let initial = Self(
      minimum: [UInt8](repeating: gameCubeAxisCenter - gameCubeAxisInitialReach, count: 4)
        + [gameCubeTriggerInitialRest, gameCubeTriggerInitialRest],
      maximum: [UInt8](repeating: gameCubeAxisCenter + gameCubeAxisInitialReach, count: 6)
    )

    /// Widens axis `index` to `value` and returns `value` within the range, from 0 to 1.
    mutating func fraction(_ value: UInt8, axis index: Int) -> Float {
      minimum[index] = min(minimum[index], value)
      maximum[index] = max(maximum[index], value)
      let span = Float(maximum[index]) - Float(minimum[index])
      return (Float(value) - Float(minimum[index])) / span
    }
  }

  /// The port this driver reads, from 0.
  private let port: Int
  /// The rumble bytes shared with the adapter's other ports.
  private let rumbleBank: GameCubeAdapterRumbleBank
  /// The state after the latest report.
  private var state = ControllerState.neutral
  /// The axis ranges seen since the controller connected.
  private var ranges = AxisRanges.initial
  /// Whether a controller is in the port.
  private var connected = false
  /// Whether the controller in the port is wireless.
  private var wireless = false
  /// Whether the adapter's second USB cable powers rumble.
  private var rumblePowered = false
  /// The connection change not yet consumed.
  private var pendingConnectionState: ControllerInputConnectionState?

  /// Creates the driver of `port`, from 0 to 3, sharing `rumbleBank` with the adapter's other
  /// ports; nil for any other port.
  public init?(port: Int, rumbleBank: GameCubeAdapterRumbleBank = GameCubeAdapterRumbleBank()) {
    guard (0..<gameCubePortCount).contains(port) else { return nil }
    self.port = port
    self.rumbleBank = rumbleBank
  }

  /// The controls of the description: the Xbox layout without Back, the left shoulder and the stick
  /// clicks, with digital triggers.
  public var capabilities: ControllerCapabilities {
    PhysicalProtocolID.nintendoGameCubeAdapter.describedControls
  }

  /// Output waits for a controller in the port; a port's rumble bytes are resent while any motor
  /// runs.
  public var sessionPlan: DriverSessionPlan {
    DriverSessionPlan(
      requiresInputConnectionBeforeOutput: true,
      keepAliveChannels: [.hid],
      keepAliveIntervalNanoseconds: gameCubeRumbleResendNanoseconds
    )
  }

  /// One on-off motor; the adapter takes no intensity (SDL `HIDAPI_DriverGameCube_RumbleJoystick`).
  public var outputCapabilities: PhysicalControllerOutputCapabilities {
    PhysicalControllerOutputCapabilities(
      rumbleMotors: [.lowFrequency, .highFrequency],
      binaryRumbleMotors: [.lowFrequency, .highFrequency]
    )
  }

  /// No default colour: the adapter has no light.
  public var defaultColor: ControllerColor? { nil }

  /// Port 0 writes report `0x13`, which starts the adapter's input reports; the other ports share
  /// the started device.
  public func startupWrites() -> [PhysicalOutputWrite] {
    guard port == 0 else { return [] }
    return [
      .hidOutput(
        PhysicalHIDOutputReport(reportID: gameCubeStartReportID, bytes: [gameCubeStartReportID])
      )
    ]
  }

  /// The shared rumble bytes while any motor runs, and once after the last change.
  public func keepAliveWrites() -> [PhysicalOutputWrite] {
    rumbleBank.resend().map { [.hidOutput($0)] } ?? []
  }

  /// Clears the state and this port's motor; the next report sets the connection again.
  public func resetProtocolState() {
    state = .neutral
    ranges = .initial
    connected = false
    wireless = false
    rumblePowered = false
    pendingConnectionState = nil
    rumbleBank.clear(port: port)
  }

  /// Returns the pending connection change and clears it.
  public func consumeInputConnectionStateChange() -> ControllerInputConnectionState? {
    defer { pendingConnectionState = nil }
    return pendingConnectionState
  }

  /// Sets this port's motor in the shared bytes and writes them.
  ///
  /// A wireless controller has no motor (Dolphin `GCAdapter.cpp`, SDL), and a wired one rumbles
  /// only while the second USB cable is plugged in. A stop always writes.
  public func encode(
    _ command: ControllerOutputCommand
  ) throws(ControllerOutputError) -> PhysicalOutputPlan {
    let on: Bool
    switch command {
    case .setRumble(let intensities, _): on = !intensities.activeMotors.isEmpty
    case .stopRumble: on = false
    default: throw .unsupportedCapability(command.capability)
    }
    if on {
      guard connected else { throw .notReady }
      guard !wireless else { throw .unsupportedCapability(command.capability) }
      guard rumblePowered else { throw .notReady }
    }
    return PhysicalOutputPlan(writes: [.hidOutput(rumbleBank.set(port: port, on: on))])
  }

  /// Decodes this port's bytes from report `0x21`; any other report is ignored.
  ///
  /// A port with no controller yields the neutral state and queues the disconnect.
  public func parse(report data: Data, receivedAt: MonotonicTimestamp) -> ControllerEvent? {
    let bytes = [UInt8](data)
    guard bytes.count >= gameCubeInputReportLength, bytes[0] == gameCubeInputReportID else {
      return nil
    }
    let slot = Array(bytes[(1 + gameCubePortStride * port)..<(1 + gameCubePortStride * (port + 1))])
    let status = slot[0]
    wireless = status & StatusMask.wireless != 0
    rumblePowered = status & StatusMask.rumblePower != 0
    updateConnection(status & (StatusMask.wired | StatusMask.wireless) != 0)
    guard connected else { return ControllerEvent(timestamp: receivedAt, state: state) }
    var next = state
    apply(slot, to: &next)
    state = next
    return ControllerEvent(timestamp: receivedAt, state: next)
  }

  /// Records whether a controller is in the port and queues a change; a connect starts the axis
  /// ranges over, and a disconnect resets the state and this port's motor.
  private func updateConnection(_ isConnected: Bool) {
    guard connected != isConnected else { return }
    connected = isConnected
    pendingConnectionState = isConnected ? .connected : .disconnected
    ranges = .initial
    if !isConnected {
      state = .neutral
      rumbleBank.clear(port: port)
    }
  }

  /// Applies one port's nine bytes to `next`.
  private func apply(_ slot: [UInt8], to next: inout ControllerState) {
    let first = slot[1]
    let second = slot[2]
    for (mask, control) in [
      (FirstButtonMask.a, Control.south), (FirstButtonMask.x, .east), (FirstButtonMask.b, .west),
      (FirstButtonMask.y, .north),
    ] { next.set(control, pressed: first & mask != 0) }
    next.hat = HatDirection(
      up: first & FirstButtonMask.up != 0,
      right: first & FirstButtonMask.right != 0,
      down: first & FirstButtonMask.down != 0,
      left: first & FirstButtonMask.left != 0
    )
    for (mask, control) in [
      (SecondButtonMask.start, Control.start), (SecondButtonMask.z, .rightShoulder),
      (SecondButtonMask.leftClick, .leftTrigger), (SecondButtonMask.rightClick, .rightTrigger),
    ] { next.set(control, pressed: second & mask != 0) }
    func stick(_ offset: Int, axis: Int, inverted: Bool) -> Float {
      let value = ranges.fraction(slot[offset], axis: axis) * 2 - 1
      return inverted ? -value : value
    }
    next.leftStick = StickPosition(
      x: stick(3, axis: 0, inverted: false),
      y: stick(4, axis: 1, inverted: true)
    )
    next.rightStick = StickPosition(
      x: stick(5, axis: 2, inverted: false),
      y: stick(6, axis: 3, inverted: true)
    )
    next.leftTrigger = UnipolarValue(normalized: ranges.fraction(slot[7], axis: 4))
    next.rightTrigger = UnipolarValue(normalized: ranges.fraction(slot[8], axis: 5))
  }
}
