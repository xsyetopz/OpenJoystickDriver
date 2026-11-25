import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverCLI

struct IsolatedUserDataTests {
  @Test
  func everyDefaultFolderMovesOutOfTheUserFolder() async {
    // Arrange: the folders keep their defaults.

    // Act
    let folders = await IsolatedUserData.run {
      [
        RecordStore.directory, ProtocolStore.controllers, ModStore.directory,
        MigrateCommand.directory.url(for: .applicationData), SettingCatalog.store.folderURL,
        SettingResetCommand.store.folderURL,
      ]
    }

    // Assert
    for folder in folders { #expect(!IsolatedUserData.isInUserFolder(folder), "\(folder.path)") }
    #expect(folders[0].lastPathComponent == "Controllers")
  }

  @Test
  func folderTheTestChoseStaysWhereTheTestPutIt() async {
    // Arrange
    let chosen = RootedDataDirectory.temporary().url(for: .applicationData)
      .appendingPathComponent("Controllers", isDirectory: true)

    // Act
    let folder = await RecordStore.$directory.withValue(chosen) {
      await IsolatedUserData.run { RecordStore.directory }
    }

    // Assert
    #expect(folder == chosen)
  }

  @Test
  func migrateOnDefaultsFindsNothingOfTheUser() async {
    // Act
    let run = await CLIRun.run(["migrate", "--dry-run", "--json"])

    // Assert: the scratch folder is empty, whatever the user's own folder holds.
    #expect(run.code == 0, "\(run.standardError)")
    #expect(!run.standardOutput.contains(#""verdict""#), "\(run.standardOutput)")
  }
}
