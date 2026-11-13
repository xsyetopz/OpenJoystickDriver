import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverPresentation

@Suite
struct UpdateStatusPresentationTests {
  @Test
  func upToDateShowsTheRunningVersion() {
    let status = UpdateStatusPresentation(
      state: .upToDate(current: "0.6.0-alpha.1", latest: "v0.6.0-alpha.1"),
      runningVersion: "0.6.0-alpha.1"
    )
    #expect(status.title == OJDLocalized.string("ui.settings.general.upToDate"))
    #expect(status.version == "0.6.0-alpha.1")
    #expect(status.latestRelease == nil)
  }

  @Test
  func aNewerRunningVersionShowsBothVersions() {
    let status = UpdateStatusPresentation(
      state: .aheadOfLatestRelease(current: "0.6.0-alpha.1", latest: "v0.5.0-beta.4"),
      runningVersion: "0.6.0-alpha.1"
    )
    #expect(status.title == OJDLocalized.string("ui.settings.general.updateAhead"))
    #expect(status.version == "0.6.0-alpha.1")
    #expect(
      status.latestRelease
        == OJDLocalized.formatted("ui.settings.general.latestRelease", "0.5.0-beta.4")
    )
  }

  @Test
  func beforeAnyCheckTheRowIsTheRunningVersion() {
    let status = UpdateStatusPresentation(state: .idle, runningVersion: "0.6.0-alpha.1")
    #expect(status.title == OJDLocalized.string("ui.settings.general.version"))
    #expect(status.version == "0.6.0-alpha.1")
    #expect(status.latestRelease == nil)
  }

  @Test
  func aFailureIsTheLabelAndKeepsTheRunningVersion() {
    let failure = UpdateCheckFailure(reason: .transport, message: "offline")
    let status = UpdateStatusPresentation(state: .failed(failure), runningVersion: "1.0.0")
    #expect(status.title == "offline")
    #expect(status.version == "1.0.0")
  }

  @Test
  func onlyPrereleasesPublishedNamesSettingWithoutFailureMark() {
    let status = UpdateStatusPresentation(state: .onlyPrereleases, runningVersion: "1.0.0")
    let setting = OJDLocalized.string("ui.settings.general.prereleaseUpdates")
    #expect(
      status.title == OJDLocalized.formatted("ui.settings.general.updateOnlyPrereleases", setting)
    )
    #expect(status.title.contains(setting))
    #expect(status.indicator == .symbol(name: "info.circle.fill", tone: .informational))
    #expect(status.version == "1.0.0")
  }

  @Test
  func anAvailableUpdateShowsTheReleaseVersion() {
    let info = UpdateInfo(
      tagName: "v9.0.0",
      version: SemanticVersion("9.0.0")!,
      htmlURL: URL(string: "https://example.com/v9.0.0")!
    )
    let status = UpdateStatusPresentation(state: .available(info), runningVersion: "1.0.0")
    #expect(status.title == OJDLocalized.string("ui.settings.general.updateAvailable"))
    #expect(status.version == "9.0.0")
  }

  @Test
  func eachOutcomeHasItsOwnIndicator() {
    func indicator(_ state: UpdateCheckState) -> UpdateStatusPresentation.Indicator {
      UpdateStatusPresentation(state: state, runningVersion: "1.0.0").indicator
    }
    let info = UpdateInfo(
      tagName: "v9.0.0",
      version: SemanticVersion("9.0.0")!,
      htmlURL: URL(string: "https://example.com/v9.0.0")!
    )
    let failure = UpdateCheckFailure(reason: .transport, message: "offline")
    #expect(indicator(.idle) == .none)
    #expect(indicator(.checking) == .progress)
    #expect(
      indicator(.upToDate(current: "1.0.0", latest: "v1.0.0"))
        == .symbol(name: "checkmark.circle.fill", tone: .positive)
    )
    #expect(
      indicator(.available(info)) == .symbol(name: "arrow.down.circle.fill", tone: .attention)
    )
    #expect(
      indicator(.aheadOfLatestRelease(current: "1.0.0", latest: "v0.9.0"))
        == .symbol(name: "arrow.up.circle.fill", tone: .informational)
    )
    #expect(indicator(.failed(failure)) == .symbol(name: "xmark.circle.fill", tone: .failure))
  }
}
