import AppKit
import Foundation
import OpenJoystickDriverKit

@MainActor extension AppModel {
  // MARK: - Application service operations

  func deviceInputState(vendorID: UInt16, productID: UInt16) async -> DeviceInputState? {
    guard serviceConnected else { return nil }
    return try? await client.deviceInputState(vendorID: vendorID, productID: productID)
  }

  func packetLog(vendorID: UInt16, productID: UInt16) async -> [PacketLogEntry] {
    guard serviceConnected else { return [] }
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
    guard serviceConnected else { return false }
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
      serviceError = formatApplicationServiceError(error)
      return false
    }
  }

  func setPhysicalPlayerIndicator(
    vendorID: UInt16,
    productID: UInt16,
    indicator: PhysicalPlayerIndicator
  ) async -> Bool {
    guard serviceConnected else { return false }
    do {
      return try await client.setPhysicalPlayerIndicator(
        vendorID: vendorID,
        productID: productID,
        indicator: indicator
      )
    } catch {
      serviceError = formatApplicationServiceError(error)
      return false
    }
  }

  func setPhysicalColor(
    vendorID: UInt16,
    productID: UInt16,
    red: UInt8,
    green: UInt8,
    blue: UInt8
  ) async -> Bool {
    guard serviceConnected else { return false }
    do {
      return try await client.setPhysicalColor(
        vendorID: vendorID,
        productID: productID,
        red: red,
        green: green,
        blue: blue
      )
    } catch {
      serviceError = formatApplicationServiceError(error)
      return false
    }
  }

  func setPhysicalBrightness(
    vendorID: UInt16,
    productID: UInt16,
    brightness: UInt8
  ) async -> Bool {
    guard serviceConnected else { return false }
    do {
      return try await client.setPhysicalBrightness(
        vendorID: vendorID,
        productID: productID,
        brightness: brightness
      )
    } catch {
      serviceError = formatApplicationServiceError(error)
      return false
    }
  }

  func setSuppressOutput(_ suppress: Bool) async {
    guard serviceConnected else { return }
    try? await client.setSuppressOutput(suppress)
  }

  func setVirtualDeviceMode(_ modeRaw: String) async {
    guard serviceConnected else { return }
    do {
      try await client.setVirtualDeviceMode(modeRaw)
      await syncFromApplicationServiceNow()
    } catch {
      await refreshApplicationServiceHealth()
      serviceError = formatApplicationServiceError(error)
    }
  }

  func setCompatibilityIdentity(_ raw: String) async {
    guard serviceConnected else { return }
    do {
      try await client.setCompatibilityIdentity(raw)
      await syncFromApplicationServiceNow()
    } catch {
      await refreshApplicationServiceHealth()
      serviceError = formatApplicationServiceError(error)
    }
  }

  func setUserSpaceVirtualDeviceEnabled(_ enabled: Bool) async {
    guard serviceConnected else { return }
    do {
      try await client.setUserSpaceVirtualDeviceEnabled(enabled)
      await syncFromApplicationServiceNow()
    } catch {
      await refreshApplicationServiceHealth()
      serviceError = formatApplicationServiceError(error)
    }
  }

  func setOutputMode(_ modeRaw: String) async {
    guard serviceConnected else { return }
    do {
      try await client.setOutputMode(modeRaw)
      await syncFromApplicationServiceNow()
    } catch {
      await refreshApplicationServiceHealth()
      serviceError = formatApplicationServiceError(error)
    }
  }

  func resetSettings() async {
    guard serviceConnected else { return }
    do {
      guard try await client.resetSettings() else {
        serviceError = L10n.string("settings.resetFailed")
        return
      }
      await syncFromApplicationServiceNow()
    } catch {
      await refreshApplicationServiceHealth()
      serviceError = formatApplicationServiceError(error)
    }
  }

  func runVirtualDeviceSelfTest(seconds: Int = 5) async {
    guard serviceConnected else { return }
    do {
      virtualDeviceSelfTest = try await client.runVirtualDeviceSelfTest(seconds: seconds)
    } catch {
      await refreshApplicationServiceHealth()
      serviceError = formatApplicationServiceError(error)
      virtualDeviceSelfTest = nil
    }
  }

  func refreshVirtualDeviceDiagnostics() async {
    guard serviceConnected else {
      virtualDeviceDiagnostics = nil
      return
    }
    do {
      virtualDeviceDiagnostics = try await client.getVirtualDeviceDiagnostics()
    } catch {
      serviceError = formatApplicationServiceError(error)
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
    if case .available(let info) = updateCheckState {
      NSWorkspace.shared.open(info.htmlURL)
    }
  }
}
