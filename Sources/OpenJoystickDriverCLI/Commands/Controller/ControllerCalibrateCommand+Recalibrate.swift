public import ArgumentParser
import Foundation
public import OpenJoystickDriverKit

/// What `ojd controller calibrate` does with its action argument.
enum ControllerCalibrateAction: String, CaseIterable, ExpressibleByArgument {
  /// Starts collecting gyro drift.
  case start
  /// Stops collecting gyro drift.
  case pause
  /// Clears the stored stick and trigger calibration and the gyro offset.
  case reset
  /// Measures stick centres, stick ranges, and trigger ends.
  case sticks

  /// The motion calibration command of a gyro action; nil for the stick and reset actions.
  var motion: RemappingMotionCalibrationCommand? {
    switch self {
    case .start: .start
    case .pause: .pause
    case .reset, .sticks: nil
    }
  }

  /// The lowercase spelling of a case, such as `sticks`.
  init?(argument: String) {
    guard let value = CommandLineName.value(of: argument, in: Self.self) else { return nil }
    self = value
  }

  /// The spellings that the command line accepts.
  static var allValueStrings: [String] { allCases.map { CommandLineName.kebab($0.rawValue) } }
}

extension ControllerCalibration.Step: ExpressibleByArgument {
  /// The lowercase spelling of a case, such as `circle`.
  public init?(argument: String) {
    guard let value = CommandLineName.value(of: argument, in: Self.self) else { return nil }
    self = value
  }

  /// The spellings that the command line accepts.
  public static var allValueStrings: [String] {
    allCases.map { CommandLineName.kebab($0.rawValue) }
  }
}

/// The `--json` result of `ojd controller calibrate` with `sticks` or `reset`.
struct ControllerRecalibrationReport: Encodable, Equatable {
  /// The session ID of the controller.
  let controller: String
  /// The step that ran, or `reset`.
  let action: String
  /// The values a step stored, by tuning key.
  let stored: [String: Double]
  /// The tuning keys a reset removed.
  let cleared: [String]
  /// The controls that did not move enough to measure.
  let unmoved: [String]
  /// Whether a reset cleared the gyro offset.
  let gyroOffsetCleared: Bool

  /// Creates the report from the service's result.
  init(controller: String, _ result: ControllerRecalibrationResult) {
    self.controller = controller
    action = result.action.rawValue
    stored = Dictionary(
      uniqueKeysWithValues: result.stored.values.map { ($0.key.rawValue, $0.value) }
    )
    cleared = result.cleared.map(\.rawValue).sorted()
    unmoved = result.unmoved.map(\.rawValue)
    gyroOffsetCleared = result.gyroOffsetCleared
  }
}

extension ControllerCalibrateCommand {
  /// How long a human run waits after it prints a step's instruction, in nanoseconds.
  private static let leadInNanoseconds: UInt64 = 3_000_000_000

  /// Runs the stick steps, or the reset, and prints what each stored or cleared.
  func recalibrate() async throws {
    try await global.run {
      let selector = controller
      let actions: [ControllerRecalibrationAction] =
        action == .reset
        ? [.reset]
        : (step.map { [$0] } ?? ControllerCalibration.Step.allCases).map(
          ControllerRecalibrationAction.init
        )
      let device = try await ServiceConnection.request { client in
        try await selector.resolve(with: client)
      }
      for recalibration in actions {
        if recalibration.step != nil, CLIContext.current.format == .human {
          CLIOutput.stdout(Self.instruction(for: recalibration))
          try await Task.sleep(nanoseconds: Self.leadInNanoseconds)
        }
        let result = try await ServiceConnection.request { client in
          try await client.recalibrateController(
            .session(device.sessionToken),
            action: recalibration
          )
        }
        try Self.report(result, of: device)
      }
    }
  }

  /// The instruction a step prints before it reads input.
  private static func instruction(for action: ControllerRecalibrationAction) -> String {
    switch action {
    case .rest: CLILocalized.text("cli.controller.calibrate.stepRest")
    case .circle: CLILocalized.text("cli.controller.calibrate.stepCircle")
    case .triggers, .reset: CLILocalized.text("cli.controller.calibrate.stepTriggers")
    }
  }

  /// Prints `result` in the output format, or throws the failure it names.
  private static func report(
    _ result: ControllerRecalibrationResult,
    of device: ApplicationServiceDeviceDescription
  ) throws {
    if let failure = result.failure { throw Self.failure(failure, result.detail, device: device) }
    let report = ControllerRecalibrationReport(controller: device.sessionToken.rawValue, result)
    switch CLIContext.current.format {
    case .json: try CLIOutput.json(report, kind: "Recalibration")
    case .plain:
      CLIOutput.plain([
        [
          report.controller, report.action, report.stored.keys.sorted().joined(separator: ","),
          report.cleared.joined(separator: ","), report.unmoved.joined(separator: ","),
          String(report.gyroOffsetCleared),
        ]
      ])
    case .human:
      if result.action == .reset {
        CLIOutput.stdout(CLILocalized.format("cli.controller.calibrate.resetDone", device.name))
      } else if !report.stored.isEmpty {
        CLIOutput.stdout(
          CLILocalized.format(
            "cli.controller.calibrate.stored",
            device.name,
            report.action,
            report.stored.keys.sorted().joined(separator: ", ")
          )
        )
      }
      if !report.unmoved.isEmpty {
        CLIOutput.stdout(
          CLILocalized.format(
            "cli.controller.calibrate.unmoved",
            device.name,
            report.unmoved.joined(separator: ", ")
          )
        )
      }
    }
  }

  /// The failure of a refused recalibration, named for the controller.
  private static func failure(
    _ failure: ControllerRecalibrationFailure,
    _ detail: String?,
    device: ApplicationServiceDeviceDescription
  ) -> CLIFailure {
    switch failure {
    case .controllerUnavailable:
      CLIFailure(.notFound, CLILocalized.format("cli.controller.calibrate.gone", device.name))
    case .noRecord:
      CLIFailure(
        .notFound,
        CLILocalized.format("cli.config.group.noRecord", device.identity, device.identity)
      )
    case .invalidRecord, .persistenceFailed:
      CLIFailure(
        failure == .invalidRecord ? .invalidInputFile : .fileAccessFailed,
        CLILocalized.format("cli.config.group.invalid", "calibration", detail ?? "")
      )
    }
  }
}
