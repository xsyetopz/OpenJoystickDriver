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

  private func runStatus(
    _ arguments: [String],
    link: String,
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
                CommandLineToolLinkStatus.probe(
                  path: link,
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
  func fileThatIsNotLinkBlocksLink() async throws {
    let folder = try Folder()
    defer { folder.remove() }
    try Data().write(to: URL(fileURLWithPath: folder.link))

    let report = try tool(await runStatus(["--json"], link: folder.link, executable: folder.app))

    #expect(report["state"] as? String == "BlockedByFile")
    #expect(report["target"] == nil)
  }
}
