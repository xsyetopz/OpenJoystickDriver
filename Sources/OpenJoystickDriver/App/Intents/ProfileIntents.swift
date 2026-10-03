#if canImport(AppIntents)
  import AppIntents
  import Foundation
  import OpenJoystickDriverService

  /// The Shortcuts action that activates a remapping profile for its controller model.
  @available(macOS 13, *)
  struct ActivateProfileIntent: AppIntent {
    static let title = LocalizedStringResource(
      "shortcuts.action.activate_profile.title",
      defaultValue: "Activate Profile"
    )
    static let description = IntentDescription(
      LocalizedStringResource(
        "shortcuts.action.activate_profile.description",
        defaultValue: "Turns on a remapping profile for its controller model."
      )
    )

    @Parameter(
      title: LocalizedStringResource("shortcuts.parameter.profile", defaultValue: "Profile")
    )
    var profile: ProfileEntity

    @Dependency
    var service: any AutomationService

    func perform() async throws -> some IntentResult & ReturnsValue<ProfileEntity> {
      .result(value: ProfileEntity(try await service.activateProfile(id: profile.id)))
    }
  }

  /// The Shortcuts action that deactivates a remapping profile.
  @available(macOS 13, *)
  struct DeactivateProfileIntent: AppIntent {
    static let title = LocalizedStringResource(
      "shortcuts.action.deactivate_profile.title",
      defaultValue: "Deactivate Profile"
    )
    static let description = IntentDescription(
      LocalizedStringResource(
        "shortcuts.action.deactivate_profile.description",
        defaultValue: "Turns off a remapping profile."
      )
    )

    @Parameter(
      title: LocalizedStringResource("shortcuts.parameter.profile", defaultValue: "Profile")
    )
    var profile: ProfileEntity

    @Dependency
    var service: any AutomationService

    func perform() async throws -> some IntentResult & ReturnsValue<ProfileEntity> {
      .result(value: ProfileEntity(try await service.deactivateProfile(id: profile.id)))
    }
  }
#endif
