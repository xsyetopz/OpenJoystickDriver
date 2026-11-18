import ArgumentParser
import Foundation
import OpenJoystickDriverKit

/// The `ojd controller check` command: asks for each control a controller declares and reports
/// which ones responded.
struct ControllerCheckCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "check",
    abstract: CLILocalized.text("cli.controller.check.abstract"),
    discussion: CLILocalized.text("cli.controller.check.discussion")
  )

  /// How long a step waits for its control when `--duration` is not given.
  private static let defaultStepSeconds = 15.0

  /// The global options.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  /// The controller to check.
  @Argument(help: controllerArgumentHelp)
  var controller: ControllerSelector

  /// `--duration`: skip a control after this many seconds without a move.
  @Option(
    help: ArgumentHelp(CLILocalized.text("cli.controller.check.duration"), valueName: "seconds")
  )
  var duration: Double?

  /// `--validate`: offer the validation form after a check in which every control responded.
  @Flag(
    name: .customLong("validate"),
    help: ArgumentHelp(CLILocalized.text("cli.controller.check.validate"))
  )
  var offersValidation = false

  /// Checks the duration.
  func validate() throws { try validateDuration(duration) }

  /// Runs the command.
  func run() async throws {
    try await global.run {
      try await withController(controller) { client, device in
        let check = try await runCheck(client, device)
        switch CLIContext.current.format {
        case .json: try CLIOutput.json(check)
        case .plain:
          CLIOutput.plain(
            check.steps.map {
              [$0.control, CommandLineName.kebab($0.outcome.rawValue), $0.otherControl ?? ""]
            }
          )
        case .human:
          for step in check.steps {
            CLIOutput.stdout(
              "\(step.control): \(CommandLineName.kebab(step.outcome.rawValue))"
                + (step.otherControl.map { " (\($0))" } ?? "")
            )
          }
        }
        if offersValidation { try offerValidation(check) }
      }
    }
  }

  /// Asks for each control in turn and returns the finished document.
  private func runCheck(
    _ client: ApplicationServiceClient,
    _ device: ApplicationServiceDeviceDescription
  ) async throws -> ControllerCheck {
    let controls = ControllerCheckControl.steps(for: device.capabilities)
    guard !controls.isEmpty else {
      throw CLIFailure(
        .aborted,
        CLILocalized.format("cli.controller.check.noControls", device.name)
      )
    }
    let timeout = CLIContext.current.requestTimeout
    var run = ControllerCheckRun(controls: controls)
    while let current = run.current {
      CLIOutput.stderr(
        CLILocalized.format(
          "cli.controller.check.step",
          String(run.results.count + 1),
          String(controls.count),
          current.id
        )
      )
      let settled = try await pollController(duration: duration ?? Self.defaultStepSeconds) {
        guard
          let state = try await ServiceConnection.withDeadline(
            seconds: timeout,
            { try await client.controllerState(for: .session(device.sessionToken)) }
          )
        else { return false }
        let finished = run.results.count
        run.observe(state)
        return run.results.count > finished
      }
      if !settled { run.skip() }
    }
    let record = RecordStore.load().records[
      ControllerModelID(vendorID: device.vendorID, productID: device.productID)
    ]
    return ControllerCheck(device: device, record: record, steps: run.results)
  }

  /// Prints the validation text and the form address, and opens the form after a typed `y`.
  private func offerValidation(_ check: ControllerCheck) throws {
    guard let text = ControllerCheckIssue.validationText(for: check) else {
      CLIOutput.stderr(CLILocalized.text("cli.controller.check.validateUnavailable"))
      return
    }
    let url = ControllerCheckIssue.validationURL(for: check)
    CLIOutput.stderr(
      CLILocalized.format("cli.controller.check.validateText", ControllerCheckIssue.destination)
    )
    CLIOutput.stderr(text)
    CLIOutput.stderr(
      CLILocalized.format("cli.controller.check.validateAddress", url.absoluteString)
    )
    guard CLITerminal.canPrompt() else {
      CLIOutput.stderr(CLILocalized.text("cli.controller.check.validateNotOpened"))
      return
    }
    try CLITerminal.confirm(CLILocalized.text("cli.controller.check.validateOpen"), force: false)
    let open = Process()
    open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    open.arguments = [url.absoluteString]
    try open.run()
  }
}
