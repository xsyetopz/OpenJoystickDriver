import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverCLI

@Suite(.serialized)
struct ExtensionCommandTests {
  private func status(_ arguments: [String], _ extensionStatus: ExtensionStatus) async -> CLIRun {
    let probe: @Sendable () -> ExtensionStatus = { extensionStatus }
    return await StatusCommand.$extensionProbe.withValue(probe) {
      await CLIRun.run(["extension", "status"] + arguments)
    }
  }

  private func submit(
    _ verb: String,
    _ arguments: [String] = [],
    outcome: SystemExtensionSetupRequestResult,
    actions: Locked<[ExtensionSubmission.Action]> = Locked([])
  ) async -> CLIRun {
    let submission:
      @Sendable (ExtensionSubmission.Action) async throws -> SystemExtensionSetupRequestResult = {
        action in
        actions.withLock { $0.append(action) }
        return outcome
      }
    return await ExtensionSubmission.$submit.withValue(submission) {
      await CLIRun.run(["extension", verb] + arguments)
    }
  }

  @Test
  func statusPrintsBundleAndRegistrationAsJSONAndPlainRows() async throws {
    let active = ExtensionStatus(bundle: .present, registration: .active("record line"))

    let jsonRun = await status(["--json"], active)
    let plainRun = await status(["--plain"], active)

    #expect(jsonRun.code == 0)
    let json = try jsonRun.json()
    #expect(json["bundle"] as? String == "present")
    #expect(json["registration"] as? String == "active")
    #expect(json["detail"] as? String == "record line")
    #expect(plainRun.standardOutput == "bundle\tpresent\nregistration\tactive\n")
  }

  @Test
  func statusOmitsDetailWhenThereIsNone() async throws {
    let result = await status(["--json"], ExtensionStatus(bundle: .missing, registration: .absent))

    #expect(result.code == 0)
    let json = try result.json()
    #expect(json["bundle"] as? String == "missing")
    #expect(json["registration"] as? String == "absent")
    #expect(json["detail"] == nil)
  }

  @Test
  func statusPrintsHumanRowsAndTheRegistrationRecord() async {
    let result = await status(
      [],
      ExtensionStatus(bundle: .present, registration: .inactive("record line"))
    )

    #expect(result.code == 0)
    #expect(
      result.standardOutput
        == "Embedded extension:  present\nmacOS registration:  inactive\nrecord line\n"
    )
  }

  @Test
  func statusExitsOneWhenMacOSDoesNotReportTheRegistration() async {
    let result = await status(
      ["--plain"],
      ExtensionStatus(bundle: .present, registration: .unavailable("probe failed"))
    )

    #expect(result.code == 1)
    #expect(result.standardOutput == "bundle\tpresent\nregistration\tunavailable\n")
    #expect(result.standardError.hasPrefix("ojd: macOS did not report"))
    #expect(result.standardError.contains("probe failed"))
  }

  @Test
  func activateReportsTheStateAndSubmitsOneActivation() async throws {
    let actions = Locked<[ExtensionSubmission.Action]>([])

    let jsonRun = await submit("activate", ["--json"], outcome: .active, actions: actions)
    let humanRun = await submit("activate", outcome: .active, actions: actions)

    #expect(try jsonRun.json()["state"] as? String == "active")
    #expect(humanRun.code == 0)
    #expect(humanRun.standardOutput.isEmpty)
    #expect(humanRun.standardError == "The extension is active.\n")
    #expect(actions.withLock { $0 } == [.activate, .activate])
  }

  @Test
  func deactivateSubmitsADeactivation() async throws {
    let actions = Locked<[ExtensionSubmission.Action]>([])

    let result = await submit("deactivate", ["--plain"], outcome: .inactive, actions: actions)

    #expect(result.code == 0)
    #expect(result.standardOutput == "state\tinactive\n")
    #expect(actions.withLock { $0 } == [.deactivate])
  }

  @Test
  func activateWaitingForApprovalExitsZeroAndSaysWhereToApprove() async throws {
    let human = await submit("activate", outcome: .awaitingApproval)
    let quiet = await submit("activate", ["--quiet"], outcome: .awaitingApproval)
    let json = await submit("activate", ["--json"], outcome: .awaitingApproval)

    #expect(human.code == 0)
    #expect(human.standardError.contains("Driver Extensions"))
    #expect(quiet.standardError.contains("Driver Extensions"))
    #expect(try json.json()["state"] as? String == "awaiting-approval")
  }

  @Test(arguments: [SystemExtensionSetupRequestResult.failed, .timedOut])
  func activateThatMacOSRejectsOrDoesNotFinishExitsOne(
    outcome: SystemExtensionSetupRequestResult
  ) async {
    let result = await submit("activate", outcome: outcome)

    #expect(result.code == 1)
    #expect(result.standardOutput.isEmpty)
    #expect(result.standardError.hasPrefix("ojd: macOS "))
    #expect(result.standardError.contains("ojd extension status"))
  }
}
