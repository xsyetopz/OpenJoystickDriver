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
      daemonUserSpaceVirtualDeviceStatus = "off"
      userSpaceVirtualDeviceStatus = "off"
      virtualDeviceDiagnostics = nil
      appInputMonitoring = "\(await permissionManager.checkAccess())"
      inputMonitoring = "unknown"
      daemonAccessibility = "unknown"
      resetDaemonHealthTrend()
      return
    }

    appInputMonitoring = "\(await permissionManager.checkAccess())"
    if !client.isConnected { client.connect() }
    do {
      let status = try await client.getStatus()
      daemonConnected = true
      daemonError = nil
      let probedDaemonInputMonitoring = await probeBundledDaemonInputMonitoringState()
      inputMonitoring = mergeDaemonInputMonitoringStatus(
        xpc: status.inputMonitoring,
        probed: probedDaemonInputMonitoring
      )
      daemonAccessibility = status.accessibility ?? "unknown"
      devices = status.connectedDevices.map { DeviceViewModel(from: $0) }
      userSpaceVirtualDeviceEnabled = status.userSpaceVirtualDeviceEnabled ?? false
      daemonUserSpaceVirtualDeviceStatus = status.userSpaceVirtualDeviceStatus ?? "unknown"
      virtualDeviceMode = status.virtualDeviceMode ?? VirtualDeviceMode.compatUserSpace.rawValue
      outputMode = status.effectiveOutputMode ?? CompositeOutputDispatcher.Mode.primaryOnly.rawValue
      compatibilityIdentity = status.compatibilityIdentity ?? CompatibilityIdentity.sdl2_3.rawValue
      userSpaceVirtualDeviceStatus = visibleCompatibilityStatus(
        daemonStatus: daemonUserSpaceVirtualDeviceStatus
      )

      await maybeRefreshDaemonHealth(isConnected: true)
    } catch {
      daemonConnected = false
      devices = []
      client.disconnect()
      appInputMonitoring = "\(await permissionManager.checkAccess())"
      inputMonitoring = "unknown"
      daemonAccessibility = "unknown"

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

  func mergeDaemonInputMonitoringStatus(xpc: String, probed: String) -> String {
    if xpc == "granted" || xpc == "denied" { return xpc }
    if probed == "granted" { return probed }
    return xpc
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

  func ensureBundleSignatureValid(for action: String) -> Bool {
    // SMAppService refuses to register an agent if the app bundle has been modified
    // after signing (e.g. copying the .dext into Contents/Library/SystemExtensions).
    //
    // When that happens, codesign reports:
    //   "a sealed resource is missing or invalid" + "file added: ..."
    let appPath = Bundle.main.bundlePath
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
    process.arguments = ["--verify", "--deep", "--strict", "--verbose=2", appPath]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    do {
      try process.run()
    } catch {
      daemonError =
        L10n.string("daemon.error.codesignLaunchFailed", action, error.localizedDescription)
      return false
    }
    process.waitUntilExit()
    let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    if process.terminationStatus == 0 { return true }

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
    startCompatibilityOutputBridge()
  }

  func startCompatibilityOutputBridge() {
    guard compatibilityOutputTask == nil else { return }
    compatibilityOutputTask = Task { [weak self] in
      while !Task.isCancelled {
        guard let self else { return }
        try? await Task.sleep(nanoseconds: self.compatibilityOutputBridgePollNanoseconds())
        await self.syncCompatibilityOutputBridge()
      }
    }
  }

  func compatibilityOutputBridgePollNanoseconds() -> UInt64 {
    if isAppOwnedCompatibilityOutputActive(daemonStatus: daemonUserSpaceVirtualDeviceStatus) {
      return compatibilityOutputBridgeFastPollNanoseconds
    }
    return appModelPollNanoseconds
  }

  func isAppOwnedCompatibilityOutputActive(daemonStatus: String) -> Bool {
    daemonStatus.hasPrefix("error:")
      && (virtualDeviceMode == VirtualDeviceMode.compatUserSpace.rawValue
        || virtualDeviceMode == VirtualDeviceMode.both.rawValue)
  }

  func visibleCompatibilityStatus(daemonStatus: String) -> String {
    guard isAppOwnedCompatibilityOutputActive(daemonStatus: daemonStatus) else {
      return daemonStatus
    }
    let bridgeStatus = compatibilityOutputBridge.status
    if daemonStatus.hasPrefix("error:") && bridgeStatus.hasPrefix("on") {
      return bridgeStatus
    }
    return daemonStatus
  }

  func syncCompatibilityOutputBridge() async {
    guard daemonConnected else {
      compatibilityOutputBridge.stop()
      return
    }

    let daemonStatus = daemonUserSpaceVirtualDeviceStatus
    let identity = CompatibilityIdentity(rawValue: compatibilityIdentity) ?? .sdl2_3
    let identifiers = devices.map {
      DeviceIdentifier(
        vendorID: $0.vendorID,
        productID: $0.productID,
        serialNumber: $0.serialNumber
      )
    }
    await compatibilityOutputBridge.update(
      isEnabled: isAppOwnedCompatibilityOutputActive(daemonStatus: daemonStatus),
      identity: identity,
      devices: identifiers
    ) { [client] identifier in
      try? await client.deviceInputState(
        vendorID: identifier.vendorID,
        productID: identifier.productID
      )
    }
    userSpaceVirtualDeviceStatus = visibleCompatibilityStatus(
      daemonStatus: daemonStatus
    )
  }
}
