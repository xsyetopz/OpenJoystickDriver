import CoreHaptics
import ForceFeedback
import Foundation
import GameController
import IOKit
import IOKit.hid
import OpenJoystickDriverKit

private enum ProbeRoute: String {
  case sdl23 = "sdl2-3"
  case forceFeedback = "force-feedback"
  case gameController = "gamecontroller"
}

private enum ProbeError: Error, LocalizedError {
  case invalidArguments
  case routeRejected(ProbeRoute)
  case hapticsUnavailable

  var errorDescription: String? {
    switch self {
    case .invalidArguments: "Invalid arguments. Run with --help for usage."
    case .routeRejected(let route): "OpenJoystickDriver rejected the \(route.rawValue) route."
    case .hapticsUnavailable: "No connected GCController exposes a public haptics engine."
    }
  }
}

private struct Arguments {
  let route: ProbeRoute?
  let pulse: Bool
  let seconds: Int

  init(_ values: [String]) throws {
    if values.isEmpty || values == ["--help"] || values == ["help"] {
      route = nil
      pulse = false
      seconds = 8
      return
    }
    guard values.first == "try", values.count >= 2,
      let parsedRoute = ProbeRoute(rawValue: values[1])
    else { throw ProbeError.invalidArguments }
    route = parsedRoute
    var parsedPulse = false
    var parsedSeconds = 8
    var didParseSeconds = false
    var index = 2
    while index < values.count {
      switch values[index] {
      case "--pulse" where parsedRoute == .gameController && !parsedPulse:
        parsedPulse = true
        index += 1
      case "--seconds" where index + 1 < values.count && !didParseSeconds:
        guard let requested = Int(values[index + 1]) else { throw ProbeError.invalidArguments }
        parsedSeconds = min(60, max(1, requested))
        didParseSeconds = true
        index += 2
      default: throw ProbeError.invalidArguments
      }
    }
    pulse = parsedPulse
    seconds = parsedSeconds
  }
}

private struct HIDSnapshot {
  let service: io_service_t
  let vendorID: Int
  let productID: Int
  let product: String
  let transport: String
  let maxOutputReportSize: Int
  let gameControllerSupported: Bool?
  let forceFeedbackResult: HRESULT
}

private enum HIDInventory {
  static func snapshots() -> [HIDSnapshot] {
    let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    IOHIDManagerSetDeviceMatching(manager, nil)
    guard IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
      return []
    }
    defer { IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone)) }
    let devices = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>) ?? []
    return devices.compactMap(snapshot).sorted {
      ($0.vendorID, $0.productID, $0.product) < ($1.vendorID, $1.productID, $1.product)
    }
  }

  private static func snapshot(_ device: IOHIDDevice) -> HIDSnapshot? {
    guard looksLikeController(device) else { return nil }
    let service = IOHIDDeviceGetService(device)
    let gameControllerSupported: Bool?
    if #available(macOS 11, *) {
      gameControllerSupported = GCController.supportsHIDDevice(device)
    } else {
      gameControllerSupported = nil
    }
    return HIDSnapshot(
      service: service,
      vendorID: integer(device, kIOHIDVendorIDKey),
      productID: integer(device, kIOHIDProductIDKey),
      product: string(device, kIOHIDProductKey) ?? "(unknown)",
      transport: string(device, kIOHIDTransportKey) ?? "(unknown)",
      maxOutputReportSize: integer(device, kIOHIDMaxOutputReportSizeKey),
      gameControllerSupported: gameControllerSupported,
      forceFeedbackResult: FFIsForceFeedback(service)
    )
  }

  private static func looksLikeController(_ device: IOHIDDevice) -> Bool {
    let page = integer(device, kIOHIDPrimaryUsagePageKey)
    let usage = integer(device, kIOHIDPrimaryUsageKey)
    if page == kHIDPage_GenericDesktop,
      usage == kHIDUsage_GD_GamePad || usage == kHIDUsage_GD_Joystick
        || usage == kHIDUsage_GD_MultiAxisController
    {
      return true
    }
    guard
      let pairs = IOHIDDeviceGetProperty(device, kIOHIDDeviceUsagePairsKey as CFString)
        as? [[String: Any]]
    else { return false }
    return pairs.contains { pair in
      guard pair[kIOHIDDeviceUsagePageKey as String] as? Int == kHIDPage_GenericDesktop else {
        return false
      }
      let usage = pair[kIOHIDDeviceUsageKey as String] as? Int
      return usage == kHIDUsage_GD_GamePad || usage == kHIDUsage_GD_Joystick
        || usage == kHIDUsage_GD_MultiAxisController
    }
  }

  private static func integer(_ device: IOHIDDevice, _ key: String) -> Int {
    IOHIDDeviceGetProperty(device, key as CFString) as? Int ?? 0
  }

  private static func string(_ device: IOHIDDevice, _ key: String) -> String? {
    IOHIDDeviceGetProperty(device, key as CFString) as? String
  }
}

private enum Report {
  static func inventory(_ snapshots: [HIDSnapshot]) {
    print("HID controller inventory:")
    if snapshots.isEmpty { print("- none") }
    for snapshot in snapshots {
      let gameController = snapshot.gameControllerSupported.map(String.init) ?? "unavailable"
      let forceFeedback = snapshot.forceFeedbackResult == FF_OK ? "yes" : "no"
      print(
        String(
          format: "- %04X:%04X \"%@\" transport=%@ outputBytes=%d HIDAPI-candidate=%@ "
            + "GameController=%@ ForceFeedback=%@ FFResult=0x%08X",
          snapshot.vendorID,
          snapshot.productID,
          snapshot.product,
          snapshot.transport,
          snapshot.maxOutputReportSize,
          snapshot.maxOutputReportSize > 0 ? "yes" : "no",
          gameController,
          forceFeedback,
          UInt32(bitPattern: snapshot.forceFeedbackResult)
        )
      )
    }
  }

  @available(macOS 11, *) static func gameControllers() {
    let controllers = GCController.controllers()
    print("GameController inventory:")
    if controllers.isEmpty { print("- none") }
    for controller in controllers {
      let haptics = controller.haptics
      let localities =
        haptics?.supportedLocalities.map(\.rawValue).sorted().joined(separator: ",") ?? ""
      print(
        "- vendor=\(controller.vendorName ?? "(unknown)") category=\(controller.productCategory) "
          + "haptics=\(haptics != nil) localities=[\(localities)]"
      )
    }
  }
}

private enum OJDService {
  private static let defaultExecutable =
    "/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver"

  static func select(_ identity: CompatibilityIdentity, route: ProbeRoute) throws {
    let executable = ProcessInfo.processInfo.environment["OJD_EXECUTABLE"] ?? defaultExecutable
    let selection = try run(
      executable: executable,
      arguments: ["--headless", "compat", "set", identity.rawValue]
    )
    guard selection.status == 0 else { throw ProbeError.routeRejected(route) }
    print("Selected OJD identity: \(identity.rawValue)")
    print(selection.output.trimmingCharacters(in: .whitespacesAndNewlines))
    let status = try run(executable: executable, arguments: ["--headless", "app", "status"])
    print(status.output.trimmingCharacters(in: .whitespacesAndNewlines))
  }

  private static func run(executable: String, arguments: [String]) throws -> (
    status: Int32, output: String
  ) {
    let pipe = Pipe()
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    process.waitUntilExit()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    return (process.terminationStatus, String(bytes: data, encoding: .utf8) ?? "")
  }
}

private enum ForceFeedbackProbe {
  static func openCandidates(_ snapshots: [HIDSnapshot]) {
    print("ForceFeedback device-open results:")
    let candidates = snapshots.filter { $0.forceFeedbackResult == FF_OK }
    if candidates.isEmpty {
      print("- none; no current HID service advertises Apple Force Feedback/PID support")
      return
    }
    for candidate in candidates {
      var reference: FFDeviceObjectReference?
      let result = FFCreateDevice(candidate.service, &reference)
      if let reference { _ = FFReleaseDevice(reference) }
      print(
        String(
          format: "- %04X:%04X create=0x%08X",
          candidate.vendorID,
          candidate.productID,
          UInt32(bitPattern: result)
        )
      )
    }
  }
}

@available(macOS 11, *) private enum GameControllerProbe {
  static func pulse() throws {
    guard let controller = GCController.controllers().first(where: { $0.haptics != nil }),
      let haptics = controller.haptics, let engine = haptics.createEngine(withLocality: .default)
    else { throw ProbeError.hapticsUnavailable }
    try engine.start()
    let event = CHHapticEvent(
      eventType: .hapticContinuous,
      parameters: [
        CHHapticEventParameter(parameterID: .hapticIntensity, value: 1),
        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)
      ],
      relativeTime: 0,
      duration: 0.5
    )
    let player = try engine.makePlayer(with: CHHapticPattern(events: [event], parameters: []))
    try player.start(atTime: 0)
    Thread.sleep(forTimeInterval: 0.7)
    engine.stop()
  }
}

private func printUsage() {
  print(
    """
    HapticsBackendProbe

      swift run HapticsBackendProbe try sdl2-3 [--seconds N]
      swift run HapticsBackendProbe try force-feedback [--seconds N]
      swift run HapticsBackendProbe try gamecontroller [--pulse] [--seconds N]

    sdl2-3 selects the hardware-verified 9886:0024 ASTRO identity and exact Xbox 360
    descriptor/report format that SDL2 and SDL3 special-case in their HIDAPI driver.
    force-feedback checks HID PID/Apple Force Feedback acceptance and device creation.
    gamecontroller selects OJD's Apple GameController identity, reports public haptics,
    and optionally sends one CoreHaptics pulse when a GCController haptics engine exists.

    Run only one route at a time. After every run, record whether input, rumble, trigger
    motors, LEDs, reconnect, and application discovery worked before changing routes.
    """
  )
}

@main private enum HapticsBackendProbe {
  static func main() async {
    do {
      let arguments = try Arguments(Array(CommandLine.arguments.dropFirst()))
      guard let route = arguments.route else {
        printUsage()
        return
      }

      let snapshots = HIDInventory.snapshots()
      Report.inventory(snapshots)

      switch route {
      case .sdl23: try OJDService.select(.sdl2_3, route: route)
      case .forceFeedback: ForceFeedbackProbe.openCandidates(snapshots)
      case .gameController:
        guard #available(macOS 11, *) else { throw ProbeError.hapticsUnavailable }
        try OJDService.select(.appleGameController, route: route)
        // GameController publishes connection changes asynchronously after OJD
        // replaces the virtual HID identity. Do not inspect the stale controller.
        try await Task.sleep(nanoseconds: 2_000_000_000)
        Report.gameControllers()
        if arguments.pulse {
          try GameControllerProbe.pulse()
          print("GameController haptic pulse submitted.")
        }
      }

      print("Keeping the selected route observable for \(arguments.seconds)s.")
      try await Task.sleep(nanoseconds: UInt64(arguments.seconds) * 1_000_000_000)
      print("Probe complete. Report physical behavior before another run.")
    } catch {
      fputs("error: \(error.localizedDescription)\n", stderr)
      exit(1)
    }
  }
}
