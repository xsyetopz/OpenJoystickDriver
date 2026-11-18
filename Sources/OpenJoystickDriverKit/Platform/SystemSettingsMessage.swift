package import Foundation

/// A message that names the macOS settings app, which resolves to the catalog key of the name the
/// running macOS shows.
///
/// macOS 12 calls the app System Preferences. Some languages spell System Settings differently
/// across releases, such as Hindi on macOS 13 to 15 and Brazilian Portuguese on macOS 27, so each
/// message has one key for macOS 13 to 15, one for macOS 26, and one for macOS 27 and later.
package enum SystemSettingsMessage: Sendable, CaseIterable {
  /// The note that macOS has turned off both banners and sounds for the app.
  case bannersAndSoundOff
  /// The note that macOS has turned off banners for the app.
  case bannersOff
  /// The note that macOS has turned off sounds for the app.
  case soundOff
  /// The error that macOS denies notifications for the app.
  case notificationsDenied
  /// The error that Start at login waits for approval.
  case startAtLoginApproval
  /// The detail line of the driver extension that waits for approval.
  case driverApprovalDetail
  /// The button that opens the settings app.
  case openSettings
  /// The alert title when the settings app could not be opened.
  case openSettingsFailed
  /// The summary of `ojd transport-extension activate`.
  case activateAbstract
  /// The error of `ojd transport-extension` when macOS does not finish in time.
  case extensionTimeout
  /// The help of `ojd setting set`.
  case settingSetDiscussion
  /// The error of `ojd setting set` when macOS does not apply the setting.
  case settingNotApplied
  /// The help of `ojd controller disconnect`.
  case disconnectDiscussion
  /// The error of `ojd controller disconnect` for a Bluetooth Low Energy controller.
  case disconnectBluetoothLE
  /// The sentence under a denied permission in the Access area.
  case permissionDenied
  /// The tooltip of the button that opens the driver approval.
  case openDriverApprovalHelp

  /// The catalog key of the message for the settings app that `version` shows.
  ///
  /// A message about the login item has no macOS 12 key, because SMAppService needs macOS 13, so
  /// it resolves to the macOS 13 key.
  package func localizationKey(
    on version: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion
  ) -> String {
    let variants = keys
    switch version.majorVersion {
    case ..<13: return variants.preferences ?? variants.macOS13
    case 13...15: return variants.macOS13
    case 16..<27: return variants.macOS26
    default: return variants.current
    }
  }

  private struct Keys {
    let current: String
    let macOS26: String
    let macOS13: String
    let preferences: String?
  }

  private var keys: Keys {
    switch self {
    case .bannersAndSoundOff:
      Keys(
        current: "platform.macos.ui.settings.notifications.notificationBannersAndSoundOff",
        macOS26: "platform.macos.ui.settings.notifications.notificationBannersAndSoundOffMacOS26",
        macOS13: "platform.macos.ui.settings.notifications.notificationBannersAndSoundOffMacOS13",
        preferences: "platform.macos.ui.settings.notifications.bannersAndSoundOffSystemPreferences"
      )
    case .bannersOff:
      Keys(
        current: "platform.macos.ui.settings.notifications.notificationBannersOffDetail",
        macOS26: "platform.macos.ui.settings.notifications.notificationBannersOffDetailMacOS26",
        macOS13: "platform.macos.ui.settings.notifications.notificationBannersOffDetailMacOS13",
        preferences: "platform.macos.ui.settings.notifications.bannersOffDetailSystemPreferences"
      )
    case .soundOff:
      Keys(
        current: "platform.macos.ui.settings.notifications.notificationSoundOffDetail",
        macOS26: "platform.macos.ui.settings.notifications.notificationSoundOffDetailMacOS26",
        macOS13: "platform.macos.ui.settings.notifications.notificationSoundOffDetailMacOS13",
        preferences:
          "platform.macos.ui.settings.notifications.notificationSoundOffDetailSystemPreferences"
      )
    case .notificationsDenied:
      Keys(
        current: "platform.macos.ui.settings.notifications.notificationsDenied",
        macOS26: "platform.macos.ui.settings.notifications.notificationsDeniedMacOS26",
        macOS13: "platform.macos.ui.settings.notifications.notificationsDeniedMacOS13",
        preferences: "platform.macos.ui.settings.notifications.notificationsDeniedSystemPreferences"
      )
    case .startAtLoginApproval:
      Keys(
        current: "platform.macos.ui.settings.general.startAtLoginApprovalRequired",
        macOS26: "platform.macos.ui.settings.general.startAtLoginApprovalRequiredMacOS26",
        macOS13: "platform.macos.ui.settings.general.startAtLoginApprovalRequiredMacOS13",
        preferences: nil
      )
    case .driverApprovalDetail:
      Keys(
        current: "platform.macos.ui.setup.approvalDetail",
        macOS26: "platform.macos.ui.setup.approvalDetailMacOS26",
        macOS13: "platform.macos.ui.setup.approvalDetailMacOS13",
        preferences: "platform.macos.ui.setup.approvalDetailSystemPreferences"
      )
    case .openSettings:
      Keys(
        current: "platform.macos.ui.setup.openSystemSettings",
        macOS26: "platform.macos.ui.setup.openSystemSettingsMacOS26",
        macOS13: "platform.macos.ui.setup.openSystemSettingsMacOS13",
        preferences: "platform.macos.ui.setup.openSystemPreferences"
      )
    case .openSettingsFailed:
      Keys(
        current: "platform.macos.ui.setup.openSystemSettingsFailed",
        macOS26: "platform.macos.ui.setup.openSystemSettingsFailedMacOS26",
        macOS13: "platform.macos.ui.setup.openSystemSettingsFailedMacOS13",
        preferences: "platform.macos.ui.setup.openSystemPreferencesFailed"
      )
    case .activateAbstract:
      Keys(
        current: "platform.macos.cli.transportExtension.activate.abstract",
        macOS26: "platform.macos.cli.transportExtension.activate.abstractMacOS26",
        macOS13: "platform.macos.cli.transportExtension.activate.abstractMacOS13",
        preferences: "platform.macos.cli.transportExtension.activate.abstractSystemPreferences"
      )
    case .extensionTimeout:
      Keys(
        current: "platform.macos.cli.transportExtension.group.timeout",
        macOS26: "platform.macos.cli.transportExtension.group.timeoutMacOS26",
        macOS13: "platform.macos.cli.transportExtension.group.timeoutMacOS13",
        preferences: "platform.macos.cli.transportExtension.group.timeoutSystemPreferences"
      )
    case .settingSetDiscussion:
      Keys(
        current: "platform.macos.cli.setting.set.discussion",
        macOS26: "platform.macos.cli.setting.set.discussionMacOS26",
        macOS13: "platform.macos.cli.setting.set.discussionMacOS13",
        preferences: nil
      )
    case .settingNotApplied:
      Keys(
        current: "platform.macos.cli.setting.set.notApplied",
        macOS26: "platform.macos.cli.setting.set.notAppliedMacOS26",
        macOS13: "platform.macos.cli.setting.set.notAppliedMacOS13",
        preferences: nil
      )
    case .disconnectDiscussion:
      Keys(
        current: "platform.macos.cli.controller.disconnect.discussion",
        macOS26: "platform.macos.cli.controller.disconnect.discussionMacOS26",
        macOS13: "platform.macos.cli.controller.disconnect.discussionMacOS13",
        preferences: "platform.macos.cli.controller.disconnect.discussionSystemPreferences"
      )
    case .disconnectBluetoothLE:
      Keys(
        current: "platform.macos.cli.controller.disconnect.bluetoothLe",
        macOS26: "platform.macos.cli.controller.disconnect.bluetoothLeMacOS26",
        macOS13: "platform.macos.cli.controller.disconnect.bluetoothLeMacOS13",
        preferences: "platform.macos.cli.controller.disconnect.bluetoothLeSystemPreferences"
      )
    case .permissionDenied:
      Keys(
        current: "platform.macos.ui.access.permission.denied.message",
        macOS26: "platform.macos.ui.access.permission.denied.messageMacOS26",
        macOS13: "platform.macos.ui.access.permission.denied.messageMacOS13",
        preferences: "platform.macos.ui.access.permission.denied.messageSystemPreferences"
      )
    case .openDriverApprovalHelp:
      Keys(
        current: "platform.macos.ui.help.openDriverApproval",
        macOS26: "platform.macos.ui.help.openDriverApprovalMacOS26",
        macOS13: "platform.macos.ui.help.openDriverApprovalMacOS13",
        preferences: "platform.macos.ui.help.openDriverApprovalSystemPreferences"
      )
    }
  }
}
