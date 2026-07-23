import OpenJoystickDriverKit

struct StatusPermissions: Sendable, Equatable {
  let inputMonitoring: StatusPermissionState
  let accessibility: StatusPermissionState

  init(inputMonitoring: StatusPermissionState, accessibility: StatusPermissionState) {
    self.inputMonitoring = inputMonitoring
    self.accessibility = accessibility
  }

  init(_ snapshot: PermissionManager.Snapshot) {
    self.init(
      inputMonitoring: StatusPermissionState(snapshot.inputMonitoring),
      accessibility: StatusPermissionState(snapshot.accessibility)
    )
  }

  init(inputMonitoring: String, accessibility: String) {
    self.init(
      inputMonitoring: StatusPermissionState(
        PermissionManager.AccessState(status: inputMonitoring)
      ),
      accessibility: StatusPermissionState(PermissionManager.AccessState(status: accessibility))
    )
  }

  static let unavailable = Self(inputMonitoring: .unavailable, accessibility: .unavailable)

  var isReady: Bool { inputMonitoring == .granted && accessibility == .granted }

  var isAvailable: Bool { inputMonitoring != .unavailable && accessibility != .unavailable }
}
