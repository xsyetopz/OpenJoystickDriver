import Foundation
import OpenJoystickDriverKit
import Testing

struct InputMonitoringPermissionStateTests {
  @Test
  func accessStateNormalizesXPCAndMultilineProbeOutput() {
    #expect(PermissionManager.AccessState(status: "granted") == .granted)
    #expect(
      PermissionManager.AccessState(
        status: "[Daemon] Starting permission-check probe mode\nDENIED\n"
      ) == .denied
    )
    #expect(PermissionManager.AccessState(status: "unexpected") == .unknown)
  }

  @Test
  func snapshotRequiresBothProcessIdentities() {
    let ready = InputMonitoringPermissionSnapshot(application: .granted, daemon: .granted)
    let missingApp = InputMonitoringPermissionSnapshot(application: .denied, daemon: .granted)
    let missingDaemon = InputMonitoringPermissionSnapshot(application: .granted, daemon: .unknown)

    #expect(ready.isReady)
    #expect(!missingApp.isReady)
    #expect(!missingDaemon.isReady)
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
