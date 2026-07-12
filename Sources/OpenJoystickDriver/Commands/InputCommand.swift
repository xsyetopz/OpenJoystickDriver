import Foundation
import OpenJoystickDriverKit

struct InputCommand {
  private enum Action {
    case state
    case packets
    case watch
  }

  private struct Options {
    var action: Action
    var vendorID: UInt16?
    var productID: UInt16?
    var json = false
    var jsonLines = false
    var limit = 50
    var seconds = 10
    var intervalMilliseconds = 16
  }

  func run(arguments: [String]) {
    let options = parse(arguments)
    let service = ControllerInputDiagnosticService()
    let failure = runSyncResult {
      await execute(options, service: service)
    }
    runSync { await service.disconnect() }
    if let failure {
      print("ERROR: \(failure)")
      exit(1)
    }
  }

  private func execute(
    _ options: Options,
    service: ControllerInputDiagnosticService
  ) async -> String? {
    do {
      let identifier = try await resolveIdentifier(options, service: service)
      switch options.action {
      case .state:
        try await printState(identifier, json: options.json, service: service)
      case .packets:
        try await printPackets(
          identifier,
          limit: options.limit,
          json: options.json,
          service: service
        )
      case .watch:
        try await watch(
          identifier,
          seconds: options.seconds,
          intervalMilliseconds: options.intervalMilliseconds,
          jsonLines: options.jsonLines,
          service: service
        )
      }
      return nil
    } catch {
      return error.localizedDescription
    }
  }

  private func resolveIdentifier(
    _ options: Options,
    service: ControllerInputDiagnosticService
  ) async throws -> DeviceIdentifier {
    if let vendorID = options.vendorID, let productID = options.productID {
      return DeviceIdentifier(vendorID: vendorID, productID: productID)
    }

    let devices = try await service.connectedDevices()
    guard let device = devices.only else {
      if devices.isEmpty {
        throw InputCommandFailure("No controller is connected.")
      }
      let choices = devices.map {
        "\(hex($0.vendorID)) \(hex($0.productID)) \($0.name)"
      }.joined(separator: "\n  ")
      throw InputCommandFailure(
        "Multiple controllers are connected. Pass VID and PID:\n  \(choices)"
      )
    }
    return DeviceIdentifier(vendorID: device.vendorID, productID: device.productID)
  }

  private func printState(
    _ identifier: DeviceIdentifier,
    json: Bool,
    service: ControllerInputDiagnosticService
  ) async throws {
    guard
      let state = try await service.deviceInputState(
        vendorID: identifier.vendorID,
        productID: identifier.productID
      )
    else {
      throw InputCommandFailure(
        "No input state has been received for \(hex(identifier.vendorID)) "
          + "\(hex(identifier.productID))."
      )
    }

    if json {
      try printJSON(state, pretty: true)
      return
    }
    print("Controller input \(hex(identifier.vendorID)):\(hex(identifier.productID))")
    print("  \(formatted(state))")
  }

  private func printPackets(
    _ identifier: DeviceIdentifier,
    limit: Int,
    json: Bool,
    service: ControllerInputDiagnosticService
  ) async throws {
    let entries = try await service.packetLog(
      vendorID: identifier.vendorID,
      productID: identifier.productID
    )
    let selected = Array(entries.suffix(limit))
    warnAboutRawPackets(json: json)

    if json {
      try printJSON(selected, pretty: true)
      return
    }

    print(
      "Recent packets \(hex(identifier.vendorID)):\(hex(identifier.productID)) "
        + "(\(selected.count)/\(entries.count))"
    )
    if selected.isEmpty {
      print("  (none captured)")
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
    _ identifier: DeviceIdentifier,
    seconds: Int,
    intervalMilliseconds: Int,
    jsonLines: Bool,
    service: ControllerInputDiagnosticService
  ) async throws {
    let deadline = DispatchTime.now().uptimeNanoseconds
      + UInt64(seconds) * 1_000_000_000
    let interval = UInt64(intervalMilliseconds) * 1_000_000
    var previous: DeviceInputState?
    var observedState = false

    if !jsonLines {
      print(
        "Watching \(hex(identifier.vendorID)):\(hex(identifier.productID)) "
          + "for \(seconds)s every \(intervalMilliseconds)ms. Press controls now."
      )
    }

    while DispatchTime.now().uptimeNanoseconds < deadline {
      let state = try await service.deviceInputState(
        vendorID: identifier.vendorID,
        productID: identifier.productID
      )
      if let state, state != previous {
        observedState = true
        if jsonLines {
          try printJSON(state, pretty: false)
        } else {
          print("  \(formatted(state))")
        }
        previous = state
      }
      try await Task.sleep(nanoseconds: interval)
    }

    if !observedState && !jsonLines {
      print("No input state was observed.")
    }
  }

  private func formatted(_ state: DeviceInputState) -> String {
    let buttons = state.pressedButtons.isEmpty
      ? "none" : state.pressedButtons.sorted().joined(separator: ",")
    return String(
      format:
        "buttons=[%@] LS=(%.3f,%.3f) RS=(%.3f,%.3f) LT=%.3f RT=%.3f",
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
      throw InputCommandFailure("Could not encode UTF-8 JSON output.")
    }
    print(output)
  }

  private func warnAboutRawPackets(json: Bool) {
    let warning =
      "Raw controller packets may contain device-specific data. Review before sharing."
    if json {
      FileHandle.standardError.write(Data("WARNING: \(warning)\n".utf8))
    } else {
      print("WARNING: \(warning)")
    }
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
    case "watch": action = .watch
    default:
      print("Unknown input command: \(command)")
      printHelp()
      exit(1)
    }

    var options = Options(action: action)
    var identifiers: [UInt16] = []
    var index = 1
    while index < arguments.count {
      let argument = arguments[index]
      switch argument {
      case "--json" where action != .watch:
        options.json = true
        index += 1
      case "--json-lines" where action == .watch:
        options.jsonLines = true
        index += 1
      case "--limit" where action == .packets:
        options.limit = parseIntegerOption(
          arguments,
          index: &index,
          option: argument,
          range: 1...200
        )
      case "--seconds" where action == .watch:
        options.seconds = parseIntegerOption(
          arguments,
          index: &index,
          option: argument,
          range: 1...3_600
        )
      case "--interval-ms" where action == .watch:
        options.intervalMilliseconds = parseIntegerOption(
          arguments,
          index: &index,
          option: argument,
          range: 8...1_000
        )
      default:
        guard !argument.hasPrefix("--"), let value = parseIdentifier(argument) else {
          print("Invalid input option or identifier: \(argument)")
          printHelp()
          exit(1)
        }
        identifiers.append(value)
        index += 1
      }
    }

    guard identifiers.isEmpty || identifiers.count == 2 else {
      print("Pass both VID and PID, or omit both when one controller is connected.")
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
    guard index + 1 < arguments.count,
      let value = Int(arguments[index + 1]),
      range.contains(value)
    else {
      print("\(option) must be \(range.lowerBound)...\(range.upperBound).")
      exit(1)
    }
    index += 2
    return value
  }

  private func parseIdentifier(_ raw: String) -> UInt16? {
    if raw.lowercased().hasPrefix("0x") {
      return UInt16(raw.dropFirst(2), radix: 16)
    }
    return UInt16(raw, radix: 10)
  }

  private func hex(_ value: UInt16) -> String {
    String(format: "0x%04X", value)
  }

  private func printHelp() {
    print(
      [
        "Usage: OpenJoystickDriver --headless input <command> [VID PID] [options]",
        "",
        "Commands:",
        "  state    Print the latest normalized buttons, sticks, and triggers",
        "  packets  Print recent raw controller packets",
        "  watch    Print normalized state changes for a bounded duration",
        "",
        "VID and PID accept decimal or 0x-prefixed hexadecimal. Omit both when",
        "exactly one controller is connected.",
        "",
        "Options:",
        "  state   [--json]",
        "  packets [--limit 1...200] [--json]",
        "  watch   [--seconds 1...3600] [--interval-ms 8...1000] [--json-lines]",
      ].joined(separator: "\n")
    )
  }
}

private struct InputCommandFailure: LocalizedError, Sendable {
  let message: String

  init(_ message: String) {
    self.message = message
  }

  var errorDescription: String? { message }
}

private extension Collection {
  var only: Element? {
    count == 1 ? first : nil
  }
}
