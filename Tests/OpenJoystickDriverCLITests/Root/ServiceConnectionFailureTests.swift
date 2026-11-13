import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverCLI

struct ServiceConnectionFailureTests {
  @Test
  func duplicateNameSaysWhereToSeeNamesInUse() {
    let error = ApplicationServiceRemappingRPCError(
      code: .duplicateName,
      message: "A remapping profile named Pad already exists."
    )

    let failure = ServiceConnection.failure(for: error) as? CLIFailure
    #expect(failure?.id == .duplicateName)
    #expect(failure?.message.contains("ojd profile list") == true)
  }

  @Test
  func serviceMessageEndingInPeriodIsNotDoubled() {
    let error = ApplicationServiceRemappingRPCError(
      code: .unwritableLibrary,
      message: "The remapping profile library could not be written."
    )

    let failure = ServiceConnection.failure(for: error) as? CLIFailure
    #expect(failure?.id == .unwritableLibrary)
    #expect(failure?.message.contains("ojd status") == true)
    #expect(failure?.message.contains("..") == false)
  }

  @Test(arguments: [(0.5, "0.5s"), (1, "1s"), (10, "10s")])
  func durationUsesUnitSymbolSoNoPluralIsNeeded(seconds: Double, text: String) {
    #expect(seconds.durationText(locale: Locale(identifier: "en_US")) == text)
  }
}

struct ServiceConnectionDeadlineTests {
  private struct Refusal: Error {}

  @Test(.timeLimit(.minutes(1)))
  func operationErrorIsReportedAsItsOwnFailureNotTimeout() async {
    do {
      _ = try await ServiceConnection.withDeadline(seconds: 30) { () async throws -> Int in
        throw Refusal()
      }
      Issue.record("expected a failure")
    } catch {
      let failure = error as? CLIFailure
      #expect(failure?.id == .serviceRequestFailed)
      #expect(failure?.id != .serviceTimeout)
    }
  }

  @Test(.timeLimit(.minutes(1)))
  func missedDeadlineIsReportedAsTimeoutNamingOption() async {
    do {
      _ = try await ServiceConnection.withDeadline(seconds: 0.05) {
        try await Task.sleep(nanoseconds: 60_000_000_000)
        return 1
      }
      Issue.record("expected a timeout")
    } catch {
      #expect(error as? CLIFailure == CLIFailure.timedOut(seconds: 0.05))
    }
  }
}
