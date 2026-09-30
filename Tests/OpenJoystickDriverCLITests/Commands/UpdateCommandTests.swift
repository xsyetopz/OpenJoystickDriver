import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverCLI

@Suite(.serialized)
struct UpdateCommandTests {
  private func run(
    _ arguments: [String],
    state: UpdateCheckState,
    prereleases: Locked<[Bool]> = Locked([])
  ) async -> CLIRun {
    let checker: @Sendable (String, Bool) async -> UpdateCheckState = { _, includePrereleases in
      prereleases.withLock { $0.append(includePrereleases) }
      return state
    }
    return await UpdateCheckCommand.$checker.withValue(checker) { await CLIRun.run(arguments) }
  }

  private static let available = UpdateCheckState.available(
    UpdateInfo(
      tagName: "v9.0.0",
      version: SemanticVersion("9.0.0")!,
      htmlURL: URL(string: "https://example.com/v9.0.0")!
    )
  )

  @Test
  func availableUpdatePrintsTheReleaseAndExitsZero() async throws {
    let prereleases = Locked<[Bool]>([])
    let human = await run(
      ["update", "check", "--prerelease"],
      state: Self.available,
      prereleases: prereleases
    )
    let json = await run(["update", "check", "--json"], state: Self.available)

    #expect(human.code == 0)
    #expect(human.standardOutput.contains("https://example.com/v9.0.0"))
    #expect(human.standardError.isEmpty)
    #expect(prereleases.withLock { $0 } == [true])
    let object = try json.json()
    #expect(object["status"] as? String == "available")
    #expect(object["latestVersion"] as? String == "v9.0.0")
    #expect(object["includePrereleases"] as? Bool == false)
  }

  @Test
  func upToDatePrintsPlainRow() async {
    let plain = await run(["update", "check", "--plain"], state: .upToDate("v1.0.0"))

    #expect(plain.code == 0)
    #expect(plain.standardOutput.hasPrefix("up-to-date\t"))
    #expect(plain.standardOutput.contains("\tv1.0.0\t"))
  }

  @Test
  func failedCheckExitsOneOnStandardErrorOnly() async {
    let failure = UpdateCheckFailure(reason: .invalidResponse, message: "offline")
    let result = await run(["update", "check", "--json"], state: .failed(failure))

    #expect(result.code == 1)
    #expect(result.standardOutput.isEmpty)
    #expect(result.standardError.hasPrefix("ojd: "))
    #expect(result.standardError.contains("offline"))
  }
}
