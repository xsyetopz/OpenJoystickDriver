#if canImport(AppIntents)
  import AppIntents
  import Foundation
  import OpenJoystickDriverKit
  import OpenJoystickDriverService

  /// The Shortcuts action that runs the rumble motors of one controller, as `ojd controller
  /// rumble` does.
  @available(macOS 13, *)
  struct RumbleControllerIntent: AppIntent {
    /// The name of the action in Shortcuts.
    static let title = LocalizedStringResource("ui.shortcuts.action.rumble.title")
    /// The description of the action in Shortcuts.
    static let description = IntentDescription(
      LocalizedStringResource("ui.shortcuts.action.rumble.description")
    )

    /// The controller to rumble.
    @Parameter(title: LocalizedStringResource("ui.shortcuts.parameter.controller"))
    var controller: ControllerEntity

    /// The intensity of both main motors from 0 to 255; 180 when no motor is named.
    @Parameter(
      title: LocalizedStringResource("ui.shortcuts.action.rumble.intensity"),
      default: 180,
      inclusiveRange: (0, 255)
    )
    var intensity: Int

    /// The seconds that the motors run, above 0 and at most 5.
    @Parameter(
      title: LocalizedStringResource("ui.shortcuts.action.rumble.duration"),
      default: 0.45,
      inclusiveRange: (0.05, 5)
    )
    var duration: Double

    /// The automation service that sends the output.
    @Dependency
    var service: any AutomationService

    /// Runs the motors.
    ///
    /// - Throws: ``CodedFailure`` with the code that `ojd controller rumble` prints, such as when
    ///   the controller has no motor.
    func perform() async throws -> some IntentResult {
      let byte = UInt8(clamping: intensity)
      let intensities = RumbleIntensities.manualTest(
        lowFrequency: byte,
        highFrequency: byte,
        leftTrigger: nil,
        rightTrigger: nil
      )
      _ = try await service.sendOutput(
        [ControllerOutput.rumble(intensities, seconds: duration)],
        to: controller.id,
        requestedMotors: intensities.activeMotors
      )
      return .result()
    }
  }

  /// The Shortcuts action that sets the player indicator of one controller, as `ojd controller
  /// player` does.
  @available(macOS 13, *)
  struct SetPlayerIndicatorIntent: AppIntent {
    /// The name of the action in Shortcuts.
    static let title = LocalizedStringResource("ui.shortcuts.action.player.title")
    /// The description of the action in Shortcuts.
    static let description = IntentDescription(
      LocalizedStringResource("ui.shortcuts.action.player.description")
    )

    /// The controller to change.
    @Parameter(title: LocalizedStringResource("ui.shortcuts.parameter.controller"))
    var controller: ControllerEntity

    /// The player number from 1 to 4, or 0 for none.
    @Parameter(
      title: LocalizedStringResource("ui.shortcuts.action.player.number"),
      default: 1,
      inclusiveRange: (0, 4)
    )
    var player: Int

    /// The automation service that sends the output.
    @Dependency
    var service: any AutomationService

    /// Sets the indicator.
    ///
    /// - Throws: ``CodedFailure`` with the code that `ojd controller player` prints.
    func perform() async throws -> some IntentResult {
      _ = try await service.sendOutput(
        [ControllerOutput.player(PhysicalPlayerIndicator(rawValue: player) ?? .off)],
        to: controller.id
      )
      return .result()
    }
  }

  /// The Shortcuts action that sets the light of one controller, as `ojd controller light` does.
  @available(macOS 13, *)
  struct SetControllerLightIntent: AppIntent {
    /// The name of the action in Shortcuts.
    static let title = LocalizedStringResource("ui.shortcuts.action.light.title")
    /// The description of the action in Shortcuts.
    static let description = IntentDescription(
      LocalizedStringResource("ui.shortcuts.action.light.description")
    )

    /// The controller to change.
    @Parameter(title: LocalizedStringResource("ui.shortcuts.parameter.controller"))
    var controller: ControllerEntity

    /// The lightbar color as `RRGGBB`.
    @Parameter(title: LocalizedStringResource("ui.shortcuts.action.light.color"))
    var color: String?

    /// The LED brightness from 0 to 255.
    @Parameter(
      title: LocalizedStringResource("ui.shortcuts.action.light.brightness"),
      inclusiveRange: (0, 255)
    )
    var brightness: Int?

    /// The automation service that sends the output.
    @Dependency
    var service: any AutomationService

    /// Sets the color and the brightness that are given.
    ///
    /// - Throws: ``CodedFailure`` with the code that `ojd controller light` prints, and
    ///   ``LightRequestError`` when the color is not `RRGGBB` or neither value is given.
    func perform() async throws -> some IntentResult {
      let parsed = color.flatMap(ControllerColor.init(hex:))
      guard (color == nil) == (parsed == nil), color != nil || brightness != nil else {
        throw LightRequestError()
      }
      _ = try await service.sendOutput(
        ControllerOutput.light(
          color: parsed,
          brightness: brightness.map { UInt8(clamping: $0) }
        ),
        to: controller.id
      )
      return .result()
    }
  }

  /// The failure of ``SetControllerLightIntent``: the color is not `RRGGBB`, or the action names
  /// neither a color nor a brightness.
  struct LightRequestError: Error, LocalizedError {
    /// The localized message.
    var errorDescription: String? {
      Localization().string("ui.shortcuts.error.lightRequest")
    }
  }
#endif
