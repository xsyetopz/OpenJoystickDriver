#if canImport(SwiftUI)

  import AppKit
  import Foundation
  import OpenJoystickDriverKit

  // Presents the macOS privacy flow for a user-initiated access request from the Access area or
  // the status item. The runtime gateway performs the request; this type opens System Settings
  // when access is still missing.
  /// Opens the macOS privacy settings for a user-requested access, which the runtime gateway asks
  /// the service to request.
  enum PermissionAccessActions {
    /// Requests a controller access and opens its Privacy & Security pane when it is not granted.
    ///
    /// Input Monitoring is the pane for `.inputRead` and Accessibility the pane for `.inputInject`.
    static func requestControllerAccess(
      viewModel: RuntimeViewModel,
      requirement: PermissionManager.Requirement
    ) {
      Task { @MainActor in
        NSApplication.shared.activate(ignoringOtherApps: true)
        guard let permissions = await viewModel.requestPermission(requirement) else { return }
        let isGranted: Bool
        switch requirement {
        case .inputRead: isGranted = permissions.inputRead == .granted
        case .inputInject: isGranted = permissions.inputInject == .granted
        }
        if !isGranted {
          openPrivacySettings(
            pane: requirement == .inputRead ? "Privacy_ListenEvent" : "Privacy_Accessibility"
          )
        }
      }
    }

    /// Requests the permission to post events and opens the Accessibility pane when it is not
    /// granted.
    static func requestPostEventAccess(viewModel: RuntimeViewModel) {
      Task { @MainActor in
        NSApplication.shared.activate(ignoringOtherApps: true)
        guard let access = await viewModel.requestPostEventAccess() else { return }
        if access != .granted { openPrivacySettings(pane: "Privacy_Accessibility") }
      }
    }

    /// Requests every controller access, then the permission to post events when it is still
    /// needed.
    ///
    /// Opens the pane of the first access that is not granted.
    static func requestAccess(viewModel: RuntimeViewModel) {
      Task { @MainActor in
        NSApplication.shared.activate(ignoringOtherApps: true)
        guard let permissions = await viewModel.requestPermissions() else { return }
        guard permissions.isReady else {
          openPrivacySettings(for: permissions)
          return
        }
        guard case .available(let status) = viewModel.statusState,
          AccessReadiness.postEventAccessNeedsRequest(in: status)
        else { return }
        guard let access = await viewModel.requestPostEventAccess() else { return }
        if access != .granted { openPrivacySettings(pane: "Privacy_Accessibility") }
      }
    }

    /// Returns the Privacy & Security pane URLs for `pane`, the System Settings one first on macOS
    /// 13 and later.
    static func privacySettingsURLs(pane: String) -> [URL] {
      var urls: [URL] = []
      if #available(macOS 13.0, *) {
        if let url = URL(
          string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?\(pane)"
        ) {
          urls.append(url)
        }
      }
      if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
        urls.append(url)
      }
      return urls
    }

    /// Opens Input Monitoring when it is not granted, else Accessibility.
    @MainActor
    private static func openPrivacySettings(for permissions: RuntimePermissionSummary) {
      let pane: String
      if permissions.inputRead != .granted {
        pane = "Privacy_ListenEvent"
      } else {
        pane = "Privacy_Accessibility"
      }
      openPrivacySettings(pane: pane)
    }

    /// Opens the Privacy & Security pane `pane`, or System Settings itself when no pane URL opens.
    @MainActor
    private static func openPrivacySettings(pane: String) {
      let urls = privacySettingsURLs(pane: pane)
      for url in urls where NSWorkspace.shared.open(url) { return }
      let fallbackPath: String
      if #available(macOS 13.0, *) {
        fallbackPath = "/System/Applications/System Settings.app"
      } else {
        fallbackPath = "/System/Library/PreferencePanes/Security.prefPane"
      }
      NSWorkspace.shared.open(URL(fileURLWithPath: fallbackPath))
    }
  }

#endif
