import Foundation
import Testing

struct RemappingCompositionTests {
  @Test func runtimeRoutesDevicePipelinesThroughRemapping() throws {
    let runtime = try source("Sources/OpenJoystickDriver/Service/ApplicationServiceRuntime.swift")

    #expect(runtime.contains("let remappingProfileLibrary = RemappingProfileLibrary()"))
    #expect(runtime.contains("let postEventAccess = CoreGraphicsPostEventAccess()"))
    #expect(runtime.contains("let remappingEngine = RemappingEventEngine("))
    #expect(runtime.contains("CoreGraphicsSystemInputSink(access: postEventAccess)"))
    #expect(runtime.contains("let remappingRouter = RemappingOutputRouter("))
    #expect(runtime.contains("let manager = DeviceManager(dispatcher: remappingRouter)"))
    #expect(!runtime.contains("DeviceManager(dispatcher: dispatcher)"))
    #expect(runtime.contains("compatibility: dispatcher"))
    #expect(!runtime.contains("manager.setupGracefulShutdown"))
  }

  @Test func foregroundConsumerGateIsCompatibilityOnlyAndCausal() throws {
    let runtime = try source("Sources/OpenJoystickDriver/Service/ApplicationServiceRuntime.swift")
    let monitor = try source(
      "Sources/OpenJoystickDriver/Service/ForegroundConsumerOutputMonitor/"
        + "ForegroundConsumerOutputMonitor.swift"
    )

    #expect(runtime.contains("try await remappingRouter.foregroundStateDidChange("))
    #expect(runtime.contains("compatibilityOutputAllowed: allowed"))
    #expect(monitor.contains("await compatibilityOutputGate(allowOutput)"))
    #expect(!monitor.contains("DeviceManager"))
    #expect(!monitor.contains("setExternalOutputAllowed"))
    #expect(monitor.contains("await compatibilityRouteHandler("))
  }

  @Test func suppressionRepliesAfterRouterDrain() throws {
    let requests = try source(
      "Sources/OpenJoystickDriver/Service/ApplicationServiceServer/Requests.swift"
    )
    let method = try #require(requests.range(of: "public func setSuppressOutput"))
    let tail = requests[method.lowerBound...]
    let routerCall = try #require(tail.range(
      of: "try await remappingRouter.setOutputSuppressed(suppress)"
    ))
    let successReply = try #require(tail.range(of: "callback.call(true)"))

    #expect(routerCall.lowerBound < successReply.lowerBound)
    #expect(!tail.prefix { $0 != "}" }.contains("dispatcher.suppressOutput"))
  }

  @Test func runtimeLifecycleStartsTickerAndDrainsAfterPipelinesStop() throws {
    let runtime = try source("Sources/OpenJoystickDriver/Service/ApplicationServiceRuntime.swift")
    let tickerStart = try #require(runtime.range(of: "remappingRouter.startTicker()"))
    let managerStart = try #require(runtime.range(of: "Task { await manager.start() }"))
    let monitorStop = try #require(runtime.range(of: "foregroundConsumerOutputMonitor.stop()"))
    let serverStop = try #require(runtime.range(of: "applicationServiceServer.stop()"))
    let managerStop = try #require(runtime.range(of: "await manager.stop()"))
    let routerShutdown = try #require(runtime.range(of: "try await remappingRouter.shutdown()"))

    #expect(tickerStart.lowerBound < managerStart.lowerBound)
    #expect(monitorStop.lowerBound < serverStop.lowerBound)
    #expect(serverStop.lowerBound < managerStop.lowerBound)
    #expect(managerStop.lowerBound < routerShutdown.lowerBound)
    #expect(runtime.contains("await self.stop()\n            exit(0)"))
  }

  @Test func serverRetainsSharedRemappingDependencies() throws {
    let server = try source(
      "Sources/OpenJoystickDriver/Service/ApplicationServiceServer/Server.swift"
    )

    #expect(server.contains("let remappingProfileLibrary: RemappingProfileLibrary"))
    #expect(server.contains("let remappingRouter: RemappingOutputRouter"))
    #expect(server.contains("let postEventAccess: CoreGraphicsPostEventAccess"))
    #expect(server.contains("self.remappingProfileLibrary = remappingProfileLibrary"))
    #expect(server.contains("self.remappingRouter = remappingRouter"))
    #expect(server.contains("self.postEventAccess = postEventAccess"))
  }

  private func source(_ path: String) throws -> String {
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
  }
}
