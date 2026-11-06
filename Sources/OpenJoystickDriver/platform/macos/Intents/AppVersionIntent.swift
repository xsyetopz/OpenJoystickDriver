#if canImport(AppIntents)
  import AppIntents
  import Foundation

  /// The Shortcuts action that returns the version of the installed app.
  @available(macOS 13, *)
  struct AppVersionIntent: AppIntent {
    /// The name of the action in Shortcuts.
    static let title = LocalizedStringResource(
      "ui.shortcuts.action.appVersion.title"
    )
    /// The description of the action in Shortcuts.
    static let description = IntentDescription(
      LocalizedStringResource(
        "ui.shortcuts.action.appVersion.description"
      )
    )

    /// Returns the version of the app.
    func perform() -> some IntentResult & ReturnsValue<String> {
      let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
      return .result(value: version as? String ?? "")
    }
  }
#endif
