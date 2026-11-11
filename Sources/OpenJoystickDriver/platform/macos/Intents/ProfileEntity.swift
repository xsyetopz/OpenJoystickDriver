#if canImport(AppIntents)
  import AppIntents
  import Foundation
  import OpenJoystickDriverService

  /// A saved remapping profile that Shortcuts actions take and return.
  @available(macOS 13, *)
  struct ProfileEntity: AppEntity {
    /// The name of the profile type in Shortcuts.
    static let typeDisplayRepresentation = TypeDisplayRepresentation(
      name: LocalizedStringResource("ui.shortcuts.profile.type")
    )
    /// The query that Shortcuts uses to find profiles.
    static let defaultQuery = ProfileEntityQuery()

    /// The profile ID.
    let id: UUID
    /// The profile name.
    @Property(title: LocalizedStringResource("ui.shortcuts.profile.name"))
    var name: String
    /// `VVVV:PPPP` of the controller model that the profile applies to.
    @Property(
      title: LocalizedStringResource("ui.shortcuts.profile.model")
    )
    var model: String
    /// Whether the profile is the active one for its model.
    @Property(title: LocalizedStringResource("ui.shortcuts.profile.active"))
    var isActive: Bool

    /// Creates the entity from an automation profile.
    init(_ profile: AutomationProfile) {
      id = profile.id
      name = profile.name
      model = profile.model
      isActive = profile.isActive
    }

    /// The title and subtitle that Shortcuts shows for the entity.
    var displayRepresentation: DisplayRepresentation {
      DisplayRepresentation(title: "\(name)", subtitle: "\(model)")
    }
  }

  /// Finds saved profiles for Shortcuts parameters.
  @available(macOS 13, *)
  struct ProfileEntityQuery: EntityQuery {
    /// The automation service that lists the profiles.
    @Dependency
    var service: any AutomationService

    /// Returns the profiles with the given IDs.
    func entities(for identifiers: [UUID]) async throws -> [ProfileEntity] {
      try await service.profiles(ids: identifiers).map(ProfileEntity.init)
    }

    /// Returns every profile as a suggestion.
    func suggestedEntities() async throws -> [ProfileEntity] {
      try await service.profiles().map(ProfileEntity.init)
    }
  }
#endif
