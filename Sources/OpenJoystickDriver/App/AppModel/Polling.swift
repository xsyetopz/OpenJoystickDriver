import AppKit
import Foundation
import OpenJoystickDriverKit

@MainActor extension AppModel {
  // MARK: - Private

  func formatApplicationServiceError(_ error: Error) -> String {
    if error is ApplicationServiceClientError {
      return L10n.string("service.error.lostConnection")
    }
    return error.localizedDescription
  }

  func poll() async {
    refreshApplicationServiceStatus()
    let localPermissions = await permissionManager.checkAccess()
    inputMonitoring = localPermissions.inputMonitoring.rawValue
    accessibility = localPermissions.accessibility.rawValue
    if !client.isConnected { client.connect() }
    do {
      let status = try await client.getStatus()
      latestStatusPayload = status
      serviceConnected = true
      serviceError = nil
      inputMonitoring = status.inputMonitoring
      accessibility = status.accessibility
      devices = status.connectedDevices.map { DeviceViewModel(from: $0) }
      userSpaceVirtualDeviceEnabled = status.userSpaceVirtualDeviceEnabled ?? false
      userSpaceVirtualDeviceStatus = status.userSpaceVirtualDeviceStatus ?? "unknown"
      compatibilityIdentity = status.compatibilityIdentity ?? CompatibilityIdentity.sdl2_3.rawValue

      await maybeRefreshApplicationServiceHealth(isConnected: true)
    } catch {
      serviceConnected = false
      devices = []
      latestStatusPayload = nil
      client.disconnect()
      let localPermissions = await permissionManager.checkAccess()
      inputMonitoring = localPermissions.inputMonitoring.rawValue
      accessibility = localPermissions.accessibility.rawValue

      // Refresh process/socket health immediately so the UI can distinguish a stopped app
      // from a live runtime that rejected or failed the request.
      await refreshApplicationServiceHealth()

      if let h = serviceHealth, h.pid != nil {
        serviceError =
          L10n.string("service.error.runningNoConnection")
      } else {
        serviceError = formatApplicationServiceError(error)
      }
    }
  }

  func maybeRefreshApplicationServiceHealth(isConnected: Bool) async {
    let now = DispatchTime.now().uptimeNanoseconds
    let intervalNs = isConnected ? serviceHealthPollNanosecondsConnected
      : serviceHealthPollNanosecondsDisconnected
    if serviceHealth == nil || now &- lastHealthPollNs >= intervalNs {
      await refreshApplicationServiceHealth()
    }
  }

  func noteApplicationServiceHealth(
    _ snapshot: ApplicationServiceManager.ApplicationServiceHealth
  ) {
    let now = DispatchTime.now().uptimeNanoseconds
    if !snapshot.installed || (snapshot.state ?? "").uppercased() == "NOT_LOADED" {
      resetApplicationServiceHealthTrend()
      lastServicePID = snapshot.pid
      return
    }

    if let pid = snapshot.pid {
      if let lastPid = lastServicePID, pid != lastPid {
        serviceStartEventsNanoseconds.append(now)
      }
      lastServicePID = pid
    }

    let windowNs: UInt64 = 15 * 1_000_000_000
    serviceStartEventsNanoseconds.removeAll { now &- $0 > windowNs }
  }

  func recentServiceStartCount(windowSeconds: UInt64) -> Int {
    let now = DispatchTime.now().uptimeNanoseconds
    let windowNs = windowSeconds * 1_000_000_000
    return serviceStartEventsNanoseconds.filter { now &- $0 <= windowNs }.count
  }

  func resetApplicationServiceHealthTrend() {
    serviceStartEventsNanoseconds.removeAll(keepingCapacity: true)
    lastServicePID = nil
  }

  func ensureRunningFromApplications() -> Bool {
    let path = Bundle.main.bundlePath
    if path.hasPrefix("/Applications/") { return true }
    serviceError =
      L10n.string("service.error.requiresApplications", path)
    return false
  }

  func ensureBundleSignatureValid(for action: String) async -> Bool {
    // SMAppService refuses to register an agent if the app bundle has been modified
    // after signing (e.g. copying the .dext into Contents/Library/SystemExtensions).
    //
    // When that happens, codesign reports:
    //   "a sealed resource is missing or invalid" + "file added: ..."
    let appPath = Bundle.main.bundlePath
    let result: BoundedProcessResult
    do {
      result = try await Task.detached(priority: .userInitiated) {
        try BoundedProcessRunner.run(
          executableURL: URL(fileURLWithPath: "/usr/bin/codesign"),
          arguments: ["--verify", "--deep", "--strict", "--verbose=2", appPath],
          timeoutSeconds: 15,
          maximumOutputBytes: 262_144
        )
      }.value
    } catch {
      serviceError =
        L10n.string("service.error.codesignLaunchFailed", action, error.localizedDescription)
      return false
    }
    if result.timedOut {
      serviceError = L10n.string(
        "service.error.codesignLaunchFailed",
        action,
        "verification timed out after 15 seconds"
      )
      return false
    }
    let out = result.output
    if result.terminationStatus == 0 { return true }

    // Keep the UI message self-describing and fix-oriented.
    if out.contains("a sealed resource is missing or invalid") {
      serviceError =
        """
        \(action) failed: this app bundle's signature is INVALID.
        macOS thinks it was modified after signing.

        Typical cause: the system extension (.dext) was copied into the app without re-signing.

        Fix (no reboot):
          1) Run: ./scripts/ojd rebuild-fast dev
          2) Then re-try \(action)

        Diagnostic command:
          /usr/bin/codesign --verify --deep --strict --verbose=2 \(appPath)
        """
      return false
    }

    serviceError =
      """
      \(action) failed: app signature verification failed.

      Diagnostic output:
      \(out.trimmingCharacters(in: .whitespacesAndNewlines))
      """
    return false
  }

  func startPolling() {
    pollTask = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: appModelPollNanoseconds)
        await self?.poll()
      }
    }
  }
}
