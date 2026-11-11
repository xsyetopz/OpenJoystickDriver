import ArgumentParser
import Foundation
import OpenJoystickDriverKit

/// Polls the service every 16 ms until `body` returns true or `duration` elapses.
///
/// Returns whether `body` stopped the loop. Without a duration it runs until interrupted.
func pollController(duration: Double?, _ body: () async throws -> Bool) async throws -> Bool {
  let start = DispatchTime.now().uptimeNanoseconds
  let limit = duration.map { UInt64($0 * 1_000_000_000) }
  while limit.map({ DispatchTime.now().uptimeNanoseconds - start < $0 }) ?? true {
    if try await body() { return true }
    try await Task.sleep(nanoseconds: 16_000_000)
  }
  return false
}

/// Refuses a `--duration` that is not a positive number.
///
/// - Throws: `ValidationError` for the refused value.
func validateDuration(_ duration: Double?) throws {
  if let duration, !isPositiveSeconds(duration) {
    throw ValidationError(
      CLILocalized.text(
        "cli.controller.group.errorDuration"
      )
    )
  }
}

/// The shared help of `--duration`.
let durationHelp = ArgumentHelp(
  CLILocalized.text(
    "cli.controller.group.optionDuration"
  ),
  valueName: "seconds"
)

/// Opens one service connection, resolves the controller, and runs `body` with both.
///
/// - Throws: ``CLIFailure`` when the service is not running or the controller is not found.
func withController(
  _ selector: ControllerSelector,
  _ body: (ApplicationServiceClient, ApplicationServiceDeviceDescription) async throws -> Void
) async throws {
  let client = try await ServiceConnection.open()
  defer { client.disconnect() }
  let device = try await ServiceConnection.withDeadline(seconds: CLIContext.current.requestTimeout)
  { try await selector.resolve(with: client) }
  try await body(client, device)
}

/// A control pressed during `ojd controller watch --first-press`.
struct ControllerFirstPress: Encodable, Equatable {
  /// The control, such as `south` or `left-shoulder`.
  let control: String
  /// The D-pad direction, when the control is the D-pad.
  let direction: String?

  /// The first control pressed in `state` that `previous` did not hold, in `Control` order,
  /// then the D-pad id for the hat when it leaves neutral; a diagonal names its vertical id.
  init?(previous: ControllerState, state: ControllerState) {
    if let pressed = Control.allCases.first(where: {
      state.pressed.contains($0) && !previous.pressed.contains($0)
    }) {
      self.control = pressed.rawValue
      direction = nil
    } else if state.hat != .neutral, state.hat != previous.hat {
      control = state.hat.dpadControl.rawValue
      direction = state.hat.rawValue
    } else {
      return nil
    }
  }
}

/// The `ojd controller watch` command: prints a controller's input state each time it changes.
struct ControllerWatchCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "watch",
    abstract: CLILocalized.text(
      "cli.controller.watch.abstract"
    ),
    discussion: CLILocalized.text(
      "cli.controller.watch.discussion"
    ) + " "
      + CLILocalized.text(
        "cli.controller.watch.discussionAll"
      ) + "\n\n" + CLILocalized.text("cli.controller.watch.examples")
  )

  /// The global options.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  /// The controller to watch; omitted with `--all`.
  @Argument(help: controllerArgumentHelp)
  var controller: ControllerSelector?

  /// `--all`: watch every controller, with connection events.
  @Flag(
    help: ArgumentHelp(
      CLILocalized.text(
        "cli.controller.watch.all"
      )
    )
  )
  var all = false

  /// `--duration`: stop after this many seconds.
  @Option(help: durationHelp)
  var duration: Double?

  /// `--first-press`: print the first control pressed and exit.
  @Flag(
    help: ArgumentHelp(
      CLILocalized.text(
        "cli.controller.watch.firstPress"
      )
    )
  )
  var firstPress = false

  /// `--output`: also print the values of the controller's virtual gamepad.
  @Flag(
    help: ArgumentHelp(
      CLILocalized.text(
        "cli.controller.watch.output"
      )
    )
  )
  var output = false

  /// One poll: the controller's input state and, with `--output`, its virtual gamepad's values.
  struct Sample: Encodable, Equatable {
    /// The input state.
    let input: ControllerState
    /// The virtual gamepad's values, or nil when none is published or `--output` is off.
    let output: ApplicationServiceVirtualOutputState?
  }

  /// Checks the duration and that the command names either `--all` or one controller.
  ///
  /// - Throws: ``ValidationError`` otherwise.
  func validate() throws {
    try validateDuration(duration)
    if all == (controller != nil) {
      throw ValidationError(
        CLILocalized.text(
          "cli.controller.watch.errorTarget"
        )
      )
    }
    if all, firstPress {
      throw ValidationError(
        CLILocalized.text(
          "cli.controller.watch.errorFirstPressAll"
        )
      )
    }
  }

  /// Runs the command.
  func run() async throws {
    try await global.run {
      guard let controller else { return try await watchAll() }
      try await withController(controller) { client, device in
        let timeout = CLIContext.current.requestTimeout
        let read: @Sendable () async throws -> ControllerState? = {
          try await ServiceConnection.withDeadline(seconds: timeout) {
            try await client.controllerState(for: .session(device.sessionToken))
          }
        }
        let readOutput: @Sendable () async throws -> ApplicationServiceVirtualOutputState? = {
          try await ServiceConnection.withDeadline(seconds: timeout) {
            try await client.virtualOutputState(for: .session(device.sessionToken))
          }
        }
        if firstPress {
          try await waitForFirstPress(device, read: read)
        } else {
          try await watch(device) {
            // The output is built from the input after it, so reading it first keeps an `out`
            // line from showing a value before the input that produced it.
            let sent = output ? try await readOutput() : nil
            guard let input = try await read() else { return nil }
            return Sample(input: input, output: sent)
          }
        }
      }
    }
  }

  /// Prints each change of the controller's state until `duration` elapses.
  private func watch(
    _ device: ApplicationServiceDeviceDescription,
    read: () async throws -> Sample?
  ) async throws {
    if CLIContext.current.format == .human {
      CLIOutput.success(
        CLILocalized.format(
          "cli.controller.watch.started",
          device.name,
          device.identity
        )
      )
    }
    var previous: Sample?
    _ = try await pollController(duration: duration) {
      guard let sample = try await read(), sample != previous else { return false }
      previous = sample
      switch CLIContext.current.format {
      case .json where output: try CLIOutput.jsonLine(sample)
      case .json: try CLIOutput.jsonLine(sample.input)
      case .plain where output:
        CLIOutput.plain([Self.plainRow(sample.input) + Self.plainRow(sample.output)])
      case .plain: CLIOutput.plain([Self.plainRow(sample.input)])
      case .human where output:
        CLIOutput.stdout(Self.formatted(sample.input))
        CLIOutput.stdout(Self.formatted(sample.output))
      case .human: CLIOutput.stdout(Self.formatted(sample.input))
      }
      return false
    }
    if previous == nil, CLIContext.current.format == .human {
      CLIOutput.stderr(CLILocalized.text("cli.controller.watch.noInput"))
    }
  }

  /// Waits for the first control pressed and prints it.
  ///
  /// - Throws: ``CLIFailure`` when `--duration` passes first.
  private func waitForFirstPress(
    _ device: ApplicationServiceDeviceDescription,
    read: () async throws -> ControllerState?
  ) async throws {
    if CLIContext.current.format == .human {
      CLIOutput.success(
        CLILocalized.format(
          "cli.controller.watch.pressPrompt",
          device.name,
          device.identity
        )
      )
    }
    // Controls already held when the command starts do not count as pressed.
    var previous: ControllerState?
    var press: ControllerFirstPress?
    let pressed = try await pollController(duration: duration) {
      guard let state = try await read() else { return false }
      defer { previous = state }
      guard let previous else { return false }
      press = ControllerFirstPress(previous: previous, state: state)
      return press != nil
    }
    guard pressed, let press else {
      throw CLIFailure(
        .aborted,
        CLILocalized.format(
          "cli.controller.watch.noPress",
          (duration ?? 0).durationText
        )
      )
    }
    switch CLIContext.current.format {
    case .json: try CLIOutput.json(press, kind: "ControlPress")
    case .plain:
      CLIOutput.plain([
        [press.control] + (press.direction.map { [CommandLineName.kebab($0)] } ?? [])
      ])
    case .human:
      CLIOutput.stdout(
        press.direction.map { "\(press.control) \(CommandLineName.kebab($0))" } ?? press.control
      )
    }
  }

  /// Pressed controls, hat, sticks, and triggers as tab-separated fields.
  static func plainRow(_ state: ControllerState) -> [String] {
    [
      pressedControls(state).joined(separator: ","), CommandLineName.kebab(state.hat.rawValue),
      String(state.leftStick.x.rawValue), String(state.leftStick.y.rawValue),
      String(state.rightStick.x.rawValue), String(state.rightStick.y.rawValue),
      String(state.leftTrigger.rawValue), String(state.rightTrigger.rawValue),
    ]
  }

  /// Pressed controls in `Control` order, the hat, and the raw stick and trigger values.
  static func formatted(_ state: ControllerState) -> String {
    let pressed = pressedControls(state)
    let buttons = pressed.isEmpty ? "none" : pressed.joined(separator: ",")
    return "buttons=[\(buttons)] hat=\(CommandLineName.kebab(state.hat.rawValue))"
      + " LS=(\(state.leftStick.x.rawValue),\(state.leftStick.y.rawValue))"
      + " RS=(\(state.rightStick.x.rawValue),\(state.rightStick.y.rawValue))"
      + " LT=\(state.leftTrigger.rawValue) RT=\(state.rightTrigger.rawValue)"
  }

  /// Virtual buttons in hex, hat, sticks, and triggers as tab-separated fields; empty fields when
  /// no virtual gamepad publishes the controller.
  static func plainRow(_ state: ApplicationServiceVirtualOutputState?) -> [String] {
    guard let state else { return Array(repeating: "", count: 8) }
    return [
      hex(state.buttons), CommandLineName.kebab(state.hat.rawValue),
      String(state.leftStickX), String(state.leftStickY),
      String(state.rightStickX), String(state.rightStickY),
      String(state.leftTrigger), String(state.rightTrigger),
    ]
  }

  /// The virtual gamepad's values on an `out` line, or `out none` when nothing is published.
  static func formatted(_ state: ApplicationServiceVirtualOutputState?) -> String {
    guard let state else { return "out none" }
    return "out buttons=\(hex(state.buttons)) hat=\(CommandLineName.kebab(state.hat.rawValue))"
      + " LS=(\(state.leftStickX),\(state.leftStickY))"
      + " RS=(\(state.rightStickX),\(state.rightStickY))"
      + " LT=\(state.leftTrigger) RT=\(state.rightTrigger)"
  }

  /// `buttons` as a hex number.
  private static func hex(_ buttons: UInt32) -> String {
    "0x" + String(buttons, radix: 16, uppercase: true)
  }

  /// The names of the pressed controls in `Control` order.
  private static func pressedControls(_ state: ControllerState) -> [String] {
    Control.allCases.filter(state.pressed.contains).map(\.rawValue)
  }
}

/// The `ojd controller capture` command: prints the raw packets that a controller sends and
/// receives.
struct ControllerCaptureCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "capture",
    abstract: CLILocalized.text(
      "cli.controller.capture.abstract"
    ),
    discussion: CLILocalized.text(
      "cli.controller.capture.discussion"
    )
  )

  /// The global options.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  /// The controller to capture.
  @Argument(help: controllerArgumentHelp)
  var controller: ControllerSelector

  /// `--duration`: stop after this many seconds.
  @Option(help: durationHelp)
  var duration: Double?

  /// Checks the duration.
  func validate() throws { try validateDuration(duration) }

  /// Runs the command.
  func run() async throws {
    try await global.run {
      try await withController(controller) { client, device in
        let timeout = CLIContext.current.requestTimeout
        let read: @Sendable () async throws -> [PacketLogEntry] = {
          try await ServiceConnection.withDeadline(seconds: timeout) {
            try await client.packetLog(for: .session(device.sessionToken))
          }
        }
        var cursor = PacketLogSnapshotCursor(snapshot: try await read())
        CLIOutput.stderr(
          CLILocalized.text(
            "cli.controller.capture.warning"
          )
        )
        if CLIContext.current.format == .human {
          CLIOutput.success(
            CLILocalized.format(
              "cli.controller.capture.started",
              device.name,
              device.identity
            )
          )
        }
        var received = false
        _ = try await pollController(duration: duration) {
          for entry in cursor.consume(snapshot: try await read()) {
            received = true
            try Self.print(entry)
          }
          return false
        }
        if !received, CLIContext.current.format == .human {
          CLIOutput.stderr(
            CLILocalized.text("cli.controller.capture.noPackets")
          )
        }
      }
    }
  }

  /// One `RawReport` line of `--json`: the log entry with its time as an RFC 3339 `captureTime`.
  private struct JSONPacket: Encodable {
    /// `Rx` or `Tx`.
    let direction: PacketLogDirection
    /// The packet bytes as hex.
    let hex: String
    /// The packet length in bytes.
    let length: Int
    /// The time of the packet.
    let captureTime: String

    /// Creates the line from `entry`.
    init(_ entry: PacketLogEntry) {
      direction = entry.direction
      hex = entry.hex
      length = entry.length
      let formatter = ISO8601DateFormatter()
      formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      captureTime = formatter.string(from: Date(timeIntervalSince1970: entry.timestamp))
    }
  }

  /// Prints `entry` as JSON, as a `--plain` row or as a human line.
  private static func print(_ entry: PacketLogEntry) throws {
    let time = unsafe String(format: "%.3f", entry.timestamp)
    switch CLIContext.current.format {
    case .json: try CLIOutput.jsonLine(JSONPacket(entry))
    case .plain:
      CLIOutput.plain([
        [time, CommandLineName.kebab(entry.direction.rawValue), String(entry.length), entry.hex]
      ])
    case .human:
      CLIOutput.stdout(
        "\(time) \(CommandLineName.kebab(entry.direction.rawValue)) len=\(entry.length) "
          + entry.hex
      )
    }
  }
}
