import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct DriverKitRelaySelfTestTests {
  @Test func ioRegistryDeliveryIsAuthoritative() {
    #expect(payload(inputDelta: 25).driverKitRelayVerdict == .passed)
    #expect(payload(inputDelta: 0, attempts: 26, successes: 26).driverKitRelayVerdict == .failed)
  }

  @Test func callbacksCanProveDeliveryWithoutRegistryCounters() {
    #expect(payload(reportEvents: 1).driverKitRelayVerdict == .passed)
    #expect(payload(valueEvents: 1).driverKitRelayVerdict == .passed)
    #expect(payload(inputDelta: 0, reportEvents: 1).driverKitRelayVerdict == .passed)
  }

  @Test func successfulSwifterKitSubmissionProvesDelivery() {
    #expect(payload(attempts: 26, successes: 26).driverKitRelayVerdict == .passed)
  }

  @Test func missingOrRejectedSubmissionFails() {
    #expect(payload().driverKitRelayVerdict == .failed)
    #expect(payload(attempts: 26, successes: 0, failures: 26).driverKitRelayVerdict == .failed)
  }

  @Test func commandSuccessRequiresPassedRelayVerdict() {
    #expect(payload(inputDelta: 1).isSuccessful)
    #expect(!payload(inputDelta: 0, attempts: 26, successes: 26).isSuccessful)
    #expect(payload(attempts: 26, successes: 26).isSuccessful)
    #expect(!payload(attempts: 26, failures: 26).isSuccessful)
  }

  @Test func optionalRelayWithoutDeliveryIsInconclusiveWhenCompatibilityPasses() {
    let result = payload(
      inputDelta: 0,
      attempts: 1,
      failures: 1,
      userSpaceReportEvents: 1,
      userSpaceRequired: true,
      driverKitRequired: false
    )

    #expect(result.driverKitRelayVerdict == .inconclusive)
    #expect(result.userSpaceVerdict == .passed)
    #expect(result.isSuccessful)
  }

  @Test func optionalRelayDoesNotMaskCompatibilityFailure() {
    let result = payload(userSpaceRequired: true, driverKitRequired: false)

    #expect(result.driverKitRelayVerdict == .inconclusive)
    #expect(result.userSpaceVerdict == .failed)
    #expect(!result.isSuccessful)
  }

  @Test func missingRelayRequirementKeyDecodesAsStrict() throws {
    let original = payload(inputDelta: 1)
    let encoded = try JSONEncoder().encode(original)
    var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    object.removeValue(forKey: "driverKitRequired")
    let legacyData = try JSONSerialization.data(withJSONObject: object)

    let decoded = try JSONDecoder().decode(
      ApplicationServiceVirtualDeviceSelfTestPayload.self,
      from: legacyData
    )

    #expect(decoded.driverKitRequired)
  }

  @Test func requiredUserSpaceFailureControlsExitVerdict() {
    let denied = ApplicationServiceVirtualDeviceSelfTestPayload(
      seconds: 1,
      driverKitValueEvents: 1,
      driverKitReportEvents: 0,
      userSpaceValueEvents: 20,
      userSpaceReportEvents: 20,
      userSpaceRequired: true,
      userSpaceStatus: "error: Accessibility denied"
    )
    #expect(denied.userSpaceVerdict == .failed)
    #expect(!denied.isSuccessful)

    let delivered = ApplicationServiceVirtualDeviceSelfTestPayload(
      seconds: 1,
      driverKitValueEvents: 1,
      driverKitReportEvents: 0,
      userSpaceValueEvents: 1,
      userSpaceReportEvents: 0,
      userSpaceRequired: true,
      userSpaceStatus: "on"
    )
    #expect(delivered.userSpaceVerdict == .passed)
    #expect(delivered.isSuccessful)
  }

  @Test func cliAndGuiSurfaceTheSharedVerdict() throws {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let service = try String(
      contentsOf: root.appendingPathComponent(
        "Sources/OpenJoystickDriver/Service/ApplicationServiceServer/SelfTest.swift"
      ),
      encoding: .utf8
    )
    let command = try String(
      contentsOf: root.appendingPathComponent(
        "Sources/OpenJoystickDriver/Commands/SelfTestCommand.swift"
      ),
      encoding: .utf8
    )
    let view = try String(
      contentsOf: root.appendingPathComponent(
        "Sources/OpenJoystickDriver/Views/MenuBarPopoverView/AdvancedCards.swift"
      ),
      encoding: .utf8
    )

    #expect(service.contains("driverKitDispatcher.sendDiagnosticProbe()"))
    #expect(service.contains("DriverKitRelayRequirement.currentExecutableRequiresRelay()"))
    #expect(service.contains("dispatch(events: [], from: identifier)"))
    #expect(command.contains("payload.driverKitRelayVerdict"))
    #expect(command.contains("payload.driverKitRequired"))
    #expect(command.contains("payload.userSpaceVerdict"))
    #expect(command.contains("if !payload.isSuccessful { exit(1) }"))
    #expect(view.contains("t.driverKitRelayVerdict"))
    #expect(view.contains("t.driverKitRequired"))
  }

  private func payload(
    inputDelta: Int? = nil,
    reportEvents: Int = 0,
    valueEvents: Int = 0,
    attempts: Int? = nil,
    successes: Int? = nil,
    failures: Int? = nil,
    userSpaceReportEvents: Int = 0,
    userSpaceRequired: Bool = false,
    driverKitRequired: Bool = true
  ) -> ApplicationServiceVirtualDeviceSelfTestPayload {
    ApplicationServiceVirtualDeviceSelfTestPayload(
      seconds: 1,
      driverKitValueEvents: valueEvents,
      driverKitReportEvents: reportEvents,
      userSpaceValueEvents: 0,
      userSpaceReportEvents: userSpaceReportEvents,
      userSpaceRequired: userSpaceRequired,
      driverKitRequired: driverKitRequired,
      driverKitInputReportDelta: inputDelta,
      driverKitSubmissionSuccessDelta: successes,
      driverKitSubmissionAttemptDelta: attempts,
      driverKitSubmissionFailureDelta: failures
    )
  }
}
