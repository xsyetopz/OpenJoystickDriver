import Foundation

/// One output command and the words that name it in a failure.
public struct ControllerOutputRequest: Sendable {
  /// The name of the command in a failure message and in a report.
  public let name: String
  /// The command to send.
  public let command: ControllerOutputCommand
  /// The feature in a failure message, such as rumble.
  public let feature: String

  /// Creates a request.
  public init(name: String, command: ControllerOutputCommand, feature: String) {
    self.name = name
    self.command = command
    self.feature = feature
  }
}

/// One output command and what happened to it, in `ojd controller rumble --json` and the endpoint
/// `OutputResult` line.
public struct ControllerOutputEntry: Encodable, Equatable, Sendable {
  /// The output command that the service received.
  public let command: String
  /// How the controller took the command.
  public let outcome: String
  /// The rumble channels that the controller dropped because it lacks them.
  public let droppedRumbleChannels: [String]

  /// Reports what became of `request`.
  public init(_ request: ControllerOutputRequest, _ result: ControllerOutputResult) {
    command = request.name
    outcome = result.outcome.rawValue
    droppedRumbleChannels = result.droppedRumbleChannels.map(\.rawValue)
  }
}

/// The rumble motors of a delivered rumble command.
public struct ControllerRumbleOutcome: Equatable, Sendable {
  /// The requested trigger motors that the controller lacks.
  public let droppedTriggers: [PhysicalRumbleMotor]
  /// The requested motors that ran.
  public let ran: [PhysicalRumbleMotor]
}

/// The output requests of `ojd controller rumble`, `player`, and `light`, which the endpoint and
/// the App Intents send too, so that an output the controller lacks fails with the same code.
public enum ControllerOutput {
  /// The catalog resolver for the preferred languages of the process.
  private static let localization = Localization()

  /// Whether `seconds` is a rumble duration above zero and within the maximum.
  public static func isValidRumbleDuration(_ seconds: Double) -> Bool {
    seconds.isFinite && seconds > 0 && seconds <= RumbleDuration.maximumSeconds
  }

  /// The request that runs `intensities` for `seconds`, or stops the rumble when no motor is named.
  ///
  /// Main-motor requests are mirrored onto trackpad haptics.
  public static func rumble(
    _ intensities: RumbleIntensities,
    seconds: Double
  )
    -> ControllerOutputRequest
  {
    ControllerOutputRequest(
      name: "rumble",
      command: intensities.activeMotors.isEmpty
        ? .stopRumble
        : .setRumble(
          intensities.mirroringMainOntoHaptics(),
          duration: .milliseconds(max(1, Int((seconds * 1000).rounded())))
        ),
      feature: localization.string("cli.controller.group.featureRumble")
    )
  }

  /// The request that sets the player indicator.
  public static func player(_ indicator: PhysicalPlayerIndicator) -> ControllerOutputRequest {
    ControllerOutputRequest(
      name: "player",
      command: .setPlayerIndicator(indicator),
      feature: localization.string("cli.controller.group.featurePlayer")
    )
  }

  /// The requests that set the lightbar color and the LED brightness that are given.
  public static func light(color: ControllerColor?, brightness: UInt8?) -> [ControllerOutputRequest]
  {
    var requests: [ControllerOutputRequest] = []
    if let color {
      requests.append(
        ControllerOutputRequest(
          name: "color",
          command: .setRGB(color),
          feature: localization.string("cli.controller.group.featureColor")
        )
      )
    }
    if let brightness {
      requests.append(
        ControllerOutputRequest(
          name: "brightness",
          command: .setLightBrightness(UnipolarValue(byte: brightness)),
          feature: localization.string("cli.controller.group.featureBrightness")
        )
      )
    }
    return requests
  }

  /// Fails with ``CodedFailure`` when `result` shows that the controller did not deliver `request`.
  ///
  /// An output the controller lacks fails with ``ErrorCode/controllerRequestFailed``.
  public static func check(
    _ result: ControllerOutputResult,
    _ request: ControllerOutputRequest,
    _ device: ApplicationServiceDeviceDescription
  ) throws {
    let message: String
    switch result.outcome {
    case .delivered: return
    case .unsupportedCapability:
      message = localization.formatted(
        "cli.controller.group.outputUnsupported",
        arguments: [device.name, request.feature, device.sessionToken.rawValue]
      )
    case .notReady:
      message = localization.formatted(
        "cli.controller.group.outputNotReady",
        arguments: [device.name]
      )
    case .notFound, .cancelled:
      message = localization.formatted("cli.controller.group.outputGone", arguments: [device.name])
    case .invalidValue, .writeFailed:
      message = localization.formatted(
        "cli.controller.group.outputFailed",
        arguments: [
          device.name, request.name, CommandLineName.kebab(result.outcome.rawValue),
        ]
      )
    }
    throw CodedFailure(.controllerRequestFailed, message)
  }

  /// Tells which of the `requested` motors ran after a delivered rumble `result`.
  ///
  /// - Throws: ``CodedFailure`` when the controller has none of the requested motors.
  public static func rumbleOutcome(
    requested: [PhysicalRumbleMotor],
    result: ControllerOutputResult,
    device: ApplicationServiceDeviceDescription
  ) throws -> ControllerRumbleOutcome {
    let dropped = Set(result.droppedRumbleChannels)
    let ran = requested.filter { motor in
      switch motor {
      case .lowFrequency: !dropped.contains(.lowFrequency) || !dropped.contains(.leftHaptic)
      case .highFrequency: !dropped.contains(.highFrequency) || !dropped.contains(.rightHaptic)
      default: !dropped.contains(motor)
      }
    }
    if !requested.isEmpty, ran.isEmpty {
      throw CodedFailure(
        .controllerRequestFailed,
        localization.formatted(
          "cli.controller.rumble.noneRan",
          arguments: [device.name, device.sessionToken.rawValue]
        )
      )
    }
    return ControllerRumbleOutcome(
      droppedTriggers: requested.filter {
        ($0 == .leftTrigger || $0 == .rightTrigger) && dropped.contains($0)
      },
      ran: ran
    )
  }
}

extension ControllerReference {
  /// The one connected controller of `devices` that the reference `text` names; text that is no
  /// reference matches none.
  ///
  /// - Throws: ``CodedFailure`` with ``ErrorCode/notFound`` that lists the candidates when none or
  ///   several match.
  public static func device(
    named text: String,
    in devices: [ApplicationServiceDeviceDescription]
  ) throws -> ApplicationServiceDeviceDescription {
    let matches = ControllerReference(text)?.matches(in: devices) ?? []
    if matches.count == 1, let device = matches.first { return device }
    let localization = Localization()
    let message: String
    let listed: [ApplicationServiceDeviceDescription]
    if matches.isEmpty {
      listed = devices
      message = localization.formatted(
        devices.isEmpty
          ? "cli.controller.group.selectorNoneConnected" : "cli.controller.group.selectorNotFound",
        arguments: [text]
      )
    } else {
      listed = matches
      message = localization.plural(
        "cli.controller.group.selectorAmbiguous",
        arguments: [text, matches.count]
      )
    }
    let lines = listed.map { device in
      let ids = [device.sessionToken.rawValue] + [device.portKey?.rawValue].compactMap { $0 }
      let identity = unsafe String(format: "%04X:%04X", device.vendorID, device.productID)
      return "  \(ids.joined(separator: "  "))  \(identity)  \(device.name)"
    }
    throw CodedFailure(.notFound, ([message] + lines).joined(separator: "\n"))
  }
}
