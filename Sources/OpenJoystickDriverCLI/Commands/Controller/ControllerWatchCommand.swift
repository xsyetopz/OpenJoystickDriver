import ArgumentParser
import Foundation
import OpenJoystickDriverKit

/// Polls the service every 16 ms until `body` returns true or `duration` elapses.
///
/// Returns whether `body` stopped the loop. Without a duration it runs until interrupted.
private func pollController(duration: Double?, _ body: () async throws -> Bool) async throws -> Bool
{
  let start = DispatchTime.now().uptimeNanoseconds
  let limit = duration.map { UInt64($0 * 1_000_000_000) }
  while limit.map({ DispatchTime.now().uptimeNanoseconds - start < $0 }) ?? true {
    if try await body() { return true }
    try await Task.sleep(nanoseconds: 16_000_000)
  }
  return false
}

private func validateDuration(_ duration: Double?) throws {
  if let duration, !(duration.isFinite && duration > 0) {
    throw ValidationError(
      CLILocalized.text(
        "cli.controller.error.duration",
        "--duration needs a number of seconds above 0."
      )
    )
  }
}

private let durationHelp = ArgumentHelp(
  CLILocalized.text(
    "cli.controller.option.duration",
    "Stop after this many seconds. Without it, run until you press Control-C."
  ),
  valueName: "seconds"
)

/// Opens one service connection, resolves the controller, and runs `body` with both.
private func withController(
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
      "cli.controller.watch.abstract",
      "Print a controller's input state each time it changes."
    ),
    discussion: CLILocalized.text(
      "cli.controller.watch.discussion",
      "With --json, prints one JSON object per line. Stick Y points up. With --first-press, "
        + "prints the first control pressed and exits; it fails when --duration passes first."
    )
  )

  @OptionGroup
  var global: GlobalOptions

  @Argument(help: controllerArgumentHelp)
  var controller: ControllerSelector

  @Option(help: durationHelp)
  var duration: Double?

  @Flag(
    help: ArgumentHelp(
      CLILocalized.text(
        "cli.controller.watch.first_press",
        "Print the first control pressed, then exit."
      )
    )
  )
  var firstPress = false

  func validate() throws { try validateDuration(duration) }

  func run() async throws {
    try await global.run {
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
        if firstPress {
          try await waitForFirstPress(device, read: read)
        } else {
          try await watch(device, read: read)
        }
      }
    }
  }

  private func watch(
    _ device: ApplicationServiceDeviceDescription,
    read: () async throws -> ControllerState?
  ) async throws {
    if CLIContext.current.format == .human {
      CLIOutput.success(
        CLILocalized.format(
          "cli.controller.watch.started",
          "Watching %@ (%@). Press controller buttons.",
          device.name,
          device.identity
        )
      )
    }
    var previous: ControllerState?
    _ = try await pollController(duration: duration) {
      guard let state = try await read(), state != previous else { return false }
      previous = state
      switch CLIContext.current.format {
      case .json: try CLIOutput.jsonLine(state)
      case .plain: CLIOutput.plain([Self.plainRow(state)])
      case .human: CLIOutput.stdout(Self.formatted(state))
      }
      return false
    }
    if previous == nil, CLIContext.current.format == .human {
      CLIOutput.stderr(CLILocalized.text("cli.controller.watch.no_input", "No input received."))
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
          "Press a control on %@ (%@).",
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
        .failure,
        CLILocalized.format(
          "cli.controller.watch.no_press",
          "No control was pressed within %@ seconds.",
          (duration ?? 0).secondsText
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

  private static func pressedControls(_ state: ControllerState) -> [String] {
    ControlID.allCases.filter(state.pressed.contains).map(\.rawValue)
  }
}

struct ControllerCaptureCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "capture",
    abstract: CLILocalized.text(
      "cli.controller.capture.abstract",
      "Print the raw packets a controller sends and receives."
    ),
    discussion: CLILocalized.text(
      "cli.controller.capture.discussion",
      "Prints each new packet as it arrives: time, direction (rx or tx), length, and hex bytes. "
        + "With --json, prints one JSON object per line."
    )
  )

  @OptionGroup
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
            "cli.controller.capture.warning",
            "Packet contents vary by controller. Check them before sharing."
          )
        )
        if CLIContext.current.format == .human {
          CLIOutput.success(
            CLILocalized.format(
              "cli.controller.capture.started",
              "Capturing packets from %@ (%@). Press controller buttons.",
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
            CLILocalized.text("cli.controller.capture.no_packets", "No packets received.")
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
