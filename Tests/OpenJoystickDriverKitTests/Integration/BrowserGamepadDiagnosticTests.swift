import Foundation
import Testing

struct BrowserGamepadDiagnosticTests {
  @Test
  func cliRoutesToPrivacyReviewableBrowserGamepadSurface() throws {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let diagnose = try source(
      "Sources/OpenJoystickDriver/Commands/DiagnoseCommand.swift",
      root: root
    )
    let command = try source(
      "Sources/OpenJoystickDriver/Commands/BrowserGamepadDiagnosticCommand.swift",
      root: root
    )
    let server = try source(
      "Sources/OpenJoystickDriver/Commands/BrowserGamepadLocalServer.swift",
      root: root
    )
    let service = try source(
      "Sources/OpenJoystickDriver/Commands/BrowserGamepadDiagnosticService.swift",
      root: root
    )
    let appModel = try source(
      "Sources/OpenJoystickDriver/App/AppModel/BrowserGamepadDiagnostic.swift",
      root: root
    )
    let view = try source(
      "Sources/OpenJoystickDriver/Views/MenuBarPopoverView/DiagnosticCards.swift",
      root: root
    )
    let appDelegate = try source(
      "Sources/OpenJoystickDriver/App/AppDelegate.swift",
      root: root
    )
    let page = try source(
      "Sources/OpenJoystickDriver/Resources/Diagnostics/browser-gamepad.html",
      root: root
    )

    #expect(diagnose.contains("case \"browser-gamepad\""))
    #expect(command.contains("BrowserGamepadDiagnosticService.start"))
    #expect(command.contains("BrowserGamepadDiagnosticService.open"))
    #expect(service.contains("BrowserGamepadLocalServer"))
    #expect(service.contains("127.0.0.1"))
    #expect(server.contains("Darwin.bind"))
    #expect(server.contains("inet_addr(\"127.0.0.1\")"))
    #expect(server.contains("Content-Security-Policy"))
    #expect(server.contains("connect-src 'self'"))
    #expect(server.contains(#"request.method == "POST""#))
    #expect(server.contains(#"request.path == "/snapshot""#))
    #expect(server.contains("maximumSnapshotBytes"))
    #expect(server.contains("encodedSnapshots"))
    #expect(command.contains("Snapshot submission stays on loopback"))
    #expect(command.contains(#"case "--output""#))
    #expect(command.contains("session.encodedSnapshots()"))
    #expect(!command.contains("setCompatibilityIdentity"))
    #expect(appModel.contains("BrowserGamepadDiagnosticService.start"))
    #expect(appModel.contains("BrowserGamepadDiagnosticService.openAsync"))
    #expect(appModel.contains("stopBrowserGamepadDiagnostic"))
    #expect(appModel.contains("browserGamepadSnapshotCount"))
    #expect(view.contains("browserDiagnostic.snapshotCount"))
    #expect(view.contains("browserGamepadTarget"))
    #expect(view.contains("browserGamepadPort"))
    #expect(view.contains("browserGamepadSeconds"))
    #expect(view.contains("BrowserGamepadTarget.allCases"))
    #expect(view.contains("in: 1...3_600"))
    #expect(command.contains("(1...3_600).contains(seconds)"))
    #expect(modelContainsSharedService(appModel))
    #expect(view.contains("model.startBrowserGamepadDiagnostic"))
    #expect(view.contains("model.stopBrowserGamepadDiagnostic"))
    #expect(appDelegate.contains("applicationWillTerminate"))
    #expect(appDelegate.contains("model.stopBrowserGamepadDiagnostic"))

    #expect(page.contains("navigator.getGamepads"))
    #expect(page.contains("gamepadconnected"))
    #expect(page.contains("gamepaddisconnected"))
    #expect(page.contains("duplicateGamepads"))
    #expect(page.contains("requestAnimationFrame"))
    #expect(page.contains("buttonTransitions"))
    #expect(page.contains("maxAxisDelta"))
    #expect(page.contains("\"dual-rumble\""))
    #expect(page.contains("\"trigger-rumble\""))
    #expect(page.contains("leftTrigger"))
    #expect(page.contains("rightTrigger"))
    #expect(page.contains("navigator.clipboard.writeText"))
    #expect(page.contains("URL.createObjectURL"))
    #expect(page.contains(#"fetch("/snapshot""#))
    #expect(page.contains(#"getElementById("submit-json")"#))
    #expect(!page.contains("XMLHttpRequest"))
    #expect(!page.contains("WebSocket"))
    #expect(!page.contains("sendBeacon"))
  }

  private func modelContainsSharedService(_ source: String) -> Bool {
    source.contains("BrowserGamepadDiagnosticService.start")
      && source.contains("BrowserGamepadDiagnosticService.openAsync")
  }

  private func source(_ path: String, root: URL) throws -> String {
    try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
  }
}
