#if canImport(AppIntents)
  import AppIntents
  import Foundation
  import OpenJoystickDriverKit
  import OpenJoystickDriverService

  /// A connected controller that Shortcuts actions take and return.
  @available(macOS 13, *)
  struct ControllerEntity: AppEntity {
    /// The name of the controller type in Shortcuts.
    static let typeDisplayRepresentation = TypeDisplayRepresentation(
      name: LocalizedStringResource("ui.shortcuts.controller.type")
    )
    /// The query that Shortcuts uses to find controllers.
    static let defaultQuery = ControllerEntityQuery()

    /// The unit ID, the runtime ID when the controller reports no unit ID, or `VVVV:PPPP` for
    /// the one connected controller of that model.
    let id: String
    /// The controller name.
    @Property(title: LocalizedStringResource("ui.shortcuts.controller.name"))
    var name: String
    /// The controller model as `VVVV:PPPP`.
    @Property(title: LocalizedStringResource("ui.shortcuts.controller.model"))
    var model: String
    /// Whether the entity stands for every controller of the model instead of one controller.
    let isModelMatch: Bool

    /// Creates the entity from an automation controller.
    init(_ controller: AutomationController) {
      id = controller.id
      isModelMatch = controller.isModelMatch
      name = controller.name
      model = controller.model
    }

    /// The title and subtitle that Shortcuts shows for the entity.
    var displayRepresentation: DisplayRepresentation {
      // A model entry and the controller it resolves to share a name, so the subtitle tells them
      // apart.
      DisplayRepresentation(
        title: "\(name)",
        subtitle: isModelMatch
          ? "\(Localization().string("ui.shortcuts.controller.anyOfModel", model))"
          : "\(model)  \(id)"
      )
    }
  }

  /// Finds controllers for Shortcuts parameters by ID or by text.
  @available(macOS 13, *)
  struct ControllerEntityQuery: EntityStringQuery {
    /// The automation service that lists the controllers.
    @Dependency
    var service: any AutomationService

    /// The controllers whose IDs are `identifiers`.
    func entities(for identifiers: [String]) async throws -> [ControllerEntity] {
      try await service.controllers(ids: identifiers).map(ControllerEntity.init)
    }

    /// The controllers that match `string`.
    ///
    /// A typed `VVVV:PPPP` resolves like a saved model; other text filters the suggestions.
    func entities(matching string: String) async throws -> [ControllerEntity] {
      if ControllerModelID(string) != nil {
        return try await service.controllers(ids: [string]).map(ControllerEntity.init)
      }
      return await service.controllers()
        .filter { $0.name.localizedCaseInsensitiveContains(string) || $0.id == string }
        .map(ControllerEntity.init)
    }

    /// Every controller that the service lists, offered as suggestions.
    func suggestedEntities() async -> [ControllerEntity] {
      await service.controllers().map(ControllerEntity.init)
    }
  }
#endif
