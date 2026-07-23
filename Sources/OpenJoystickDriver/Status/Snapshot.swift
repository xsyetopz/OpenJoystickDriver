import OpenJoystickDriverKit

struct RuntimeStatusSnapshot: Sendable {
  let source: RuntimeStatusSource
  let permissions: StatusPermissions
  let controllers: ConnectedControllersStatus
  let compatibility: RuntimeCompatibilityStatus
  let output: CompatibilityOutputStatus
  let applicationServicePayload: ApplicationServiceStatusPayload?

  init(payload: ApplicationServiceStatusPayload) {
    self.source = .runningApplication
    self.permissions = StatusPermissions(
      inputMonitoring: payload.inputMonitoring,
      accessibility: payload.accessibility
    )
    self.controllers = ConnectedControllersStatus(descriptions: payload.connectedDevices)
    self.compatibility = RuntimeCompatibilityStatus(rawValue: payload.compatibilityIdentity)
    self.output = CompatibilityOutputStatus(
      enabled: payload.userSpaceVirtualDeviceEnabled,
      status: payload.userSpaceVirtualDeviceStatus
    )
    self.applicationServicePayload = payload
  }

  init(localPermissions: PermissionManager.Snapshot) {
    self.source = .localSystem
    self.permissions = StatusPermissions(localPermissions)
    self.controllers = .unavailable
    self.compatibility = .unavailable
    self.output = .unavailable
    self.applicationServicePayload = nil
  }

  private init() {
    self.source = .unavailable
    self.permissions = .unavailable
    self.controllers = .unavailable
    self.compatibility = .unavailable
    self.output = .unavailable
    self.applicationServicePayload = nil
  }

  static let unavailable = Self()
}
