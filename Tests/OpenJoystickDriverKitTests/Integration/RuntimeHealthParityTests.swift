import Foundation
import Testing

struct RuntimeHealthParityTests {
  @Test
  func cliOwnsRuntimeSoakWithoutGUIEntryPoint() throws {
    let root = try RepositoryRoot.from()
    let command = try source(
      "Sources/OpenJoystickDriver/Commands/RuntimeHealthCommand.swift",
      root: root
    )
    let appModel =
      try source(
        "Sources/OpenJoystickDriver/App/AppModel/AppModel.swift",
        root: root
      )
      + source(
        "Sources/OpenJoystickDriver/App/AppModel/SupportReport.swift",
        root: root
      )
    let view =
      try source(
        "Sources/OpenJoystickDriver/Views/MenuBarPopoverView/MenuBarPopoverView.swift",
        root: root
      )
      + source(
        "Sources/OpenJoystickDriver/Views/MenuBarPopoverView/AdvancedCards.swift",
        root: root
      )
    let consumerMonitorPath =
      "Sources/OpenJoystickDriver/Service/ForegroundConsumerOutputMonitor/"
      + "ForegroundConsumerOutputMonitor.swift"
    let consumerDiscoveryPath =
      "Sources/OpenJoystickDriver/Service/ForegroundConsumerOutputMonitor/"
      + "Discovery.swift"
    let consumerMonitor =
      try source(consumerMonitorPath, root: root)
      + source(consumerDiscoveryPath, root: root)

    #expect(command.contains("ApplicationServiceRuntimeHealthSampler.sample"))
    #expect(command.contains("--seconds 1...86400"))
    #expect(command.contains("--interval-ms 100...60000"))
    #expect(command.contains("--rss-limit-mib 0...65536"))
    #expect(command.contains("--footprint-limit-mib 0...65536"))
    #expect(command.contains("RuntimeHealthPolicy"))
    #expect(command.contains("not proof that all leaks are absent"))

    for applicationSource in [appModel, view] {
      #expect(!applicationSource.contains("runtimeHealthRunning"))
      #expect(!applicationSource.contains("runtimeHealthSummary"))
      #expect(!applicationSource.contains("runRuntimeHealthCheck"))
      #expect(!applicationSource.contains("runtimeHealthRow"))
      #expect(!applicationSource.contains("runtimeHealth."))
    }

    #expect(consumerMonitor.contains("let consumerClients = autoreleasepool"))
    #expect(consumerMonitor.contains("ForegroundConsumerHIDManagerState"))
    #expect(consumerMonitor.components(separatedBy: "IOHIDManagerCreate").count == 2)
    #expect(consumerMonitor.contains("consumerHIDManagerState.withOpenManager"))
    #expect(consumerMonitor.contains("cachedFrontmostBundleRoot"))
    #expect(!consumerMonitor.contains("await MainActor.run { Self.frontmostBundleRootPath() }"))
  }

  private func source(_ path: String, root: URL) throws -> String {
    try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
  }
}
