import AppKit
import Foundation
import OpenJoystickDriverKit

@MainActor extension AppModel {
  // MARK: - XPC-backed operations

  func deviceInputState(vendorID: UInt16, productID: UInt16) async -> DeviceInputState? {
    guard daemonConnected else { return nil }
    return try? await client.deviceInputState(vendorID: vendorID, productID: productID)
  }

  func packetLog(vendorID: UInt16, productID: UInt16) async -> [PacketLogEntry] {
    guard daemonConnected else { return [] }
    return (try? await client.packetLog(vendorID: vendorID, productID: productID)) ?? []
  }

  func sendPhysicalRumble(
    vendorID: UInt16,
    productID: UInt16,
    left: UInt8,
    right: UInt8,
    lt: UInt8,
    rt: UInt8,
    durationMs: Int
  ) async -> Bool {
    guard daemonConnected else { return false }
    do {
      return try await client.sendPhysicalRumble(
        vendorID: vendorID,
        productID: productID,
        left: left,
        right: right,
        lt: lt,
        rt: rt,
        durationMs: durationMs
      )
    } catch {
      daemonError = formatDaemonError(error)
      return false
    }
  }

  func setSuppressOutput(_ suppress: Bool) async {
    guard daemonConnected else { return }
    try? await client.setSuppressOutput(suppress)
  }

  func setVirtualDeviceMode(_ modeRaw: String) async {
    guard daemonConnected else { return }
    do {
      try await client.setVirtualDeviceMode(modeRaw)
      await syncFromDaemonNow()
    } catch {
      await refreshDaemonHealth()
      daemonError = formatDaemonError(error)
    }
  }

  func setCompatibilityIdentity(_ raw: String) async {
    guard daemonConnected else { return }
    do {
      try await client.setCompatibilityIdentity(raw)
      await syncFromDaemonNow()
    } catch {
      await refreshDaemonHealth()
      daemonError = formatDaemonError(error)
    }
  }

  func setUserSpaceVirtualDeviceEnabled(_ enabled: Bool) async {
    guard daemonConnected else { return }
    do {
      try await client.setUserSpaceVirtualDeviceEnabled(enabled)
      await syncFromDaemonNow()
    } catch {
      await refreshDaemonHealth()
      daemonError = formatDaemonError(error)
    }
  }

  func runVirtualDeviceSelfTest(seconds: Int = 5) async {
    guard daemonConnected else { return }
    do { virtualDeviceSelfTest = try await client.runVirtualDeviceSelfTest(seconds: seconds) } catch
    {
      await refreshDaemonHealth()
      daemonError = formatDaemonError(error)
      virtualDeviceSelfTest = nil
    }
  }

  func refreshVirtualDeviceDiagnostics() async {
    guard daemonConnected else {
      virtualDeviceDiagnostics = nil
      return
    }
    do { virtualDeviceDiagnostics = try await client.getVirtualDeviceDiagnostics() } catch {
      daemonError = formatDaemonError(error)
      virtualDeviceDiagnostics = nil
    }
  }

  func checkForUpdates() async {
    if sparkleUpdates.isConfigured {
      sparkleUpdates.checkForUpdates(nil)
      updateCheckState = .idle
      return
    }

    updateCheckState = .checking
    updateCheckState = await updateChecker.check(
      currentVersion: appVersion,
      includePrereleases: includePrereleaseUpdates
    )
  }

  func openLatestRelease() {
    if case .available(let info) = updateCheckState { NSWorkspace.shared.open(info.htmlURL) }
  }
}
