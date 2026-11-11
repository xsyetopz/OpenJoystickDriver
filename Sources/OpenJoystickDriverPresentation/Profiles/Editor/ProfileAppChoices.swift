import Foundation

/// An app a profile can name: its bundle identifier, display name and where it is installed.
struct ProfileAppChoice: Equatable, Identifiable {
  /// The bundle identifier the profile stores.
  let bundleID: String
  /// The name the chooser shows.
  let name: String
  /// The app bundle, for its icon.
  let url: URL?
  /// Whether the app runs now.
  var isRunning = false

  /// The bundle identifier.
  var id: String { bundleID }
}

/// How an app of a profile shows in the editor.
struct ProfileAppEntry: Equatable {
  /// The bundle identifier.
  let bundleID: String
  /// The app's name, or its identifier when the app is not installed.
  let title: String
  /// The app bundle, for its icon.
  let url: URL?
  /// Whether the app is installed.
  let isInstalled: Bool
}

/// The apps the profile creation sheet and the profile editor offer.
enum ProfileAppChoices {
  /// The folders that hold installed apps.
  static var applicationFolders: [URL] {
    [
      URL(fileURLWithPath: "/Applications", isDirectory: true),
      URL(fileURLWithPath: "/System/Applications", isDirectory: true),
      FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
        "Applications",
        isDirectory: true
      ),
    ]
  }

  /// The running apps, then the installed apps by name, each bundle identifier once and none of
  /// `excluding`.
  static func merged(
    running: [ProfileAppChoice],
    installed: [ProfileAppChoice],
    excluding: [String]
  ) -> [ProfileAppChoice] {
    var seen = Set(excluding)
    let runningFirst = running.sorted(by: byName).filter { seen.insert($0.bundleID).inserted }
    let rest = installed.sorted(by: byName).filter { seen.insert($0.bundleID).inserted }
    return runningFirst.map { choice in
      var marked = choice
      marked.isRunning = true
      return marked
    } + rest
  }

  /// How the app `bundleID` shows: by name when `lookup` finds it, else by its identifier.
  static func entry(
    for bundleID: String,
    lookup: (String) -> ProfileAppChoice?
  ) -> ProfileAppEntry {
    guard let found = lookup(bundleID) else {
      return ProfileAppEntry(bundleID: bundleID, title: bundleID, url: nil, isInstalled: false)
    }
    return ProfileAppEntry(
      bundleID: bundleID,
      title: found.name,
      url: found.url,
      isInstalled: true
    )
  }

  /// The apps in `folders` and in the `Utilities` folder of each that have a bundle identifier.
  static func installedApps(in folders: [URL]) -> [ProfileAppChoice] {
    folders.flatMap { folder in
      apps(in: folder) + apps(in: folder.appendingPathComponent("Utilities", isDirectory: true))
    }
  }

  /// The app at `url`, or nil when `url` is no app bundle with a bundle identifier.
  static func choice(forAppAt url: URL) -> ProfileAppChoice? {
    guard let bundle = Bundle(url: url), let identifier = bundle.bundleIdentifier,
      !identifier.isEmpty
    else { return nil }
    let name =
      (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
      ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
      ?? url.deletingPathExtension().lastPathComponent
    return ProfileAppChoice(bundleID: identifier, name: name, url: url)
  }

  /// The app bundles directly inside `folder`.
  private static func apps(in folder: URL) -> [ProfileAppChoice] {
    let contents =
      (try? FileManager.default.contentsOfDirectory(
        at: folder,
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles]
      )) ?? []
    return contents.filter { $0.pathExtension == "app" }.compactMap(choice(forAppAt:))
  }

  /// Whether `left` sorts before `right` by name.
  private static func byName(_ left: ProfileAppChoice, _ right: ProfileAppChoice) -> Bool {
    left.name.localizedStandardCompare(right.name) == .orderedAscending
  }
}
