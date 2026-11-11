import Foundation
import Testing

@testable import OpenJoystickDriverCLI

@Suite(.serialized)
struct GenerateCommandTests {
  private let folder = FileManager.default.temporaryDirectory
    .appendingPathComponent("ojd-generate-\(UUID().uuidString)", isDirectory: true)

  init() throws {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
  }

  /// Writes `source` as a script in the test folder and returns its path.
  private func script(_ source: String, _ name: String = "script.js") throws -> String {
    let url = folder.appendingPathComponent(name)
    try Data(source.utf8).write(to: url)
    return url.path
  }

  /// Runs `ojd generate` with the helper of the built executable.
  private func run(_ arguments: [String]) async -> CLIRun {
    await GenerateCommand.$helper.withValue(GenerateHelperLocation.executable) {
      await CLIRun.run(["generate"] + arguments)
    }
  }

  @Test
  func anEndlessScriptIsEndedAtTheTimeLimit() async throws {
    let path = try script("while (true) {}")
    let start = Date()

    let result = await run([path, "--timeout", "1"])

    #expect(result.code == 1, "\(result.standardError)")
    #expect(result.standardError.contains("error[E2010]"), "\(result.standardError)")
    #expect(Date().timeIntervalSince(start) < 20)
  }
}
