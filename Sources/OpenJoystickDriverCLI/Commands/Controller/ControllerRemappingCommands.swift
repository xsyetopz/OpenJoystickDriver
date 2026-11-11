import ArgumentParser
import Foundation
import OpenJoystickDriverKit

/// The `ojd controller calibrate` command: shows the motion calibration of a controller with a
/// gyro, and starts, pauses or resets it.
struct ControllerCalibrateCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "calibrate",
    abstract: CLILocalized.text(
      "cli.controller.calibrate.abstract"
    ),
    discussion: CLILocalized.text(
      "cli.controller.calibrate.discussion"
    )
  )

  /// The `--json` result.
  struct Result: Encodable, Equatable {
    /// The gyro offset of the calibration.
    struct Offset: Encodable, Equatable {
      /// The offset around the x axis, in degrees per second.
      let x: Double
      /// The offset around the y axis, in degrees per second.
      let y: Double
      /// The offset around the z axis, in degrees per second.
      let z: Double
    }

    /// The session ID of the controller.
    let controller: String
    /// Whether the controller has a calibration.
    let calibrated: Bool
    /// Whether the service is collecting gyro drift.
    let collecting: Bool
    /// The gyro offset of the calibration.
    let offsetDegreesPerSecond: Offset
  }

  /// The controller to calibrate.
  @Argument(help: controllerArgumentHelp)
  var controller: ControllerSelector

  /// The action: `start`, `pause` or `reset`; without one the command only shows the calibration.
  @Argument(
    help: ArgumentHelp(
      CLILocalized.text(
        "cli.controller.calibrate.action"
      ),
      valueName: "action"
    )
  )
  var action: RemappingMotionCalibrationCommand?

  /// The global options.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  /// Runs the command.
  func run() async throws {
    try await global.run {
      let (selector, action) = (controller, action)
      let (device, status) = try await ServiceConnection.request { client in
        let device = try await selector.resolve(with: client)
        do {
          return (
            device,
            try await client.remappingMotionCalibration(
              for: .session(device.sessionToken),
              command: action
            )
          )
        } catch let error as ApplicationServiceRemappingRPCError {
          throw Self.failure(error, device: device)
        }
      }
      let offset = status.offsetDegreesPerSecond
      let result = Result(
        controller: device.sessionToken.rawValue,
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
          ? CLILocalized.text("cli.controller.calibrate.collecting")
          : status.hasMotionBaseline
            ? CLILocalized.text("cli.controller.calibrate.calibrated")
            : CLILocalized.text("cli.controller.calibrate.uncalibrated")
        CLIOutput.stdout(
          CLILocalized.format(
            "cli.controller.calibrate.status",
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

  /// The service's calibration refusals, named for the controller; other rejections keep the
  /// shared service-failure text.
  static func failure(
    _ error: ApplicationServiceRemappingRPCError,
    device: ApplicationServiceDeviceDescription
  ) -> any Error {
    let id = error.code.errorCode
    switch error.code {
    case .controllerUnavailable:
      return CLIFailure(
        id,
        CLILocalized.format(
          "cli.controller.calibrate.unavailable",
          device.name
        )
      )
    case .motionUnavailable:
      return CLIFailure(
        id,
        CLILocalized.format(
          "cli.controller.calibrate.noMotion",
          device.name
        )
      )
    case .motionGyroNotSelected, .motionProfileInactive, .motionSessionChanged:
      return CLIFailure(id, id.localizedExplanation)
    default: return ServiceConnection.failure(for: error)
    }
  }
}

/// The `--json` result of `ojd controller pair` and `unpair`.
struct JoyConPairResult: Encodable, Equatable {
  /// The session ID of the pair.
  let session: String
  /// The ID of the left Joy-Con.
  let left: String
  /// The ID of the right Joy-Con.
  let right: String
  /// The name of the profile that the pair uses.
  let profile: String
  /// Which Joy-Con supplies the gyro.
  let gyro: String

  /// Creates the result from the service's `pair`.
  init(_ pair: ApplicationServiceJoyConPairPayload) {
    session = pair.sessionID.uuidString
    left = pair.left.rawValue
    right = pair.right.rawValue
    profile = pair.profileName
    gyro = pair.gyroSelection.rawValue
  }

  /// The `--plain` row of the result.
  var row: [String] { [session, left, right, profile, gyro] }
}

/// The `ojd controller pair` command: combines a left and a right Joy-Con into one controller that
/// uses a profile.
struct ControllerPairCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "pair",
    abstract: CLILocalized.text(
      "cli.controller.pair.abstract"
    ),
    discussion: CLILocalized.text(
      "cli.controller.pair.discussion"
    )
  )

  /// The left Joy-Con.
  @Argument(
    help: ArgumentHelp(
      CLILocalized.text("cli.controller.pair.left"),
      valueName: "left"
    )
  )
  var left: ControllerSelector

  /// The right Joy-Con.
  @Argument(
    help: ArgumentHelp(
      CLILocalized.text("cli.controller.pair.right"),
      valueName: "right"
    )
  )
  var right: ControllerSelector

  /// `--profile`: the paired Joy-Con profile that the pair uses.
  @Option(help: profileArgumentHelp)
  var profile: ProfileSelector

  /// The global options.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  /// Runs the command.
  func run() async throws {
    try await global.run {
      let (left, right, selector) = (left, right, profile)
      let (leftID, rightID, snapshot) = try await ServiceConnection.request { client in
        let leftDevice = try await left.resolve(with: client)
        let rightDevice = try await right.resolve(with: client)
        let (profile, _) = try await selector.resolve(with: client)
        let snapshot = try await client.pairRemappingJoyCons(
          left: .session(leftDevice.sessionToken),
          right: .session(rightDevice.sessionToken),
          profileID: profile.id
        )
        return (leftDevice.sessionToken, rightDevice.sessionToken, snapshot)
      }
      guard
        let pair = snapshot.joyConPairs.first(where: {
          $0.left == leftID && $0.right == rightID
        })
      else {
        throw CLIFailure(
          .serviceRequestFailed,
          CLILocalized.text(
            "cli.controller.pair.missing"
          )
        )
      }
      try Self.print(
        JoyConPairResult(pair),
        message: CLILocalized.format(
          "cli.controller.pair.done",
          pair.sessionID.uuidString,
          pair.profileName
        )
      )
    }
  }

  /// Prints `result` as JSON, as a `--plain` row, or as `message` on stderr.
  static func print(_ result: JoyConPairResult, message: String) throws {
    switch CLIContext.current.format {
    case .json: try CLIOutput.json(result)
    case .plain: CLIOutput.plain([result.row])
    case .human: CLIOutput.success(message)
    }
  }
}

/// The `ojd controller unpair` command: separates a Joy-Con pair.
struct ControllerUnpairCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "unpair",
    abstract: CLILocalized.text(
      "cli.controller.unpair.abstract"
    )
  )

  /// The pair: the session ID that `controller pair` prints, or the ID of either Joy-Con.
  @Argument(
    help: ArgumentHelp(
      CLILocalized.text(
        "cli.controller.unpair.pair"
      ),
      valueName: "pair"
    )
  )
  var pair: String

  /// The global options.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  /// Runs the command.
  func run() async throws {
    try await global.run {
      let text = pair
      let removed = try await ServiceConnection.request { client in
        let snapshot = try await client.getRemappingSnapshot()
        guard
          let pair = snapshot.joyConPairs.first(where: {
            $0.sessionID.uuidString.caseInsensitiveCompare(text) == .orderedSame
              || $0.left.rawValue == text || $0.right.rawValue == text
          })
        else {
          throw CLIFailure(
            .notFound,
            CLILocalized.format(
              "cli.controller.unpair.notFound",
              text
            )
          )
        }
        _ = try await client.unpairRemappingJoyCons(sessionID: pair.sessionID)
        return pair
      }
      try ControllerPairCommand.print(
        JoyConPairResult(removed),
        message: CLILocalized.text("cli.controller.unpair.done")
      )
    }
  }
}
