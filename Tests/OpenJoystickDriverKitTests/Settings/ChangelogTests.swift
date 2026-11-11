import Foundation
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit

@Suite
struct ChangelogTests {
  private let root = RootedDataDirectory.temporary()

  private var store: SettingsStore { SettingsStore(directory: root) }

  private static let text = """
    # Changelog

    ## [Unreleased]

    ## [0.6.0-alpha.2] - 2026-11-07

    ### Added

    - Alpha two item.

    ## [0.6.0] - 2026-12-01

    ### Fixed

    - Release item.

    [Unreleased]: https://example.com/unreleased
    [0.6.0]: https://example.com/0.6.0
    """

  @Test
  func aSectionIsTheTextUnderItsHeaderUpToTheNextHeader() {
    #expect(
      Changelog.section(of: "0.6.0-alpha.2", in: Self.text) == "### Added\n\n- Alpha two item."
    )
  }

  @Test
  func theLastSectionEndsBeforeTheLinkReferences() {
    #expect(Changelog.section(of: "0.6.0", in: Self.text) == "### Fixed\n\n- Release item.")
  }

  @Test
  func aVersionMatchesOnlyItsOwnHeader() {
    #expect(Changelog.section(of: "0.6", in: Self.text) == nil)
    #expect(Changelog.section(of: "0.7.0", in: Self.text) == nil)
  }

  @Test
  func aSectionWithNoTextHasNoChanges() {
    #expect(Changelog.section(of: "Unreleased", in: Self.text) == nil)
  }

  @Test
  func theBundledChangelogHoldsTheReleasedVersions() throws {
    let text = try #require(Changelog.bundled())

    #expect(text.hasPrefix("# Changelog"))
    #expect(Changelog.section(of: "0.6.0-alpha.2", in: text) != nil)
  }

  @Test
  func aFreshInstallationHasShownNothing() throws {
    #expect(try store.lastShownChangelogVersion() == nil)
  }

  @Test
  func theLastShownVersionIsStored() throws {
    try store.setLastShownChangelogVersion("0.6.0-alpha.3")
    try store.set(.developerTools, to: true)

    #expect(try store.lastShownChangelogVersion() == "0.6.0-alpha.3")
    let object = try PropertyListFixture.dictionary(at: store.userFileURL)
    #expect(object["lastShownChangelogVersion"] as? String == "0.6.0-alpha.3")
  }

  @Test
  func anInstalledVersionShowsItsSectionUntilItIsRecorded() {
    let first = Changelog.toShow(installed: "0.6.0", lastShown: nil, in: Self.text)
    let afterUpdate = Changelog.toShow(installed: "0.6.0", lastShown: "0.6.0-alpha.2", in: Self.text)
    let again = Changelog.toShow(installed: "0.6.0", lastShown: "0.6.0", in: Self.text)

    #expect(first == "### Fixed\n\n- Release item.")
    #expect(afterUpdate == first)
    #expect(again == nil)
  }

  @Test
  func aVersionWithoutASectionShowsNothing() {
    #expect(Changelog.toShow(installed: "0.7.0-dev", lastShown: "0.6.0", in: Self.text) == nil)
  }

  @Test(arguments: [
    #""lastShownChangelogVersion": """#,
    #""lastShownChangelogVersion": 3"#,
    #""lastShownChangelogVersion": true"#,
  ])
  func aFileWithAnInvalidLastShownVersionIsDamaged(body: String) throws {
    let url = store.userFileURL
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try PropertyListFixture.bytes(
      json: #"{"apiVersion": "\#(OpenJoystickDriverAPI.version)", "kind": "Settings", \#(body)}"#
    ).write(to: url)

    #expect(throws: SettingsStoreError.damaged(file: url.path)) { try store.load() }
  }
}
