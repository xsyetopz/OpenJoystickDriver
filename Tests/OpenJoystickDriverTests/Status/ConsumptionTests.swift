import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriver

struct StatusConsumptionTests {
  @Test func cliTextConsumesTheSameTypedErrorAndPermissionSemantics() {
    let payload = ApplicationServiceStatusPayload(
      inputMonitoring: "unknown",
      accessibility: "denied",
      connectedDevices: [],
      userSpaceVirtualDeviceEnabled: false,
      userSpaceVirtualDeviceStatus: "error: creation failed",
      compatibilityIdentity: CompatibilityIdentity.x360HID.rawValue
    )
    let snapshot = RuntimeStatusSnapshot(payload: payload)

    let lines = RuntimeStatusText.payloadLines(snapshot)

    #expect(lines.contains("  Input Monitoring : [UNKNOWN] unknown"))
    #expect(lines.contains("  Accessibility    : [DENIED] denied"))
    #expect(lines.contains("  backend   : error"))
    #expect(lines.contains("  status    : error: creation failed"))
    #expect(lines.contains("  identity  : x360-hid"))
  }

  @Test func directModeRetainsLocallyObservedPermissionTruth() {
    let permissions = StatusPermissions(inputMonitoring: .granted, accessibility: .denied)
    let lines = RuntimeStatusText.directModeLines(permissions)

    #expect(lines.contains("  Input Monitoring : [OK] granted"))
    #expect(lines.contains("  Accessibility    : [DENIED] denied"))
    #expect(lines.contains("  Overall          : [ACTION] blocked"))
    #expect(!lines.contains { $0.contains("[UNAVAILABLE]") })
  }
}
