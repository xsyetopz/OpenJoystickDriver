import OpenJoystickDriverKit

@MainActor extension AppModel {
  func runAppleGameControllerAudit() async {
    appleGameControllerAuditRunning = true
    defer { appleGameControllerAuditRunning = false }

    let task = Task.detached {
      AppleGameControllerSupportAuditor.auditCurrentSystem()
    }
    appleGameControllerAudit = await task.value
  }
}
