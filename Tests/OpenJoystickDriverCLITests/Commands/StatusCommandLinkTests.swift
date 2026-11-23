import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverCLI

@Suite(.serialized, .removingTemporarySockets)
struct StatusCommandLinkTests {
  /// A folder that holds the link under test and the file it may point at.
  private struct Folder {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(
      "ojd-link-\(UUID().uuidString)",
      isDirectory: true
    )
    var link: String { url.appendingPathComponent("ojd").path }
    var app: String { url.appendingPathComponent("OpenJoystickDriver").path }

    init() throws {
      try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
      try Data().write(to: URL(fileURLWithPath: app))
    }

    func remove() { try? FileManager.default.removeItem(at: url) }
  }

  /// Runs `ojd status` reading `link`, then `searchPath` when nothing is at `link`.
  private func runStatus(
    _ arguments: [String],
    link: String,
    searchPath: String = "",
    executable: String
  ) async -> CLIRun {
    let records = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)")
    return await RecordStore.$directory.withValue(records) {
      await ServiceConnection.$socketPath.withValue(temporarySocketPath()) {
        await StatusCommand.$extensionProbe.withValue(
          { ExtensionStatus(bundle: .present, registration: .absent) },
          operation: {
            await StatusCommand.$linkProbe.withValue(
              {
                CommandLineToolLinkStatus.locate(
                  path: link,
                  searchPath: searchPath,
                  executable: URL(fileURLWithPath: executable)
                )
              },
              operation: { await CLIRun.run(["status"] + arguments) }
            )
          }
        )
      }
    }
  }

  private func tool(_ result: CLIRun) throws -> [String: Any] {
    try #require(try result.json()["commandLineTool"] as? [String: Any])
  }

  @Test
  func installedLinkIsReportedWithItsTarget() async throws {
    let folder = try Folder()
    defer { folder.remove() }
    try FileManager.default.createSymbolicLink(atPath: folder.link, withDestinationPath: folder.app)

    let json = await runStatus(["--json"], link: folder.link, executable: folder.app)
    let plain = await runStatus(["--plain"], link: folder.link, executable: folder.app)
    let human = await runStatus([], link: folder.link, executable: folder.app)

    #expect(json.code == 0, "\(json.standardError)")
    let report = try tool(json)
    #expect(report["state"] as? String == "Installed")
    #expect(report["path"] as? String == folder.link)
    #expect(report["target"] as? String == folder.app)
    #expect(plain.standardOutput.contains("command-line-tool\tinstalled\t\(folder.link)\n"))
    #expect(human.standardOutput.contains("installed, \(folder.link)"))
  }

  @Test
  func missingLinkIsReportedWithoutTarget() async throws {
    let folder = try Folder()
    defer { folder.remove() }

    let json = await runStatus(["--json"], link: folder.link, executable: folder.app)
    let plain = await runStatus(["--plain"], link: folder.link, executable: folder.app)

    #expect(json.code == 0, "\(json.standardError)")
    let report = try tool(json)
    #expect(report["state"] as? String == "Missing")
    #expect(report["path"] as? String == folder.link)
    #expect(report["target"] == nil)
    #expect(plain.standardOutput.contains("command-line-tool\tmissing\t\(folder.link)\n"))
  }

  @Test
  func linkWhoseTargetIsGoneIsBroken() async throws {
    let folder = try Folder()
    defer { folder.remove() }
    try FileManager.default.createSymbolicLink(atPath: folder.link, withDestinationPath: folder.app)
    try FileManager.default.removeItem(atPath: folder.app)

    let json = await runStatus(["--json"], link: folder.link, executable: folder.app)
    let plain = await runStatus(["--plain"], link: folder.link, executable: folder.app)

    #expect(json.code == 0, "\(json.standardError)")
    let report = try tool(json)
    #expect(report["state"] as? String == "Broken")
    #expect(report["target"] as? String == folder.app)
    #expect(plain.standardOutput.contains("command-line-tool\tbroken\t\(folder.link)\n"))
  }

  @Test
  func linkToAnotherExistingFileIsLinkedElsewhere() async throws {
    let folder = try Folder()
    defer { folder.remove() }
    let other = folder.url.appendingPathComponent("Other").path
    try Data().write(to: URL(fileURLWithPath: other))
    try FileManager.default.createSymbolicLink(atPath: folder.link, withDestinationPath: other)

    let report = try tool(
      await runStatus(["--json"], link: folder.link, executable: folder.app)
    )

    #expect(report["state"] as? String == "LinkedElsewhere")
    #expect(report["target"] as? String == other)
  }

  @Test
  func relativeLinkToExecutableIsInstalled() async throws {
    let folder = try Folder()
    defer { folder.remove() }
    try FileManager.default.createSymbolicLink(
      atPath: folder.link,
      withDestinationPath: "OpenJoystickDriver"
    )

    let report = try tool(
      await runStatus(["--json"], link: folder.link, executable: folder.app)
    )

    #expect(report["state"] as? String == "Installed")
    #expect(report["target"] as? String == "OpenJoystickDriver")
  }

  @Test
  func linkOnSearchPathIsInstalledWhenDefaultLinkIsMissing() async throws {
    let folder = try Folder()
    defer { folder.remove() }
    let bin = folder.url.appendingPathComponent("bin", isDirectory: true)
    try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
    let onPath = bin.appendingPathComponent("ojd").path
    try FileManager.default.createSymbolicLink(atPath: onPath, withDestinationPath: folder.app)

    let report = try tool(
      await runStatus(
        ["--json"],
        link: folder.link,
        searchPath: "/nonexistent-\(UUID().uuidString):\(bin.path)",
        executable: folder.app
      )
    )

    #expect(report["state"] as? String == "Installed")
    #expect(report["path"] as? String == onPath)
    #expect(report["target"] as? String == folder.app)
  }

  @Test
  func linkOnSearchPathToAnotherFileLeavesDefaultMissing() async throws {
    let folder = try Folder()
    defer { folder.remove() }
    let bin = folder.url.appendingPathComponent("bin", isDirectory: true)
    try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
    let other = folder.url.appendingPathComponent("Other").path
    try Data().write(to: URL(fileURLWithPath: other))
    try FileManager.default.createSymbolicLink(
      atPath: bin.appendingPathComponent("ojd").path,
      withDestinationPath: other
    )

    let report = try tool(
      await runStatus(
        ["--json"],
        link: folder.link,
        searchPath: bin.path,
        executable: folder.app
      )
    )

    #expect(report["state"] as? String == "Missing")
    #expect(report["path"] as? String == folder.link)
  }

  @Test
  func fileThatIsNotLinkBlocksLink() async throws {
    let folder = try Folder()
    defer { folder.remove() }
    try Data().write(to: URL(fileURLWithPath: folder.link))

    let report = try tool(await runStatus(["--json"], link: folder.link, executable: folder.app))

    #expect(report["state"] as? String == "BlockedByFile")
    #expect(report["target"] == nil)
  }
}
