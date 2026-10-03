#if canImport(AppIntents)
  import AppIntents
  import Foundation
  import OpenJoystickDriverService

  /// A saved remapping profile that Shortcuts actions take and return.
  @available(macOS 13, *)
  struct ProfileEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(
      name: LocalizedStringResource("shortcuts.profile.type", defaultValue: "Remapping Profile")
    )
    static let defaultQuery = ProfileEntityQuery()

    let id: UUID
    @Property(title: LocalizedStringResource("shortcuts.profile.name", defaultValue: "Name"))
    var name: String
    /// `VVVV:PPPP` of the controller model that the profile applies to.
    @Property(
      title: LocalizedStringResource("shortcuts.profile.model", defaultValue: "Controller Model")
    )
    var model: String
    @Property(title: LocalizedStringResource("shortcuts.profile.active", defaultValue: "Active"))
    var isActive: Bool

    init(_ profile: AutomationProfile) {
      id = profile.id
      name = profile.name
      model = profile.model
      isActive = profile.isActive
    }

    var displayRepresentation: DisplayRepresentation {
      DisplayRepresentation(title: "\(name)", subtitle: "\(model)")
    }
  }

  @available(macOS 13, *)
  struct ProfileEntityQuery: EntityQuery {
    @Dependency
    var service: any AutomationService

    func entities(for identifiers: [UUID]) async throws -> [ProfileEntity] {
      try await service.profiles(ids: identifiers).map(ProfileEntity.init)
    }

    func suggestedEntities() async throws -> [ProfileEntity] {
      try await service.profiles().map(ProfileEntity.init)
    }
  }
#endif
