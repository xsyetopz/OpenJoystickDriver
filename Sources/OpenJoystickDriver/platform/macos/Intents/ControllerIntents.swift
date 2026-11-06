#if canImport(AppIntents)
  import AppIntents
  import Foundation
  import OpenJoystickDriverKit
  import OpenJoystickDriverService

  /// The Shortcuts action that returns the connected controllers.
  @available(macOS 13, *)
  struct GetControllersIntent: AppIntent {
    /// The name of the action in Shortcuts.
    static let title = LocalizedStringResource(
      "ui.shortcuts.action.getControllers.title"
    )
    /// The description of the action in Shortcuts.
    static let description = IntentDescription(
      LocalizedStringResource(
        "ui.shortcuts.action.getControllers.description"
      )
    )

    /// The automation service that lists the controllers.
    @Dependency
    var service: any AutomationService

    /// Returns the connected controllers, without the model entries.
    func perform() async -> some IntentResult & ReturnsValue<[ControllerEntity]> {
      // Only the controllers themselves; the model entries are for picking a controller.
      let controllers = await service.controllers().filter { !$0.isModelMatch }
      return .result(value: controllers.map(ControllerEntity.init))
    }
  }

  /// The Shortcuts action that returns the battery charge of one controller in percent.
  @available(macOS 13, *)
  struct GetBatteryLevelIntent: AppIntent {
    /// The name of the action in Shortcuts.
    static let title = LocalizedStringResource(
      "ui.shortcuts.action.batteryLevel.title"
    )
    /// The description of the action in Shortcuts.
    static let description = IntentDescription(
      LocalizedStringResource(
        "ui.shortcuts.action.batteryLevel.description"
      )
    )

    /// The controller to read.
    @Parameter(
      title: LocalizedStringResource("ui.shortcuts.parameter.controller")
    )
    var controller: ControllerEntity

    /// The automation service that reports the battery level.
    @Dependency
    var service: any AutomationService

    /// Returns the battery charge of the controller as read when the action runs.
    ///
    /// The entity that Shortcuts passes in can be older than the last report, so the action reads
    /// the controller again.
    ///
    /// - Throws: ``BatteryLevelUnknownError`` when the controller reports no battery level.
    func perform() async throws -> some IntentResult & ReturnsValue<Int> {
      // Read the charge now; the entity Shortcuts passes in can be older than the last report.
      let current = try await service.controllers(ids: [controller.id]).first
      guard let battery = current?.battery else {
        throw BatteryLevelUnknownError(controller: current?.name ?? controller.name)
      }
      return .result(value: Int(battery.lowerBound))
    }
  }

  /// The failure of ``GetBatteryLevelIntent``: the controller reports no battery level, or is not
  /// connected.
  struct BatteryLevelUnknownError: Error, LocalizedError {
    /// The name of the controller.
    let controller: String

    /// The localized message that names the controller.
    var errorDescription: String? {
      Localization().formatted(
        "ui.shortcuts.error.batteryUnknown",
        arguments: [controller]
      )
    }
  }
#endif
