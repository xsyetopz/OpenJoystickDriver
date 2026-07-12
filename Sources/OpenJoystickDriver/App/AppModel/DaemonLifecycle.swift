import AppKit
import Foundation
import OpenJoystickDriverKit

@MainActor extension AppModel {
  // MARK: - Daemon lifecycle

  func installDaemon() async {
    daemonError = nil
    guard ensureRunningFromApplications() else { return }
    guard await ensureBundleSignatureValid(for: "Install") else { return }
    do {
      let task = Task.detached { try DaemonManager.install() }
      try await task.value
    } catch {
      daemonError = error.localizedDescription
      return
    }
    try? await Task.sleep(nanoseconds: 500_000_000)
    client.disconnect()
    client.connect()
    await syncFromDaemonNow()
  }

  func startDaemon() async {
    daemonError = nil
    guard ensureRunningFromApplications() else { return }
    guard await ensureBundleSignatureValid(for: "Start") else { return }
    do {
      let task = Task.detached { try DaemonManager.start() }
      try await task.value
    } catch {
      daemonError = error.localizedDescription
      return
    }
    try? await Task.sleep(nanoseconds: 500_000_000)
    client.disconnect()
    client.connect()
    await syncFromDaemonNow()
  }

  func restartDaemon() async {
    daemonError = nil
    daemonRestarting = true
    guard ensureRunningFromApplications() else {
      daemonRestarting = false
      return
    }
    guard await ensureBundleSignatureValid(for: "Restart") else {
      daemonRestarting = false
      return
    }
    do {
      let task = Task.detached { try DaemonManager.restart() }
      try await task.value
    } catch {
      daemonError = error.localizedDescription
      daemonRestarting = false
      return
    }
    client.disconnect()
    try? await Task.sleep(nanoseconds: 1_000_000_000)
    client.connect()
    await syncFromDaemonNow()
    daemonRestarting = false
  }

  func uninstallDaemon() async {
    daemonError = nil
    guard ensureRunningFromApplications() else { return }
    guard await ensureBundleSignatureValid(for: "Uninstall") else { return }
    do {
      let task = Task.detached { try DaemonManager.uninstall() }
      try await task.value
    } catch {
      daemonError = error.localizedDescription
      return
    }
    client.disconnect()
    await syncFromDaemonNow()
  }
}
