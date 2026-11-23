#if canImport(SwiftUI) && canImport(AppKit)

  import AppKit
  import Combine
  import OpenJoystickDriverKit

  /// The launch settings the Controllers detail lists, edits and removes.
  ///
  /// It reads and writes the same settings file as `ojd virtual launch-setting`, so the app and the
  /// command line agree.
  @MainActor
  final class LaunchSettingsModel: ObservableObject {
    /// One stored launch setting with the name the list shows.
    struct Entry: Identifiable, Equatable {
      /// The key of the setting: a bundle identifier, or the path of a program outside a bundle.
      let key: String
      /// The name of the app, or the last path component of the key when the app is not found.
      let name: String
      /// The setting.
      let setting: LaunchSetting

      /// The key, which identifies the entry.
      var id: String { key }
    }

    /// The stored settings, sorted by name.
    @Published
    private(set) var entries: [Entry] = []
    /// The message of the latest failure, or nil.
    @Published
    private(set) var failure: String?
    /// Whether the latest copy of the Steam launch option succeeded.
    @Published
    private(set) var copied = false

    /// The settings file.
    private let settings: SettingsStore

    /// Creates the model on a settings store and loads the settings.
    init(settings: SettingsStore = SettingsStore()) {
      self.settings = settings
      reload()
    }

    /// Reads the stored settings again.
    func reload() {
      do {
        entries = try settings.launchSettings().map { key, setting in
          Entry(key: key, name: Self.name(of: key), setting: setting)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        failure = nil
      } catch { failure = error.localizedDescription }
    }

    /// Returns the entry of `app`, which is stored empty when it has none yet.
    ///
    /// - Parameter app: The `.app` or executable the person chose.
    /// - Returns: The entry to edit, or nil when `app` has no executable or the file cannot be
    ///   written; ``failure`` then says why.
    func entry(adding app: URL) -> Entry? {
      do {
        let key = try LaunchSettingKey.key(for: app.path, searchPath: nil)
        let stored = try settings.launchSettings()[key]
        return Entry(key: key, name: Self.name(of: key), setting: stored ?? LaunchSetting())
      } catch {
        failure = error.localizedDescription
        return nil
      }
    }

    /// Stores `setting` under `key`.
    ///
    /// - Parameters:
    ///   - setting: The setting to store.
    ///   - key: The key of the app.
    /// - Returns: Whether the setting was stored; ``failure`` says why when it was not.
    @discardableResult
    func save(_ setting: LaunchSetting, for key: String) -> Bool {
      do {
        try settings.setLaunchSetting(setting, for: key)
        reload()
        return true
      } catch let error as LaunchSettingError {
        failure = Self.message(for: error)
      } catch { failure = error.localizedDescription }
      return false
    }

    /// Shows the message of `problem` as the failure.
    func report(_ problem: any Error) {
      if let setting = problem as? LaunchSettingError {
        failure = Self.message(for: setting)
      } else {
        failure = problem.localizedDescription
      }
    }

    /// Removes the setting stored under `key`.
    func removeLaunchSetting(key: String) {
      do {
        _ = try settings.removeLaunchSetting(for: key)
        reload()
      } catch { failure = error.localizedDescription }
    }

    /// Puts the Steam launch option on the clipboard.
    func copySteamLaunchOption() {
      NSPasteboard.general.clearContents()
      copied = NSPasteboard.general.setString(
        Self.steamLaunchOption(tool: Self.installedTool()),
        forType: .string
      )
    }

    /// Returns the launch option that makes Steam run a game through `ojd virtual launch`.
    ///
    /// - Parameter tool: The path of the `ojd` command-line tool.
    /// - Returns: The launch option, with the path in quotes and Steam's `%command%` for the game.
    static func steamLaunchOption(tool: String = CommandLineToolLinkStatus.defaultPath) -> String {
      "\"\(tool)\" virtual launch -- %command%"
    }

    /// Returns the path of the `ojd` link that runs this app, or the default link path.
    ///
    /// The app and Steam start with launchd's `PATH`, which leaves out the folders where users
    /// link `ojd` when `/usr/local/bin` is missing, so those folders are searched too. The option
    /// holds the full path because a game Steam starts has the same short `PATH`.
    /// - Parameters:
    ///   - path: The link the app installs, read first.
    ///   - home: The user's home folder.
    ///   - searchPath: Colon-separated folders searched before the user folders.
    ///   - executable: The app executable the link must point to.
    /// - Returns: The installed link, or `path` when none is.
    static func installedTool(
      path: String = CommandLineToolLinkStatus.defaultPath,
      home: URL = FileManager.default.homeDirectoryForCurrentUser,
      searchPath: String = ProcessInfo.processInfo.environment["PATH"] ?? "",
      executable: URL = CommandLineToolLinkStatus.currentExecutable
    ) -> String {
      let folders = [
        searchPath, "/opt/homebrew/bin", home.appendingPathComponent(".local/bin").path,
      ]
      let status = CommandLineToolLinkStatus.locate(
        path: path,
        searchPath: folders.filter { !$0.isEmpty }.joined(separator: ":"),
        executable: executable
      )
      return status.state == .installed ? status.path : path
    }

    /// Returns the message of `error`, as the command line words it.
    private static func message(for error: LaunchSettingError) -> String {
      switch error {
      case .invalidEnvironmentName(let name):
        OJDLocalized.formatted("cli.virtual.launchSetting.group.errorName", name)
      case .invalidEnvironmentAssignment(let text):
        OJDLocalized.formatted("cli.virtual.launchSetting.group.errorAssignment", text)
      }
    }

    /// Returns the name the list shows for `key`.
    private static func name(of key: String) -> String {
      if key.hasPrefix("/") { return URL(fileURLWithPath: key).lastPathComponent }
      guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: key) else {
        return key
      }
      return FileManager.default.displayName(atPath: url.path)
    }
  }

#endif
