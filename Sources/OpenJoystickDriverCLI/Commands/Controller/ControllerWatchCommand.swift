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

func validateDuration(_ duration: Double?) throws {
  if let duration, !(duration.isFinite && duration > 0) {
    throw ValidationError(
      CLILocalized.text(
        "cli.controller.error.duration"
      )
    )
  }
}

let durationHelp = ArgumentHelp(
  CLILocalized.text(
    "cli.controller.option.duration"
  ),
  valueName: "seconds"
)

/// Opens one service connection, resolves the controller, and runs `body` with both.
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
  let control: String
  let direction: String?

  /// The first control pressed in `state` that `previous` did not hold, in `ControlID` order,
  /// then the D-pad when the hat leaves neutral.
  init?(previous: ControllerState, state: ControllerState) {
    if let control = ControlID.allCases.first(where: {
      state.pressed.contains($0) && !previous.pressed.contains($0)
    }) {
      self.control = control.rawValue
      direction = nil
    } else if state.hat != .neutral, state.hat != previous.hat {
      control = ControlID.dpad.rawValue
      direction = state.hat.rawValue
    } else {
      return nil
    }
  }
}

struct ControllerWatchCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "watch",
    abstract: CLILocalized.text(
      "cli.controller.watch.abstract"
    ),
    discussion: CLILocalized.text(
      "cli.controller.watch.discussion"
    ) + " "
      + CLILocalized.text(
        "cli.controller.watch.discussion.all"
      ) + "\n\n" + CLILocalized.text("cli.controller.watch.examples")
  )

  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  @Argument(help: controllerArgumentHelp)
  var controller: ControllerSelector?

  @Flag(
    help: ArgumentHelp(
      CLILocalized.text(
        "cli.controller.watch.all"
      )
    )
  )
  var all = false

  @Option(help: durationHelp)
  var duration: Double?

  @Flag(
    help: ArgumentHelp(
      CLILocalized.text(
        "cli.controller.watch.first_press"
      )
    )
  )
  var firstPress = false

  @Flag(
    help: ArgumentHelp(
      CLILocalized.text(
        "cli.controller.watch.output"
      )
    )
  )
  var output = false

  /// One poll: the controller's input state and, with --output, its virtual gamepad's values.
  struct Sample: Encodable, Equatable {
    let input: ControllerState
    let output: ApplicationServiceVirtualOutputState?
  }

  func validate() throws {
    try validateDuration(duration)
    if all == (controller != nil) {
      throw ValidationError(
        CLILocalized.text(
          "cli.controller.watch.error.target"
        )
      )
    }
    if all, firstPress {
      throw ValidationError(
        CLILocalized.text(
          "cli.controller.watch.error.first_press_all"
        )
      )
    }
  }

  func run() async throws {
    try await global.run {
      guard let controller else { return try await watchAll() }
      try await withController(controller) { client, device in
        let timeout = CLIContext.current.requestTimeout
        let read: @Sendable () async throws -> ControllerState? = {
          try await ServiceConnection.withDeadline(seconds: timeout) {
            try await client.controllerState(
              vendorID: device.vendorID,
              productID: device.productID,
              runtimeIdentifier: device.runtimeIdentifier
            )
          }
        }
        let readOutput: @Sendable () async throws -> ApplicationServiceVirtualOutputState? = {
          try await ServiceConnection.withDeadline(seconds: timeout) {
            try await client.virtualOutputState(
              vendorID: device.vendorID,
              productID: device.productID,
              runtimeIdentifier: device.runtimeIdentifier
            )
          }
        }
        if firstPress {
          try await waitForFirstPress(device, read: read)
        } else {
          try await watch(device) {
            guard let input = try await read() else { return nil }
            return Sample(input: input, output: output ? try await readOutput() : nil)
          }
        }
      }
    }
  }

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
      CLIOutput.stderr(CLILocalized.text("cli.controller.watch.no_input"))
    }
  }

  private func waitForFirstPress(
    _ device: ApplicationServiceDeviceDescription,
    read: () async throws -> ControllerState?
  ) async throws {
    if CLIContext.current.format == .human {
      CLIOutput.success(
        CLILocalized.format(
          "cli.controller.watch.press_prompt",
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
          "cli.controller.watch.no_press",
          (duration ?? 0).durationText
        )
      )
    }
    switch CLIContext.current.format {
    case .json: try CLIOutput.json(press)
    case .plain: CLIOutput.plain([[press.control] + (press.direction.map { [$0] } ?? [])])
    case .human: CLIOutput.stdout(press.direction.map { "\(press.control) \($0)" } ?? press.control)
    }
  }

  /// Pressed controls, hat, sticks, and triggers as tab-separated fields.
  static func plainRow(_ state: ControllerState) -> [String] {
    [
      pressedControls(state).joined(separator: ","), state.hat.rawValue,
      String(state.leftStick.x.rawValue), String(state.leftStick.y.rawValue),
      String(state.rightStick.x.rawValue), String(state.rightStick.y.rawValue),
      String(state.leftTrigger.rawValue), String(state.rightTrigger.rawValue),
    ]
  }

  /// Pressed controls in `ControlID` order, the hat, and the raw stick and trigger values.
  static func formatted(_ state: ControllerState) -> String {
    let pressed = pressedControls(state)
    let buttons = pressed.isEmpty ? "none" : pressed.joined(separator: ",")
    return "buttons=[\(buttons)] hat=\(state.hat.rawValue)"
      + " LS=(\(state.leftStick.x.rawValue),\(state.leftStick.y.rawValue))"
      + " RS=(\(state.rightStick.x.rawValue),\(state.rightStick.y.rawValue))"
      + " LT=\(state.leftTrigger.rawValue) RT=\(state.rightTrigger.rawValue)"
  }

  /// Virtual buttons in hex, hat, sticks, and triggers as tab-separated fields; empty fields when
  /// no virtual gamepad publishes the controller.
  static func plainRow(_ state: ApplicationServiceVirtualOutputState?) -> [String] {
    guard let state else { return Array(repeating: "", count: 8) }
    return [
      hex(state.buttons), state.hat.rawValue,
      String(state.leftStickX), String(state.leftStickY),
      String(state.rightStickX), String(state.rightStickY),
      String(state.leftTrigger), String(state.rightTrigger),
    ]
  }

  /// The virtual gamepad's values on an `out` line, or `out none` when nothing is published.
  static func formatted(_ state: ApplicationServiceVirtualOutputState?) -> String {
    guard let state else { return "out none" }
    return "out buttons=\(hex(state.buttons)) hat=\(state.hat.rawValue)"
      + " LS=(\(state.leftStickX),\(state.leftStickY))"
      + " RS=(\(state.rightStickX),\(state.rightStickY))"
      + " LT=\(state.leftTrigger) RT=\(state.rightTrigger)"
  }

  private static func hex(_ buttons: UInt32) -> String {
    "0x" + String(buttons, radix: 16, uppercase: true)
  }

  private static func pressedControls(_ state: ControllerState) -> [String] {
    ControlID.allCases.filter(state.pressed.contains).map(\.rawValue)
  }
}

struct ControllerCaptureCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "capture",
    abstract: CLILocalized.text(
      "cli.controller.capture.abstract"
    ),
    discussion: CLILocalized.text(
      "cli.controller.capture.discussion"
    )
  )

  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  @Argument(help: controllerArgumentHelp)
  var controller: ControllerSelector

  @Option(help: durationHelp)
  var duration: Double?

  func validate() throws { try validateDuration(duration) }

  func run() async throws {
    try await global.run {
      try await withController(controller) { client, device in
        let timeout = CLIContext.current.requestTimeout
        let read: @Sendable () async throws -> [PacketLogEntry] = {
          try await ServiceConnection.withDeadline(seconds: timeout) {
            try await client.packetLog(
              vendorID: device.vendorID,
              productID: device.productID,
              runtimeIdentifier: device.runtimeIdentifier
            )
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
            CLILocalized.text("cli.controller.capture.no_packets")
          )
        }
      }
    }
  }

  private static func print(_ entry: PacketLogEntry) throws {
    let time = String(format: "%.3f", entry.timestamp)
    switch CLIContext.current.format {
    case .json: try CLIOutput.jsonLine(entry)
    case .plain:
      CLIOutput.plain([[time, entry.direction.rawValue, String(entry.length), entry.hex]])
    case .human:
      CLIOutput.stdout("\(time) \(entry.direction.rawValue) len=\(entry.length) \(entry.hex)")
    }
  }
}
