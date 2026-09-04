import Foundation
import OpenJoystickDriverKit

struct InputCommand {
  private static let nanosecondsPerSecond: UInt64 = 1_000_000_000
  private static let nanosecondsPerMillisecond: UInt64 = 1_000_000

  private enum Action {
    case state
    case packets
    case trace
    case watch
  }

  private struct Options {
    var action: Action
    var vendorID: UInt16?
    var productID: UInt16?
    var runtimeIdentifier: String?
    var json = false
    var jsonLines = false
    var limit = 50
    var seconds = 10
    var intervalMilliseconds = 16
  }

  func run(arguments: [String]) {
    let options = parse(arguments)
    let service = ControllerInputDiagnosticService()
    let failure = withCLIShutdownCleanup(
      { runSync { await service.disconnect() } },
      { runSyncResult { await execute(options, service: service) } }
    )
    runSync { await service.disconnect() }
    if let failure {
      CLIOutput.error(failure)
      exit(1)
    }
  }

  private func execute(_ options: Options, service: ControllerInputDiagnosticService) async
    -> String?
  {
    do {
      let device = try await resolveDevice(options, service: service)
      switch options.action {
      case .state: try await printState(device, json: options.json, service: service)
      case .packets:
        try await printPackets(device, limit: options.limit, json: options.json, service: service)
      case .trace:
        try await tracePackets(
          device,
          seconds: options.seconds,
          intervalMilliseconds: options.intervalMilliseconds,
          jsonLines: options.jsonLines,
          service: service
        )
      case .watch:
        try await watch(
          device,
          seconds: options.seconds,
          intervalMilliseconds: options.intervalMilliseconds,
          jsonLines: options.jsonLines,
          service: service
        )
      }
      return nil
    } catch { return error.localizedDescription }
  }

  private func resolveDevice(_ options: Options, service: ControllerInputDiagnosticService)
    async throws -> ApplicationServiceDeviceDescription
  {
    let devices = try await service.connectedDevices()
    return try ConnectedControllerSelection.resolve(
      devices: devices,
      vendorID: options.vendorID,
      productID: options.productID,
      runtimeIdentifier: options.runtimeIdentifier
    )
  }

  private func printState(
    _ device: ApplicationServiceDeviceDescription,
    json: Bool,
    service: ControllerInputDiagnosticService
  ) async throws {
    guard
      let state = try await service.deviceInputState(
        vendorID: device.vendorID,
        productID: device.productID,
        runtimeIdentifier: device.runtimeIdentifier
      )
    else {
      throw InputCommandFailure(
        CLILocalized.format(
          "cli.controller.noInputFrom",
          "No input received from %@:%@.",
          hex(device.vendorID),
          hex(device.productID)
        )
      )
    }

    if json {
      try printJSON(state, pretty: true)
      return
    }
    print(
      CLILocalized.format(
        "cli.controller.state",
        "Controller state %@:%@",
        hex(device.vendorID),
        hex(device.productID)
      )
    )
    print("  \(formatted(state))")
  }

  private func printPackets(
    _ device: ApplicationServiceDeviceDescription,
    limit: Int,
    json: Bool,
    service: ControllerInputDiagnosticService
  ) async throws {
    let entries = try await service.packetLog(
      vendorID: device.vendorID,
      productID: device.productID,
      runtimeIdentifier: device.runtimeIdentifier
    )
    let selected = Array(entries.suffix(limit))
    warnAboutRawPackets()

    if json {
      try printJSON(selected, pretty: true)
      return
    }

    print(
      CLILocalized.format(
        "cli.controller.recentPackets",
        "Recent packets %@:%@ (%d/%d)",
        hex(device.vendorID),
        hex(device.productID),
        selected.count,
        entries.count
      )
    )
    if selected.isEmpty {
      print("  \(CLILocalized.text("cli.controller.noPackets", "(no packets)"))")
      return
    }
    for entry in selected {
      print(
        "  \(String(format: "%.3f", entry.timestamp)) "
          + "\(entry.direction) len=\(entry.length) \(entry.hex)"
      )
    }
  }

  private func watch(
    _ device: ApplicationServiceDeviceDescription,
    seconds: Int,
    intervalMilliseconds: Int,
    jsonLines: Bool,
    service: ControllerInputDiagnosticService
  ) async throws {
    let deadline =
      DispatchTime.now().uptimeNanoseconds + UInt64(seconds) * Self.nanosecondsPerSecond
    let interval = UInt64(intervalMilliseconds) * Self.nanosecondsPerMillisecond
    var previous: DeviceInputState?
    var observedState = false

    if !jsonLines {
      print(
        CLILocalized.format(
          "cli.controller.readingInput",
          "Reading input from %@:%@ for %d seconds. Press controller buttons.",
          hex(device.vendorID),
          hex(device.productID),
          seconds
        )
      )
    }

    while DispatchTime.now().uptimeNanoseconds < deadline {
      let state = try await service.deviceInputState(
        vendorID: device.vendorID,
        productID: device.productID,
        runtimeIdentifier: device.runtimeIdentifier
      )
      if let state, state != previous {
        observedState = true
        if jsonLines { try printJSON(state, pretty: false) } else { print("  \(formatted(state))") }
        previous = state
      }
      try await Task.sleep(nanoseconds: interval)
    }

    if !observedState && !jsonLines {
      print(CLILocalized.text("cli.controller.noInput", "No input received."))
    }
  }

  private func tracePackets(
    _ device: ApplicationServiceDeviceDescription,
    seconds: Int,
    intervalMilliseconds: Int,
    jsonLines: Bool,
    service: ControllerInputDiagnosticService
  ) async throws {
    let initialEntries = try await service.packetLog(
      vendorID: device.vendorID,
      productID: device.productID,
      runtimeIdentifier: device.runtimeIdentifier
    )
    var cursor = PacketLogSnapshotCursor(snapshot: initialEntries)
    let deadline =
      DispatchTime.now().uptimeNanoseconds + UInt64(seconds) * Self.nanosecondsPerSecond
    let interval = UInt64(intervalMilliseconds) * Self.nanosecondsPerMillisecond
    var observedPacket = false

    warnAboutRawPackets()
    let traceStatus = CLILocalized.format(
      "cli.controller.capturingPackets",
      "Capturing packets from %@:%@ for %d seconds. Press controller buttons.",
      hex(device.vendorID),
      hex(device.productID),
      seconds
    )
    if jsonLines { CLIOutput.diagnostic(traceStatus) } else { print(traceStatus) }

    while DispatchTime.now().uptimeNanoseconds < deadline {
      let entries = try await service.packetLog(
        vendorID: device.vendorID,
        productID: device.productID,
        runtimeIdentifier: device.runtimeIdentifier
      )
      for entry in cursor.consume(snapshot: entries) {
        observedPacket = true
        if jsonLines {
          try printJSON(entry, pretty: false)
        } else {
          print(
            "  \(String(format: "%.3f", entry.timestamp)) "
              + "\(entry.direction) len=\(entry.length) \(entry.hex)"
          )
        }
      }
      try await Task.sleep(nanoseconds: interval)
    }

    if !observedPacket {
      let message = CLILocalized.text("cli.controller.noPacketsReceived", "No packets received.")
      if jsonLines { CLIOutput.diagnostic(message) } else { print(message) }
    }
  }

  private func formatted(_ state: DeviceInputState) -> String {
    let buttons =
      state.pressedButtons.isEmpty ? "none" : state.pressedButtons.sorted().joined(separator: ",")
    return String(
      format: "buttons=[%@] LS=(%.3f,%.3f) RS=(%.3f,%.3f) LT=%.3f RT=%.3f",
      buttons,
      state.leftStickX,
      state.leftStickY,
      state.rightStickX,
      state.rightStickY,
      state.leftTrigger,
      state.rightTrigger
    )
  }

  private func printJSON<T: Encodable>(_ value: T, pretty: Bool) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
    let data = try encoder.encode(value)
    guard let output = String(data: data, encoding: .utf8) else {
      throw InputCommandFailure(
        CLILocalized.text("cli.controller.jsonEncodeFailed", "Could not encode UTF-8 JSON output.")
      )
    }
    print(output)
  }

  private func warnAboutRawPackets() {
    CLIOutput.warning(
      CLILocalized.text(
        "cli.controller.packetWarning",
        "Packet contents vary by controller. Check them before sharing."
      )
    )
  }

  private func parse(_ arguments: [String]) -> Options {
    guard let command = arguments.first else {
      printHelp()
      exit(1)
    }
    if ["--help", "-h", "help"].contains(command) {
      printHelp()
      exit(0)
    }

    let action: Action
    switch command {
    case "state": action = .state
    case "packets": action = .packets
    case "trace": action = .trace
    case "watch": action = .watch
    default:
      CLIOutput.error(
        CLILocalized.format(
          "cli.controller.unknownCommand",
          "Unknown controller command: %@",
          command
        )
      )
      printHelp()
      exit(1)
    }

    var options = Options(action: action)
    var identifiers: [UInt16] = []
    var index = 1
    while index < arguments.count {
      let argument = arguments[index]
      switch argument {
      case "--json" where action == .state || action == .packets:
        options.json = true
        index += 1
      case "--json-lines" where action == .watch || action == .trace:
        options.jsonLines = true
        index += 1
      case "--limit" where action == .packets:
        options.limit = parseIntegerOption(
          arguments,
          index: &index,
          option: argument,
          range: 1...200
        )
      case "--seconds" where action == .watch || action == .trace:
        options.seconds = parseIntegerOption(
          arguments,
          index: &index,
          option: argument,
          range: 1...3_600
        )
      case "--interval-ms" where action == .watch || action == .trace:
        options.intervalMilliseconds = parseIntegerOption(
          arguments,
          index: &index,
          option: argument,
          range: 8...1_000
        )
      case "--device":
        guard options.runtimeIdentifier == nil, index + 1 < arguments.count else {
          CLIOutput.error(
            CLILocalized.text(
              "cli.controller.deviceRequired",
              "--device requires one unique identifier."
            )
          )
          exit(1)
        }
        let identifier = arguments[index + 1]
        guard !identifier.isEmpty, !identifier.hasPrefix("--") else {
          CLIOutput.error(
            CLILocalized.text(
              "cli.controller.deviceRequired",
              "--device requires one unique identifier."
            )
          )
          exit(1)
        }
        options.runtimeIdentifier = identifier
        index += 2
      default:
        guard !argument.hasPrefix("--"), let value = parseIdentifier(argument) else {
          CLIOutput.error(
            CLILocalized.format(
              "cli.controller.invalidOption",
              "Invalid controller option or identifier: %@",
              argument
            )
          )
          printHelp()
          exit(1)
        }
        identifiers.append(value)
        index += 1
      }
    }

    guard identifiers.isEmpty || identifiers.count == 2 else {
      CLIOutput.error(
        CLILocalized.text(
          "cli.controller.vidPidOrSingle",
          "Pass both VID and PID, or omit both when one controller is connected."
        )
      )
      exit(1)
    }
    if identifiers.count == 2 {
      options.vendorID = identifiers[0]
      options.productID = identifiers[1]
    }
    return options
  }

  private func parseIntegerOption(
    _ arguments: [String],
    index: inout Int,
    option: String,
    range: ClosedRange<Int>
  ) -> Int {
    guard index + 1 < arguments.count, let value = Int(arguments[index + 1]), range.contains(value)
    else {
      CLIOutput.error(
        CLILocalized.format(
          "cli.controller.optionRange",
          "%@ must be %d...%d.",
          option,
          range.lowerBound,
          range.upperBound
        )
      )
      exit(1)
    }
    index += 2
    return value
  }

  private func parseIdentifier(_ raw: String) -> UInt16? {
    if raw.lowercased().hasPrefix("0x") { return UInt16(raw.dropFirst(2), radix: 16) }
    return UInt16(raw, radix: 10)
  }

  private func hex(_ value: UInt16) -> String { String(format: "0x%04X", value) }

  private func printHelp() {
    print(
      CLILocalized.text(
        "cli.controller.input.help",
        """
        Usage: OpenJoystickDriver --headless controller <state|packets|trace|watch> [options]

        Commands:
          state    Print the latest normalized buttons, sticks, and triggers
          packets  Print recent raw controller packets
          trace    Capture raw controller packets for a set duration
          watch    Print normalized state changes for a bounded duration

        VID and PID accept decimal or 0x-prefixed hexadecimal. Omit both when
        exactly one controller is connected. Use --device with the opaque ID
        reported by controller output list when identical models are connected.

        Options:
          state   [--device <id>] [--json]
          packets [--device <id>] [--limit 1...200] [--json]
          trace   [--device <id>] [--seconds 1...3600]
                  [--interval-ms 8...1000] [--json-lines]
          watch   [--device <id>] [--seconds 1...3600]
                  [--interval-ms 8...1000] [--json-lines]
        """
      )
    )
  }
}

private struct InputCommandFailure: LocalizedError, Sendable {
  let message: String

  init(_ message: String) { self.message = message }

  var errorDescription: String? { message }
}
