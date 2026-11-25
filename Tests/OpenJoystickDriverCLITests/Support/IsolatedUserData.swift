import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport

@testable import OpenJoystickDriverCLI

/// Keeps an in-process `ojd` run out of the user's own Application Support folder.
///
/// A command that a test runs on its defaults reads and writes the folders of the user who runs
/// the tests: `ojd migrate` converts their files and `ojd setting set` changes their settings.
/// Each folder that still points into the real Application Support folder moves to the same place
/// under a fresh scratch root; a folder that a test chose stays where the test put it.
enum IsolatedUserData {
  /// The Application Support folder of the user who runs the tests.
  static let userFolder = MacOSDataDirectory().url(for: .applicationData).standardizedFileURL

  /// Whether `url` is `userFolder` or inside it.
  static func isInUserFolder(_ url: URL) -> Bool {
    let path = url.standardizedFileURL.path
    return path == userFolder.path || path.hasPrefix(userFolder.path + "/")
  }

  /// Runs `body` with every CLI data folder that points into `userFolder` moved under a fresh
  /// scratch root.
  static func run<T>(_ body: () async -> T) async -> T {
    let scratch = RootedDataDirectory.temporary()
    let scratchFolder = scratch.url(for: .applicationData)
    func moved(_ url: URL) -> URL {
      guard isInUserFolder(url) else { return url }
      let relative = url.standardizedFileURL.path.dropFirst(userFolder.path.count)
      return scratchFolder.appendingPathComponent(String(relative.drop { $0 == "/" }))
    }
    // The scratch settings file goes away for good; the default trash is the user's Trash.
    let scratchSettings = SettingsStore(directory: scratch) {
      try FileManager.default.removeItem(at: $0)
    }
    func settings(_ store: SettingsStore) -> SettingsStore {
      isInUserFolder(store.folderURL) ? scratchSettings : store
    }
    let migration: any DataDirectory =
      isInUserFolder(MigrateCommand.directory.url(for: .applicationData))
      ? scratch : MigrateCommand.directory

    return await RecordStore.$directory.withValue(moved(RecordStore.directory)) {
      await ProtocolStore.$controllers.withValue(moved(ProtocolStore.controllers)) {
        await ModStore.$directory.withValue(moved(ModStore.directory)) {
          await MigrateCommand.$directory.withValue(migration) {
            await SettingCatalog.$store.withValue(settings(SettingCatalog.store)) {
              await SettingResetCommand.$store.withValue(settings(SettingResetCommand.store)) {
                await body()
              }
            }
          }
        }
      }
    }
  }
}
