#if canImport(AppIntents)
  import AppIntents
  import Foundation
  import OpenJoystickDriverService

  /// The Shortcuts action that activates a remapping profile for its controller model.
  @available(macOS 13, *)
  struct ActivateProfileIntent: AppIntent {
    /// The name of the action in Shortcuts.
    static let title = LocalizedStringResource(
      "ui.shortcuts.action.activateProfile.title"
    )
    /// The description of the action in Shortcuts.
    static let description = IntentDescription(
      LocalizedStringResource(
        "ui.shortcuts.action.activateProfile.description"
      )
    )

    /// The profile to activate.
    @Parameter(
      title: LocalizedStringResource("ui.shortcuts.parameter.profile")
    )
    var profile: ProfileEntity

    /// The automation service that activates the profile.
    @Dependency
    var service: any AutomationService

    /// Activates the profile and returns it.
    func perform() async throws -> some IntentResult & ReturnsValue<ProfileEntity> {
      .result(value: ProfileEntity(try await service.activateProfile(id: profile.id)))
    }
  }

  /// The Shortcuts action that deactivates a remapping profile.
  @available(macOS 13, *)
  struct DeactivateProfileIntent: AppIntent {
    /// The name of the action in Shortcuts.
    static let title = LocalizedStringResource(
      "ui.shortcuts.action.deactivateProfile.title"
    )
    /// The description of the action in Shortcuts.
    static let description = IntentDescription(
      LocalizedStringResource(
        "ui.shortcuts.action.deactivateProfile.description"
      )
    )

    /// The profile to deactivate.
    @Parameter(
      title: LocalizedStringResource("ui.shortcuts.parameter.profile")
    )
    var profile: ProfileEntity

    /// The automation service that deactivates the profile.
    @Dependency
    var service: any AutomationService

    /// Deactivates the profile and returns it.
    func perform() async throws -> some IntentResult & ReturnsValue<ProfileEntity> {
      .result(value: ProfileEntity(try await service.deactivateProfile(id: profile.id)))
    }
  }
#endif
