import Foundation
import OpenJoystickDriverKit

struct PhysicalOutputCommand {
  private struct ListedDevice: Codable {
    let id: String
    let name: String
    let vendorID: UInt16
    let productID: UInt16
    let parser: String
    let connection: String
    let physicalOutputCapabilities: PhysicalControllerOutputCapabilities

    init(_ device: ApplicationServiceDeviceDescription) {
      id = device.runtimeIdentifier
      name = device.name
      vendorID = device.vendorID
      productID = device.productID
      parser = device.parser
      connection = device.connection
      physicalOutputCapabilities = device.physicalOutputCapabilities
    }
  }

  func run(arguments: [String]) {
    let subcommand = arguments.first ?? "list"
    switch subcommand {
    case "list":
      list(arguments: Array(arguments.dropFirst()))
    case "rumble":
      rumble(arguments: Array(arguments.dropFirst()))
    case "player":
      player(arguments: Array(arguments.dropFirst()))
    case "brightness":
      brightness(arguments: Array(arguments.dropFirst()))
    case "color":
      color(arguments: Array(arguments.dropFirst()))
    case "plan":
      plan(arguments: Array(arguments.dropFirst()))
    case "--help", "-h", "help":
      printHelp()
    default:
      fail("Unknown controller output command: \(subcommand)")
    }
  }

  private func list(arguments: [String]) {
    guard arguments.allSatisfy({ $0 == "--json" }) && arguments.count <= 1 else {
      printHelp()
      exit(1)
    }
    let devices = connectedDevices()
    if arguments.contains("--json") {
      do {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(devices.map(ListedDevice.init))
        print(String(data: data, encoding: .utf8) ?? "[]")
      } catch {
        fail("Could not encode physical output capabilities: \(error.localizedDescription)")
      }
      return
    }

    if devices.isEmpty {
      print("Physical output devices: (none connected)")
      return
    }
    print("Physical output devices (\(devices.count)):")
    for device in devices {
      let capabilities = device.physicalOutputCapabilities
      print("  \(device.name) (\(hex(device.vendorID)):\(hex(device.productID)))")
      print("    device   : \(device.runtimeIdentifier)")
      print("    motors   : \(names(capabilities.rumbleMotors.map(\.rawValue)))")
      print("    lighting : \(names(capabilities.lightingFeatures.map(\.rawValue)))")
      print("    binary   : \(names(capabilities.binaryRumbleMotors.map(\.rawValue)))")
      print("    evidence : \(capabilities.evidence.rawValue)")
    }
  }

  private func rumble(arguments: [String]) {
    let parsed = parseDeviceOption(arguments)
    let arguments = parsed.arguments
    guard arguments.count >= 2 else {
      printHelp()
      exit(1)
    }
    let vendorID = parseIdentifier(arguments[0], label: "VID")
    let productID = parseIdentifier(arguments[1], label: "PID")
    var left = UInt8(180)
    var right = UInt8(180)
    var lt = UInt8(0)
    var rt = UInt8(0)
    var durationMs = 450
    var index = 2
    while index < arguments.count {
      guard index + 1 < arguments.count else {
        fail("Missing value for \(arguments[index])")
      }
      let option = arguments[index]
      let value = parseInteger(arguments[index + 1], label: option)
      switch option {
      case "--left": left = parseIntensity(value, label: option)
      case "--right": right = parseIntensity(value, label: option)
      case "--lt": lt = parseIntensity(value, label: option)
      case "--rt": rt = parseIntensity(value, label: option)
      case "--duration-ms":
        guard (0...5_000).contains(value) else {
          fail("--duration-ms must be 0...5000")
        }
        durationMs = value
      default: fail("Unknown rumble option: \(option)")
      }
      index += 2
    }

    let device = requireDevice(
      vendorID: vendorID,
      productID: productID,
      runtimeIdentifier: parsed.runtimeIdentifier
    )
    let capabilities = device.physicalOutputCapabilities
    guard capabilities.supportsRumble else {
      fail("The selected controller has no physical rumble implementation.")
    }
    if lt > 0 && !capabilities.rumbleMotors.contains(.leftTrigger) {
      fail("The selected controller does not expose a left trigger motor.")
    }
    if rt > 0 && !capabilities.rumbleMotors.contains(.rightTrigger) {
      fail("The selected controller does not expose a right trigger motor.")
    }

    let rumbleLeft = left
    let rumbleRight = right
    let rumbleLT = lt
    let rumbleRT = rt
    let rumbleDurationMs = durationMs
    let client = ApplicationServiceClient()
    client.connect()
    defer { client.disconnect() }
    let sent: Bool? = runSyncOptionalResult(timeout: applicationServiceCallTimeoutSeconds + 5.0) {
      try? await client.sendPhysicalRumble(
        vendorID: vendorID,
        productID: productID,
        runtimeIdentifier: device.runtimeIdentifier,
        left: rumbleLeft,
        right: rumbleRight,
        lt: rumbleLT,
        rt: rumbleRT,
        durationMs: rumbleDurationMs
      )
    }
    guard sent == true else {
      fail("The application service could not send the physical rumble command.")
    }
    print("Physical rumble command sent to \(hex(vendorID)):\(hex(productID)).")
  }

  private func player(arguments: [String]) {
    let parsed = parseDeviceOption(arguments)
    let arguments = parsed.arguments
    guard arguments.count == 3 else {
      printHelp()
      exit(1)
    }
    let vendorID = parseIdentifier(arguments[0], label: "VID")
    let productID = parseIdentifier(arguments[1], label: "PID")
    let indicator: PhysicalPlayerIndicator
    if arguments[2] == "off" {
      indicator = .off
    } else {
      let rawValue = parseInteger(arguments[2], label: "player")
      guard let parsed = PhysicalPlayerIndicator(rawValue: rawValue), parsed != .off else {
        fail("Player must be off, 1, 2, 3, or 4.")
      }
      indicator = parsed
    }

    let device = requireDevice(
      vendorID: vendorID,
      productID: productID,
      runtimeIdentifier: parsed.runtimeIdentifier
    )
    guard device.physicalOutputCapabilities.supportsPlayerIndicator else {
      fail("The selected controller has no source-backed player-indicator implementation.")
    }

    let client = ApplicationServiceClient()
    client.connect()
    defer { client.disconnect() }
    let sent: Bool? = runSyncOptionalResult(timeout: applicationServiceCallTimeoutSeconds) {
      try? await client.setPhysicalPlayerIndicator(
        vendorID: vendorID,
        productID: productID,
        runtimeIdentifier: device.runtimeIdentifier,
        indicator: indicator
      )
    }
    guard sent == true else {
      fail("The application service could not set the physical player indicator.")
    }
    print("Physical player indicator set on \(hex(vendorID)):\(hex(productID)).")
  }

  private func plan(arguments: [String]) {
    let parsed = parseDeviceOption(arguments)
    let json = parsed.arguments.last == "--json"
    let values = json ? Array(parsed.arguments.dropLast()) : parsed.arguments
    guard values.count == 2 else {
      printHelp()
      exit(1)
    }
    let vendorID = parseIdentifier(values[0], label: "VID")
    let productID = parseIdentifier(values[1], label: "PID")
    let device = requireDevice(
      vendorID: vendorID,
      productID: productID,
      runtimeIdentifier: parsed.runtimeIdentifier
    )
    let plan = PhysicalOutputValidationPlan(device: device)
    if json {
      do {
        let data = try plan.encodedJSON()
        print(String(data: data, encoding: .utf8) ?? "{}")
      } catch {
        fail("Could not encode physical output validation plan: \(error.localizedDescription)")
      }
      return
    }
    print("Physical output validation plan for \(hex(vendorID)):\(hex(productID))")
    print("Evidence: \(plan.evidence.rawValue)")
    if plan.steps.isEmpty {
      print("No source-backed physical output steps are available.")
    }
    for (index, step) in plan.steps.enumerated() {
      print("\(index + 1). \(step.id)")
      print("   Run: \(step.command)")
      print("   Expect: \(step.expectedObservation)")
    }
    for note in plan.notes { print("Note: \(note)") }
  }

  private func color(arguments: [String]) {
    let parsed = parseDeviceOption(arguments)
    let arguments = parsed.arguments
    guard arguments.count == 5 else {
      printHelp()
      exit(1)
    }
    let vendorID = parseIdentifier(arguments[0], label: "VID")
    let productID = parseIdentifier(arguments[1], label: "PID")
    let components = zip(["red", "green", "blue"], arguments.dropFirst(2)).map { label, value in
      let parsed = parseInteger(value, label: label)
      guard (0...255).contains(parsed) else { fail("Color components must be 0...255.") }
      return UInt8(parsed)
    }

    let device = requireDevice(
      vendorID: vendorID,
      productID: productID,
      runtimeIdentifier: parsed.runtimeIdentifier
    )
    guard device.physicalOutputCapabilities.lightingFeatures.contains(.programmableColor) else {
      fail("The selected controller has no source-backed RGB implementation.")
    }

    let client = ApplicationServiceClient()
    client.connect()
    defer { client.disconnect() }
    let sent: Bool? = runSyncOptionalResult(timeout: applicationServiceCallTimeoutSeconds) {
      try? await client.setPhysicalColor(
        vendorID: vendorID,
        productID: productID,
        runtimeIdentifier: device.runtimeIdentifier,
        red: components[0],
        green: components[1],
        blue: components[2]
      )
    }
    guard sent == true else { fail("The application service could not set physical RGB color.") }
    print("Physical RGB color set on \(hex(vendorID)):\(hex(productID)).")
  }

  private func brightness(arguments: [String]) {
    let parsed = parseDeviceOption(arguments)
    let arguments = parsed.arguments
    guard arguments.count == 3 else {
      printHelp()
      exit(1)
    }
    let vendorID = parseIdentifier(arguments[0], label: "VID")
    let productID = parseIdentifier(arguments[1], label: "PID")
    let rawBrightness = parseInteger(arguments[2], label: "brightness")
    guard (0...255).contains(rawBrightness) else {
      fail("Brightness must be 0...255.")
    }

    let device = requireDevice(
      vendorID: vendorID,
      productID: productID,
      runtimeIdentifier: parsed.runtimeIdentifier
    )
    guard device.physicalOutputCapabilities.supportsProgrammableBrightness else {
      fail("The selected controller has no source-backed brightness implementation.")
    }

    let client = ApplicationServiceClient()
    client.connect()
    defer { client.disconnect() }
    let sent: Bool? = runSyncOptionalResult(timeout: applicationServiceCallTimeoutSeconds) {
      try? await client.setPhysicalBrightness(
        vendorID: vendorID,
        productID: productID,
        runtimeIdentifier: device.runtimeIdentifier,
        brightness: UInt8(rawBrightness)
      )
    }
    guard sent == true else {
      fail("The application service could not set physical LED brightness.")
    }
    print("Physical LED brightness set on \(hex(vendorID)):\(hex(productID)).")
  }

  private func connectedDevices() -> [ApplicationServiceDeviceDescription] {
    let client = ApplicationServiceClient()
    client.connect()
    defer { client.disconnect() }
    guard let status: ApplicationServiceStatusPayload = runSyncOptionalResult(
      timeout: applicationServiceCallTimeoutSeconds,
      { try? await client.getStatus() }
    ) else {
      fail("The application service is unavailable.")
    }
    return status.connectedDevices
  }

  private func requireDevice(
    vendorID: UInt16,
    productID: UInt16,
    runtimeIdentifier: String?
  ) -> ApplicationServiceDeviceDescription {
    do {
      return try ConnectedControllerSelection.resolve(
        devices: connectedDevices(),
        vendorID: vendorID,
        productID: productID,
        runtimeIdentifier: runtimeIdentifier
      )
    } catch {
      fail(error.localizedDescription)
    }
  }

  private func parseDeviceOption(
    _ arguments: [String]
  ) -> (arguments: [String], runtimeIdentifier: String?) {
    var values: [String] = []
    var runtimeIdentifier: String?
    var index = 0
    while index < arguments.count {
      if arguments[index] == "--device" {
        guard runtimeIdentifier == nil, index + 1 < arguments.count else {
          fail("--device requires one unique identifier from controller output list.")
        }
        let identifier = arguments[index + 1]
        guard !identifier.isEmpty, !identifier.hasPrefix("--") else {
          fail("--device requires one unique identifier from controller output list.")
        }
        runtimeIdentifier = identifier
        index += 2
      } else {
        values.append(arguments[index])
        index += 1
      }
    }
    return (values, runtimeIdentifier)
  }

  private func parseIdentifier(_ value: String, label: String) -> UInt16 {
    let radix = value.lowercased().hasPrefix("0x") ? 16 : 10
    let digits = radix == 16 ? String(value.dropFirst(2)) : value
    guard let parsed = UInt16(digits, radix: radix) else {
      fail("\(label) must be a decimal or 0x-prefixed 16-bit value.")
    }
    return parsed
  }

  private func parseInteger(_ value: String, label: String) -> Int {
    guard let parsed = Int(value) else {
      fail("\(label) must be an integer.")
    }
    return parsed
  }

  private func parseIntensity(_ value: Int, label: String) -> UInt8 {
    guard (0...255).contains(value) else {
      fail("\(label) must be 0...255.")
    }
    return UInt8(value)
  }

  private func names(_ values: [String]) -> String {
    values.isEmpty ? "none" : values.joined(separator: ",")
  }

  private func hex(_ value: UInt16) -> String {
    String(format: "%04x", value)
  }

  private func fail(_ message: String) -> Never {
    CLIOutput.error(message)
    exit(1)
  }

  private func printHelp() {
    print(
      """
      Usage: OpenJoystickDriver --headless controller output <command>

      Commands:
        list [--json]
        rumble <vid> <pid> [--device <id>] [--left 0...255] [--right 0...255]
               [--lt 0...255] [--rt 0...255] [--duration-ms 0...5000]
        player <vid> <pid> off|1|2|3|4 [--device <id>]
        brightness <vid> <pid> 0...255 [--device <id>]
        color <vid> <pid> <red 0...255> <green 0...255> <blue 0...255> [--device <id>]
        plan <vid> <pid> [--device <id>] [--json]

      VID and PID accept decimal values or a 0x prefix. Output commands write to
      connected physical hardware and reject capabilities the active parser does
      not implement. When identical models are connected, pass the opaque device
      identifier printed by controller output list.
      """
    )
  }
}
