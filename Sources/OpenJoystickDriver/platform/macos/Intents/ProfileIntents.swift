#if canImport(AppIntents)
  import AppIntents
  import Foundation
  import OpenJoystickDriverKit
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

  /// The Shortcuts action that changes one value of a remapping profile, as `ojd profile set` does.
  @available(macOS 13, *)
  struct SetProfileValueIntent: AppIntent {
    /// The name of the action in Shortcuts.
    static let title = LocalizedStringResource(
      "ui.shortcuts.action.setProfileValue.title"
    )
    /// The description of the action in Shortcuts.
    static let description = IntentDescription(
      LocalizedStringResource(
        "ui.shortcuts.action.setProfileValue.description"
      )
    )

    /// The profile to change.
    @Parameter(
      title: LocalizedStringResource("ui.shortcuts.parameter.profile")
    )
    var profile: ProfileEntity

    /// The dotted path of the value in the profile, such as `name`.
    @Parameter(
      title: LocalizedStringResource("ui.shortcuts.action.setProfileValue.key")
    )
    var key: String

    /// The new value, read as JSON or, when it is not JSON, as text.
    @Parameter(
      title: LocalizedStringResource("ui.shortcuts.action.setProfileValue.value")
    )
    var value: String

    /// The automation service that changes the profile.
    @Dependency
    var service: any AutomationService

    /// Changes the value and returns the profile.
    func perform() async throws -> some IntentResult & ReturnsValue<ProfileEntity> {
      guard let profileKey = ProfileKey(argument: key) else {
        throw CodedFailure.usage(Localization().string("ui.shortcuts.error.profileKey"))
      }
      // A UUID text is never empty, so the selector always parses.
      guard let selector = ProfileSelector(argument: profile.id.uuidString) else {
        throw CodedFailure(.notFound, profile.id.uuidString)
      }
      let changed = try await service.setProfileValue(
        profile: selector,
        key: profileKey,
        value: ProfileValue(argument: value)
      )
      return .result(value: ProfileEntity(changed))
    }
  }
#endif
