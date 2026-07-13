import Foundation
import OpenJoystickDriverKit
import Testing

struct InputMonitoringPermissionStateTests {
  @Test
  func accessStateNormalizesMultilineProbeOutput() {
    #expect(PermissionManager.AccessState(status: "granted") == .granted)
    #expect(
      PermissionManager.AccessState(
        status: "[Application service] Starting permission-check probe mode\nDENIED\n"
      ) == .denied
    )
    #expect(PermissionManager.AccessState(status: "unexpected") == .unknown)
  }

  @Test
  func permissionSnapshotRequiresBothStates() {
    #expect(
      PermissionManager.Snapshot(inputMonitoring: .granted, accessibility: .granted).isReady
    )
    #expect(
      !PermissionManager.Snapshot(inputMonitoring: .granted, accessibility: .denied).isReady
    )
  }

  @Test
  func accessStateHasStableTransportAndDisplayValues() throws {
    let encoded = try JSONEncoder().encode(PermissionManager.AccessState.denied)
    let decoded = try JSONDecoder().decode(PermissionManager.AccessState.self, from: encoded)

    #expect(decoded == .denied)
    #expect(String(describing: decoded) == "denied")
    #expect(decoded.label == "[DENIED]")
  }
}
