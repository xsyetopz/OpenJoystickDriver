import ArgumentParser
import Foundation
import OpenJoystickDriverKit

struct ControllerCalibrateCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "calibrate",
    abstract: CLILocalized.text(
      "cli.controller.calibrate.abstract",
      "Show or change a controller's motion calibration."
    ),
    discussion: CLILocalized.text(
      "cli.controller.calibrate.discussion",
      "Without an action, prints the calibration. start collects gyro drift while the "
        + "controller lies still, pause stops collecting, and reset forgets the calibration. "
        + "Motion lean and steering bindings use the calibration."
    )
  )

  /// The `--json` result.
  struct Result: Encodable, Equatable {
    struct Offset: Encodable, Equatable {
      let x: Double
      let y: Double
      let z: Double
    }

    let controller: String
    let calibrated: Bool
    let collecting: Bool
    let offsetDegreesPerSecond: Offset
  }

  @Argument(help: controllerArgumentHelp)
  var controller: ControllerSelector

  @Argument(
    help: ArgumentHelp(
      CLILocalized.text(
        "cli.controller.calibrate.action",
        "What to do: start, pause, or reset. Omit it to print the calibration."
      ),
      valueName: "action"
    )
  )
  var action: RemappingMotionCalibrationCommand?

  @OptionGroup
  var global: GlobalOptions

  func run() async throws {
    try await global.run {
      let (selector, action) = (controller, action)
      let (device, status) = try await ServiceConnection.request { client in
        let device = try await selector.resolve(with: client)
        do {
          return (
            device,
            try await client.remappingMotionCalibration(
              runtimeIdentifier: device.runtimeIdentifier,
              command: action
            )
          )
        } catch let error as RemappingMotionCalibrationError {
          throw Self.failure(error, device: device)
        }
      }
      let offset = status.offsetDegreesPerSecond
      let result = Result(
        controller: device.runtimeIdentifier,
        calibrated: status.hasMotionBaseline,
        collecting: status.isCollecting,
        offsetDegreesPerSecond: Result.Offset(x: offset.x, y: offset.y, z: offset.z)
      )
      switch CLIContext.current.format {
      case .json: try CLIOutput.json(result)
      case .plain:
        CLIOutput.plain([
          [
            result.controller, String(result.calibrated), String(result.collecting),
            String(offset.x), String(offset.y), String(offset.z),
          ]
        ])
      case .human:
        let state =
          status.isCollecting
          ? CLILocalized.text("cli.controller.calibrate.collecting", "collecting")
          : status.hasMotionBaseline
            ? CLILocalized.text("cli.controller.calibrate.calibrated", "calibrated")
            : CLILocalized.text("cli.controller.calibrate.uncalibrated", "not calibrated")
        CLIOutput.stdout(
          CLILocalized.format(
            "cli.controller.calibrate.status",
            "%@: %@, gyro offset x %@ y %@ z %@ degrees per second",
            device.name,
            state,
            String(format: "%.3f", offset.x),
            String(format: "%.3f", offset.y),
            String(format: "%.3f", offset.z)
          )
        )
      }
    }
  }

  static func failure(
    _ error: RemappingMotionCalibrationError,
    device: ApplicationServiceDeviceDescription
  ) -> CLIFailure {
    switch error {
    case .controllerUnavailable:
      CLIFailure(
        ApplicationServiceRemappingRPCError.Code.controllerUnavailable.errorCode,
        CLILocalized.format(
          "cli.controller.calibrate.unavailable",
          "%@ has no active remapping session. Activate a profile for it with "
            + "'ojd profile activate'.",
          device.name
        )
      )
    case .motionUnavailable:
      CLIFailure(
        ApplicationServiceRemappingRPCError.Code.motionUnavailable.errorCode,
        CLILocalized.format(
          "cli.controller.calibrate.no_motion",
          "%@ does not report motion.",
          device.name
        )
      )
    }
  }
}

/// The `--json` result of `ojd controller pair` and `unpair`.
struct JoyConPairResult: Encodable, Equatable {
  let session: String
  let left: String
  let right: String
  let profile: String
  let gyro: String

  init(_ pair: ApplicationServiceJoyConPairPayload) {
    session = pair.sessionID.uuidString
    left = pair.leftRuntimeIdentifier
    right = pair.rightRuntimeIdentifier
    profile = pair.profileName
    gyro = pair.gyroSelection.rawValue
  }

  var row: [String] { [session, left, right, profile, gyro] }
}

struct ControllerPairCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "pair",
    abstract: CLILocalized.text(
      "cli.controller.pair.abstract",
      "Combine a left and a right Joy-Con into one controller."
    ),
    discussion: CLILocalized.text(
      "cli.controller.pair.discussion",
      "The pair uses PROFILE, which must be a paired Joy-Con profile. 'ojd controller unpair' "
        + "separates them again."
    )
  )

  @Argument(
    help: ArgumentHelp(
      CLILocalized.text("cli.controller.pair.left", "The left Joy-Con."),
      valueName: "left"
    )
  )
  var left: ControllerSelector

  @Argument(
    help: ArgumentHelp(
      CLILocalized.text("cli.controller.pair.right", "The right Joy-Con."),
      valueName: "right"
    )
  )
  var right: ControllerSelector

  @Option(help: profileArgumentHelp)
  var profile: ProfileSelector

  @OptionGroup
  var global: GlobalOptions

  func run() async throws {
    try await global.run {
      let (left, right, selector) = (left, right, profile)
      let (leftID, rightID, snapshot) = try await ServiceConnection.request { client in
        let leftDevice = try await left.resolve(with: client)
        let rightDevice = try await right.resolve(with: client)
        let (profile, _) = try await selector.resolve(with: client)
        let snapshot = try await client.pairRemappingJoyCons(
          leftRuntimeIdentifier: leftDevice.runtimeIdentifier,
          rightRuntimeIdentifier: rightDevice.runtimeIdentifier,
          profileID: profile.id
        )
        return (leftDevice.runtimeIdentifier, rightDevice.runtimeIdentifier, snapshot)
      }
      guard
        let pair = snapshot.joyConPairs.first(where: {
          $0.leftRuntimeIdentifier == leftID && $0.rightRuntimeIdentifier == rightID
        })
      else {
        throw CLIFailure(
          .serviceRequestFailed,
          CLILocalized.text(
            "cli.controller.pair.missing",
            "The service did not pair the Joy-Cons. Check them with 'ojd controller list'."
          )
        )
      }
      try Self.print(
        JoyConPairResult(pair),
        message: CLILocalized.format(
          "cli.controller.pair.done",
          "Paired the Joy-Cons as %@ with '%@'.",
          pair.sessionID.uuidString,
          pair.profileName
        )
      )
    }
  }

  static func print(_ result: JoyConPairResult, message: String) throws {
    switch CLIContext.current.format {
    case .json: try CLIOutput.json(result)
    case .plain: CLIOutput.plain([result.row])
    case .human: CLIOutput.success(message)
    }
  }
}

struct ControllerUnpairCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "unpair",
    abstract: CLILocalized.text(
      "cli.controller.unpair.abstract",
      "Separate a Joy-Con pair into two controllers."
    )
  )

  @Argument(
    help: ArgumentHelp(
      CLILocalized.text(
        "cli.controller.unpair.pair",
        "The pair: its session ID from 'ojd controller pair', or the ID of either Joy-Con."
      ),
      valueName: "pair"
    )
  )
  var pair: String

  @OptionGroup
  var global: GlobalOptions

  func run() async throws {
    try await global.run {
      let text = pair
      let removed = try await ServiceConnection.request { client in
        let snapshot = try await client.getRemappingSnapshot()
        guard
          let pair = snapshot.joyConPairs.first(where: {
            $0.sessionID.uuidString.caseInsensitiveCompare(text) == .orderedSame
              || $0.leftRuntimeIdentifier == text || $0.rightRuntimeIdentifier == text
          })
        else {
          throw CLIFailure(
            .notFound,
            CLILocalized.format(
              "cli.controller.unpair.not_found",
              "No Joy-Con pair matches '%@'.",
              text
            )
          )
        }
        _ = try await client.unpairRemappingJoyCons(sessionID: pair.sessionID)
        return pair
      }
      try ControllerPairCommand.print(
        JoyConPairResult(removed),
        message: CLILocalized.text("cli.controller.unpair.done", "Separated the Joy-Cons.")
      )
    }
  }
}
