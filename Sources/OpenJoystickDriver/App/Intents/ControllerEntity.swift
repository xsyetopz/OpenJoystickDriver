#if canImport(AppIntents)
  import AppIntents
  import Foundation
  import OpenJoystickDriverService

  /// A connected controller that Shortcuts actions take and return.
  @available(macOS 13, *)
  struct ControllerEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(
      name: LocalizedStringResource("shortcuts.controller.type")
    )
    static let defaultQuery = ControllerEntityQuery()

    /// The unit ID, the runtime ID when the controller reports no unit ID, or `VVVV:PPPP` for
    /// the one connected controller of that model.
    let id: String
    @Property(title: LocalizedStringResource("shortcuts.controller.name"))
    var name: String
    /// `VVVV:PPPP`.
    @Property(title: LocalizedStringResource("shortcuts.controller.model"))
    var model: String
    let isModelMatch: Bool

    init(_ controller: AutomationController) {
      id = controller.id
      isModelMatch = controller.isModelMatch
      name = controller.name
      model = controller.model
    }

    var displayRepresentation: DisplayRepresentation {
      // A model entry shows only the model; a single controller also shows its own ID.
      DisplayRepresentation(
        title: "\(name)",
        subtitle: isModelMatch ? "\(model)" : "\(model)  \(id)"
      )
    }
  }

  @available(macOS 13, *)
  struct ControllerEntityQuery: EntityStringQuery {
    @Dependency
    var service: any AutomationService

    func entities(for identifiers: [String]) async throws -> [ControllerEntity] {
      try await service.controllers(ids: identifiers).map(ControllerEntity.init)
    }

    /// A typed `VVVV:PPPP` resolves like a saved model; other text filters the suggestions.
    func entities(matching string: String) async throws -> [ControllerEntity] {
      if parseControllerModel(string) != nil {
        return try await service.controllers(ids: [string]).map(ControllerEntity.init)
      }
      return await service.controllers()
        .filter { $0.name.localizedCaseInsensitiveContains(string) || $0.id == string }
        .map(ControllerEntity.init)
    }

    func suggestedEntities() async throws -> [ControllerEntity] {
      await service.controllers().map(ControllerEntity.init)
    }
  }
#endif
