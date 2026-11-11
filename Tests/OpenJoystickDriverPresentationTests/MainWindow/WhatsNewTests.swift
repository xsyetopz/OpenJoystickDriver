import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverPresentation

@Suite
@MainActor
struct WhatsNewTests {
  private let root = RootedDataDirectory.temporary()

  private var store: SettingsStore { SettingsStore(directory: root) }

  private static let changelog = """
    ## [0.6.0] - 2026-12-01

    - Release item.

    ## [0.5.0] - 2026-10-01

    - Older item.
    """

  private func model(installed: String, changelog: String? = changelog) -> WhatsNewModel {
    WhatsNewModel(settings: store, installed: installed, changelog: { changelog })
  }

  @Test
  func aSectionSplitsIntoHeadingsAndItems() {
    let blocks = WhatsNewBlock.blocks(from: "### Added\n\n- `ojd migrate` converts files.\n- Second.\n")
    #expect(
      blocks == [.heading("Added"), .item("`ojd migrate` converts files."), .item("Second.")]
    )
  }

  @Test
  func theFirstOpeningAfterAnUpdateShowsTheInstalledVersionOnce() throws {
    try store.setLastShownChangelogVersion("0.5.0")
    let whatsNew = model(installed: "0.6.0")

    whatsNew.presentIfNeeded()

    #expect(whatsNew.isPresented)
    #expect(whatsNew.version == "0.6.0")
    #expect(whatsNew.text == "- Release item.")
    #expect(try store.lastShownChangelogVersion() == "0.6.0")

    whatsNew.isPresented = false
    whatsNew.presentIfNeeded()
    #expect(!whatsNew.isPresented)
    let relaunched = model(installed: "0.6.0")
    relaunched.presentIfNeeded()
    #expect(!relaunched.isPresented)
  }

  @Test
  func aFreshInstallationShowsTheInstalledVersion() throws {
    let whatsNew = model(installed: "0.5.0")

    whatsNew.presentIfNeeded()

    #expect(whatsNew.isPresented)
    #expect(whatsNew.text == "- Older item.")
  }

  @Test
  func aVersionWithoutASectionShowsNothingAndRecordsNothing() throws {
    let whatsNew = model(installed: "0.7.0")

    whatsNew.presentIfNeeded()

    #expect(!whatsNew.isPresented)
    #expect(try store.lastShownChangelogVersion() == nil)
  }

  @Test
  func aMissingChangelogShowsNothing() {
    let whatsNew = model(installed: "0.6.0", changelog: nil)

    whatsNew.presentIfNeeded()

    #expect(!whatsNew.isPresented)
  }

  @Test
  func anUnreadableSettingsFileShowsNothing() throws {
    let url = store.userFileURL
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try Data("not a plist".utf8).write(to: url)
    let whatsNew = model(installed: "0.6.0")

    whatsNew.presentIfNeeded()

    #expect(!whatsNew.isPresented)
  }
}
