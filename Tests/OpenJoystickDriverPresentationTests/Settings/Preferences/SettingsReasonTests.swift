#if canImport(SwiftUI)

  import Foundation
  import OpenJoystickDriverKit
  import OpenJoystickDriverTestSupport
  import SwiftUI
  import Testing

  @testable import OpenJoystickDriverPresentation

  /// A Settings control that cannot change, or does not apply a change, says why or applies it.
  @Suite
  @MainActor
  struct SettingsReasonTests {
    private static func model(
      launch: LaunchAtLoginStub = LaunchAtLoginStub(isEnabled: false),
      authorization: RuntimeNotificationAuthorizationState = .allowed,
      checker: any ApplicationUpdateChecking = UpdateCheckerStub(
        result: .upToDate(current: "1.2.3", latest: "v1.2.3")
      )
    ) -> SettingsPreferencesModel {
      SettingsPreferencesModel(
        testNotifications: TestNotificationRequestStub(),
        settings: SettingsStore(directory: RootedDataDirectory.temporary()),
        launchAtLogin: launch,
        notificationAuthorization: NotificationAuthorizationStub(state: authorization),
        updateChecker: checker
      )
    }

    @Test
    func startAtLoginGivesReasonWhileLoginItemUnavailable() {
      let unavailable = LaunchAtLoginStub(isEnabled: false)
      unavailable.isAvailable = false
      #expect(
        Self.model(launch: unavailable).startAtLoginUnavailableReason
          == OJDLocalized.string("platform.macos.ui.settings.general.startAtLoginUnavailable")
      )
      #expect(Self.model().startAtLoginUnavailableReason == nil)
    }

    @Test
    func lockedSwitchShowsItsReasonAsRowText() {
      let row = SettingsSwitchRow(
        title: "Title",
        help: "Help",
        description: "Description",
        isOn: .constant(true),
        isEnabled: false,
        disabledReason: "Reason"
      )
      #expect(row.lockReason == "Reason")
      #expect(
        SettingsSwitchRow(
          title: "Title",
          help: "Help",
          description: "Description",
          isOn: .constant(true),
          disabledReason: "Reason"
        ).lockReason == nil
      )
    }

    @Test
    func deniedNotificationsSayWhyAndOfferSystemSettings() {
      let denied = NotificationDeliveryPresentation(settings: .authorizationOnly(.denied))
      #expect(
        denied.status
          == OJDLocalized.string("platform.macos.ui.settings.notifications.notificationsDenied")
      )
      #expect(denied.needsAttention)
    }

    @Test
    func undecidedNotificationsOfferNoSystemSettings() {
      let undecided = NotificationDeliveryPresentation(settings: .authorizationOnly(.notDetermined))
      #expect(
        undecided.status
          == OJDLocalized.string("ui.settings.notifications.notificationPermissionRequired")
      )
      #expect(!undecided.needsAttention)
    }

    @Test
    func allowedNotificationsHiddenByMacOSOfferSystemSettings() {
      let hidden = NotificationDeliveryPresentation(
        settings: RuntimeNotificationSettings(
          authorization: .allowed,
          alertStyle: .none,
          soundsEnabled: true
        )
      )
      #expect(hidden.needsAttention)
      let ready = NotificationDeliveryPresentation(
        settings: RuntimeNotificationSettings(
          authorization: .allowed,
          alertStyle: .banner,
          soundsEnabled: true
        )
      )
      #expect(!ready.needsAttention)
      #expect(ready.status == nil)
    }

    @Test
    func turningAutomaticUpdateCheckOnChecksInSession() async {
      let checker = UpdateCheckerStub(result: .upToDate(current: "1.2.3", latest: "v1.2.3"))
      let model = Self.model(checker: checker)
      model.setCheckUpdatesAutomatically(false)
      await Task.yield()
      #expect(model.updateState == .idle)

      model.setCheckUpdatesAutomatically(true)
      await waitUntil("the check ends") {
        model.updateState == .upToDate(current: "1.2.3", latest: "v1.2.3")
      }
      #expect(await checker.includePrereleaseArguments.count == 1)
    }

    @Test
    func controllerConnectedSwitchNamesNeedsAttentionNotification() {
      let title = OJDLocalized.string("ui.settings.notifications.controllerConnectedOrAttention")
      let label = OJDLocalized.string("ui.settings.notifications.controllerNotifications")
      #expect(!title.hasPrefix("ui.settings."))
      #expect(title != OJDLocalized.string("ui.settings.notifications.controllerConnectedShort"))
      #expect(label != title)
    }
  }

#endif
