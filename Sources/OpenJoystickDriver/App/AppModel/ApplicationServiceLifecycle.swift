import AppKit
import Foundation
import OpenJoystickDriverKit

@MainActor extension AppModel {
  // MARK: - Application service lifecycle

  func installApplicationService() async {
    serviceError = nil
    guard ensureRunningFromApplications() else { return }
    guard await ensureBundleSignatureValid(for: "Install") else { return }
    do {
      let task = Task.detached { try ApplicationServiceManager.install() }
      try await task.value
    } catch {
      serviceError = error.localizedDescription
      return
    }
    try? await Task.sleep(nanoseconds: 500_000_000)
    client.disconnect()
    client.connect()
    await syncFromApplicationServiceNow()
  }

  func startApplicationService() async {
    serviceError = nil
    guard ensureRunningFromApplications() else { return }
    guard await ensureBundleSignatureValid(for: "Start") else { return }
    do {
      let task = Task.detached { try ApplicationServiceManager.start() }
      try await task.value
    } catch {
      serviceError = error.localizedDescription
      return
    }
    try? await Task.sleep(nanoseconds: 500_000_000)
    client.disconnect()
    client.connect()
    await syncFromApplicationServiceNow()
  }

  func restartApplicationService() async {
    serviceError = nil
    serviceRestarting = true
    guard ensureRunningFromApplications() else {
      serviceRestarting = false
      return
    }
    guard await ensureBundleSignatureValid(for: "Restart") else {
      serviceRestarting = false
      return
    }
    do {
      let task = Task.detached { try ApplicationServiceManager.restart() }
      try await task.value
      let relaunch = Process()
      relaunch.executableURL = URL(fileURLWithPath: "/bin/sh")
      relaunch.arguments = [
        "-c",
        "sleep 1; exec /usr/bin/open \"$1\"",
        "openjoystickdriver-relaunch",
        Bundle.main.bundlePath,
      ]
      try relaunch.run()
      NSApplication.shared.terminate(nil)
    } catch {
      serviceError = error.localizedDescription
      serviceRestarting = false
    }
  }

  func uninstallApplicationService() async {
    serviceError = nil
    guard ensureRunningFromApplications() else { return }
    guard await ensureBundleSignatureValid(for: "Uninstall") else { return }
    do {
      let task = Task.detached { try ApplicationServiceManager.uninstall() }
      try await task.value
    } catch {
      serviceError = error.localizedDescription
      return
    }
    client.disconnect()
    await syncFromApplicationServiceNow()
  }
}
