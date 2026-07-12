import AppKit
import Foundation
import OpenJoystickDriverKit

@MainActor extension AppModel {
  // MARK: - Private

  func formatDaemonError(_ error: Error) -> String {
    let ns = error as NSError
    if ns.domain == NSCocoaErrorDomain && ns.code == 4099 {
      if let h = daemonHealth, h.isInefficientKillLoop {
        let runs = h.runs.map { "\($0)" } ?? "unknown"
        let active = h.activeCount.map { "\($0)" } ?? "unknown"
        return
          L10n.string("daemon.error.inefficientKill", active, runs)
      }
      return L10n.string("daemon.error.lostApplication")
    }
    if ns.domain == "NSXPCErrorDomain" {
      return L10n.string("daemon.error.lostConnection")
    }
    return ns.localizedDescription
  }

  func poll() async {
    refreshDaemonStatus()
    guard daemonInstalled else {
      daemonConnected = false
      devices = []
      userSpaceVirtualDeviceEnabled = false
      userSpaceVirtualDeviceStatus = "off"
      virtualDeviceDiagnostics = nil
      latestStatusPayload = nil
      appInputMonitoring = "\(await permissionManager.checkAccess())"
      inputMonitoring = "unknown"
      resetDaemonHealthTrend()
      return
    }

    appInputMonitoring = "\(await permissionManager.checkAccess())"
    if !client.isConnected { client.connect() }
    do {
      let status = try await client.getStatus()
      latestStatusPayload = status
      daemonConnected = true
      daemonError = nil
      inputMonitoring = status.inputMonitoring
      devices = status.connectedDevices.map { DeviceViewModel(from: $0) }
      userSpaceVirtualDeviceEnabled = status.userSpaceVirtualDeviceEnabled ?? false
      userSpaceVirtualDeviceStatus = status.userSpaceVirtualDeviceStatus ?? "unknown"
      virtualDeviceMode = status.virtualDeviceMode ?? VirtualDeviceMode.compatUserSpace.rawValue
      outputMode = status.effectiveOutputMode ?? CompositeOutputDispatcher.Mode.primaryOnly.rawValue
      compatibilityIdentity = status.compatibilityIdentity ?? CompatibilityIdentity.sdl2_3.rawValue

      await maybeRefreshDaemonHealth(isConnected: true)
    } catch {
      daemonConnected = false
      devices = []
      latestStatusPayload = nil
      client.disconnect()
      appInputMonitoring = "\(await permissionManager.checkAccess())"
      inputMonitoring = "unknown"

      // When XPC is failing, refresh launchd health immediately so we can explain why.
      await refreshDaemonHealth()

      // If launchd says the job is loaded/running but XPC isn't responding, call that out.
      if let h = daemonHealth, h.pid != nil {
        daemonError =
          L10n.string("daemon.error.runningNoConnection")
      } else {
        daemonError = formatDaemonError(error)
      }
    }
  }

  func maybeRefreshDaemonHealth(isConnected: Bool) async {
    let now = DispatchTime.now().uptimeNanoseconds
    let intervalNs = isConnected ? daemonHealthPollNanosecondsConnected
      : daemonHealthPollNanosecondsDisconnected
    if daemonHealth == nil || now &- lastHealthPollNs >= intervalNs {
      await refreshDaemonHealth()
    }
  }

  func noteDaemonHealth(_ snapshot: DaemonManager.DaemonHealth) {
    let now = DispatchTime.now().uptimeNanoseconds
    if !snapshot.installed || (snapshot.state ?? "").uppercased() == "NOT_LOADED" {
      resetDaemonHealthTrend()
      lastDaemonRuns = snapshot.runs
      lastDaemonPid = snapshot.pid
      return
    }

    if let runs = snapshot.runs {
      if let last = lastDaemonRuns, runs > last {
        for _ in 0..<(runs - last) { daemonStartEventsNs.append(now) }
      }
      lastDaemonRuns = runs
    }

    if let pid = snapshot.pid {
      if let lastPid = lastDaemonPid, pid != lastPid {
        daemonStartEventsNs.append(now)
      }
      lastDaemonPid = pid
    }

    let windowNs: UInt64 = 15 * 1_000_000_000
    daemonStartEventsNs.removeAll { now &- $0 > windowNs }
  }

  func recentDaemonStartCount(windowSeconds: UInt64) -> Int {
    let now = DispatchTime.now().uptimeNanoseconds
    let windowNs = windowSeconds * 1_000_000_000
    return daemonStartEventsNs.filter { now &- $0 <= windowNs }.count
  }

  func resetDaemonHealthTrend() {
    daemonStartEventsNs.removeAll(keepingCapacity: true)
    lastDaemonRuns = nil
    lastDaemonPid = nil
  }

  func ensureRunningFromApplications() -> Bool {
    let path = Bundle.main.bundlePath
    if path.hasPrefix("/Applications/") { return true }
    daemonError =
      L10n.string("daemon.error.requiresApplications", path)
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
      daemonError =
        L10n.string("daemon.error.codesignLaunchFailed", action, error.localizedDescription)
      return false
    }
    if result.timedOut {
      daemonError = L10n.string(
        "daemon.error.codesignLaunchFailed",
        action,
        "verification timed out after 15 seconds"
      )
      return false
    }
    let out = result.output
    if result.terminationStatus == 0 { return true }

    // Keep the UI message self-describing and fix-oriented.
    if out.contains("a sealed resource is missing or invalid") {
      daemonError =
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

    daemonError =
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
