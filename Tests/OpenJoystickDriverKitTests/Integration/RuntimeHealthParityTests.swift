import Foundation
import Testing

struct RuntimeHealthParityTests {
  @Test
  func cliAndGuiUseTheSharedConfigurableRuntimeSoakSampler() throws {
    let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let command = try source(
      "Sources/OpenJoystickDriver/Commands/RuntimeHealthCommand.swift",
      root: rootURL
    )
    let appModel = try source(
      "Sources/OpenJoystickDriver/App/AppModel/SupportReport.swift",
      root: rootURL
    )
    let modelState = try source(
      "Sources/OpenJoystickDriver/App/AppModel/AppModel.swift",
      root: rootURL
    )
    let view = try source(
      "Sources/OpenJoystickDriver/Views/MenuBarPopoverView/AdvancedCards.swift",
      root: rootURL
    )
    let menuState = try source(
      "Sources/OpenJoystickDriver/Views/MenuBarPopoverView/MenuBarPopoverView.swift",
      root: rootURL
    )
    let report = try source(
      "Sources/OpenJoystickDriverKit/Diagnostics/SupportReport.swift",
      root: rootURL
    )
    let consumerMonitorPath =
      "Sources/OpenJoystickDriverDaemon/ForegroundConsumerOutputMonitor/"
      + "ForegroundConsumerOutputMonitor.swift"
    let consumerMonitor =
      try source(consumerMonitorPath, root: rootURL)
      + source(
        "Sources/OpenJoystickDriverDaemon/ForegroundConsumerOutputMonitor/ConsumerDiscovery.swift",
        root: rootURL
      )
    let consumerProbe = try source(
      "Sources/OpenJoystickDriverDaemon/ForegroundConsumerMemoryProbe.swift",
      root: rootURL
    )
    let daemonMain = try source(
      "Sources/OpenJoystickDriverDaemon/main.swift",
      root: rootURL
    )

    #expect(command.contains("DaemonRuntimeHealthSampler.sample"))
    #expect(appModel.contains("DaemonRuntimeHealthSampler.sample"))
    #expect(command.contains("--seconds 1...86400"))
    #expect(command.contains("--interval-ms 100...60000"))
    #expect(command.contains("--rss-limit-mib 0...65536"))
    #expect(command.contains("--footprint-limit-mib 0...65536"))
    #expect(command.contains("RuntimeHealthPolicy"))
    #expect(appModel.contains("seconds: Int = 60"))
    #expect(appModel.contains("intervalMilliseconds: Int = 1_000"))
    #expect(appModel.contains("residentLimitMiB: Int = 0"))
    #expect(appModel.contains("physicalFootprintLimitMiB: Int = 512"))
    #expect(appModel.contains("stopRuntimeHealthCheck"))
    #expect(modelState.contains("runtimeHealthTask"))
    #expect(menuState.contains("runtimeHealthSeconds = 60"))
    #expect(menuState.contains("runtimeHealthIntervalMilliseconds = 1_000"))
    #expect(menuState.contains("runtimeHealthResidentLimitMiB = 0"))
    #expect(menuState.contains("runtimeHealthFootprintLimitMiB = 512"))
    #expect(view.contains("runtimeHealthSeconds"))
    #expect(view.contains("runtimeHealthIntervalMilliseconds"))
    #expect(view.contains("runtimeHealthResidentLimitMiB"))
    #expect(view.contains("runtimeHealthFootprintLimitMiB"))
    #expect(view.contains("model.runRuntimeHealthCheck"))
    #expect(view.contains("model.stopRuntimeHealthCheck"))
    #expect(view.contains("summary.soakVerdict"))
    #expect(report.contains("RuntimeHealthSummary"))
    #expect(consumerMonitor.contains("let consumerClients = autoreleasepool"))
    #expect(consumerMonitor.contains("ForegroundConsumerHIDManagerState"))
    #expect(consumerMonitor.components(separatedBy: "IOHIDManagerCreate").count == 2)
    #expect(consumerMonitor.contains("consumerHIDManagerState.withOpenManager"))
    #expect(consumerProbe.contains("diagnosticConsumerClientCount"))
    #expect(daemonMain.contains("--probe-foreground-consumer-memory="))
    #expect(consumerMonitor.contains("cachedFrontmostBundleRoot"))
    #expect(!consumerMonitor.contains("await MainActor.run { Self.frontmostBundleRootPath() }"))
    #expect(command.contains("not proof that all leaks are absent"))
  }

  private func source(_ path: String, root: URL) throws -> String {
    try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
  }
}
