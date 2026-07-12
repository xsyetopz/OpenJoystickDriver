import Foundation

struct BrowserGamepadDiagnosticCommand {
  private struct Options {
    var port = 8_765
    var seconds = 300
    var browser = BrowserGamepadTarget.none
    var outputPath: String?
  }

  func run(arguments: [String]) {
    let options = parse(arguments)
    let session: BrowserGamepadDiagnosticSession
    do {
      session = try BrowserGamepadDiagnosticService.start(port: options.port)
    } catch {
      fail("Could not start the local server: \(error.localizedDescription)")
    }
    defer { session.stop() }

    print("Browser Gamepad diagnostic")
    print("  URL      : \(session.url.absoluteString)")
    print("  Duration : \(options.seconds) seconds")
    print("  Identity : set separately with '--headless compat <identity>'")
    print("")
    print("Keep the page focused, press a controller control once, then:")
    print("  1. Check ID, mapping, button/axis counts, and duplicate instances.")
    print("  2. Run the hands-off idle sample for misfires and frame stalls.")
    print("  3. Test only haptic effects the browser reports as supported.")
    print("  4. Submit locally, copy, or download JSON; review it before sharing.")

    for warning in BrowserGamepadDiagnosticService.open(session.url, target: options.browser) {
      print("WARNING: \(warning)")
    }

    let deadline = Date().addingTimeInterval(TimeInterval(options.seconds))
    while Date() < deadline {
      Thread.sleep(forTimeInterval: 0.25)
    }
    let count = session.snapshotCount
    print("Submitted browser snapshots: \(count)")
    if let outputPath = options.outputPath {
      do {
        try session.encodedSnapshots().write(
          to: URL(fileURLWithPath: outputPath),
          options: .atomic
        )
        print("Browser snapshots written to \(outputPath)")
      } catch {
        fail("Could not write browser snapshots: \(error.localizedDescription)")
      }
    }
    print("Browser Gamepad diagnostic server stopped.")
  }

  private func parse(_ arguments: [String]) -> Options {
    var options = Options()
    var index = 0
    while index < arguments.count {
      let argument = arguments[index]
      if ["--help", "-h", "help"].contains(argument) {
        printHelp()
        exit(0)
      }
      guard index + 1 < arguments.count else {
        fail("Missing value for \(argument).")
      }
      let value = arguments[index + 1]
      switch argument {
      case "--port":
        guard let port = Int(value), (1...65_535).contains(port) else {
          fail("--port must be 1...65535.")
        }
        options.port = port
      case "--seconds":
        guard let seconds = Int(value), (1...3_600).contains(seconds) else {
          fail("--seconds must be 1...3600.")
        }
        options.seconds = seconds
      case "--open":
        guard let browser = BrowserGamepadTarget(rawValue: value) else {
          fail("--open must be none, default, safari, chrome, firefox, or all.")
        }
        options.browser = browser
      case "--output":
        guard !value.isEmpty else { fail("--output must not be empty.") }
        options.outputPath = value
      default:
        fail("Unknown browser-gamepad option: \(argument)")
      }
      index += 2
    }
    return options
  }

  private func fail(_ message: String) -> Never {
    print("ERROR: \(message)")
    exit(1)
  }

  private func printHelp() {
    print(
      """
      Usage: OpenJoystickDriver --headless diagnose browser-gamepad
             [--port 1...65535] [--seconds 1...3600]
             [--open none|default|safari|chrome|firefox|all]
             [--output snapshots.json]

      Serves a local, privacy-reviewable Gamepad API page for comparing Blink,
      Gecko, and WebKit. The command does not change the active compatibility
      identity. Snapshot submission stays on loopback and occurs only when the
      page button is pressed. Browser launch, file export, and haptic writes occur
      only when explicitly requested.
      """
    )
  }
}
