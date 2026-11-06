#if canImport(SwiftUI)

  import AppKit

  /// Opens the System Settings page where the user approves the Xbox USB driver extension.
  enum SystemExtensionApproval {
    /// Opens the approval page in System Settings.
    ///
    /// Returns false when no page opens.
    @MainActor
    static func openSystemSettings() -> Bool {
      settingsURLs.contains { NSWorkspace.shared.open($0) }
    }

    /// macOS 15 and later list driver extensions under Login Items & Extensions; macOS 13 and 14
    /// show the approval prompt in Privacy & Security, and macOS 12 in Security & Privacy >
    /// General.
    static var settingsURLs: [URL] {
      if #available(macOS 15, *) {
        guard
          let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")
        else {
          preconditionFailure("the Login Items settings URL is a valid URL literal")
        }
        return [url]
      }
      return PermissionAccessActions.privacySettingsURLs(pane: "General")
    }
  }

#endif
