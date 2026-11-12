import AppKit
import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverPresentation

/// A command-line tool link in a temporary folder, so no test reads or changes the system link.
struct CommandLineToolSandbox {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "CommandLineToolSandbox.\(UUID().uuidString)"
  )
  let link: CommandLineToolLink

  init() throws {
    let executable = root.appendingPathComponent("App/OpenJoystickDriver")
    try FileManager.default.createDirectory(
      at: executable.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try Data().write(to: executable)
    link = CommandLineToolLink(
      linkURL: root.appendingPathComponent("bin/ojd"),
      executableURL: executable
    ) { _ in }
  }

  @MainActor
  func model() -> CommandLineToolModel { CommandLineToolModel(link: link) }

  func remove() { try? FileManager.default.removeItem(at: root) }
}

@Suite
@MainActor
struct SettingsWindowControllerTests {
  private func controller(
    gateway: GatewayStub,
    developerTools: Bool = true,
    commandLineTool: CommandLineToolModel
  ) throws -> (SettingsWindowController, SettingsPreferencesModel) {
    let settings = SettingsStore(directory: RootedDataDirectory.temporary())
    try settings.set(.developerTools, to: developerTools)
    try settings.setInterfaceLevel(.advanced)
    let preferences = SettingsPreferencesModel(
      testNotifications: TestNotificationRequestStub(),
      settings: settings,
      launchAtLogin: LaunchAtLoginStub(isEnabled: false),
      notificationAuthorization: NotificationAuthorizationStub(state: .denied)
    )
    let controller = SettingsWindowController(
      gateway: gateway,
      runtime: RuntimeViewModel(gateway: gateway),
      preferences: preferences,
      commandLineTool: commandLineTool
    ) { _ in }
    return (controller, preferences)
  }

  private func gatedGateway() async -> GatewayStub {
    let gateway = GatewayStub()
    await gateway.setStatusReadsAreGated(true)
    return gateway
  }

  private func startRead(_ controller: SettingsWindowController, _ gateway: GatewayStub) async {
    controller.showSettings(pane: .advanced)
    await gateway.waitForStatusCall(count: 1)
  }

  private func finishRead(_ controller: SettingsWindowController, _ gateway: GatewayStub) async {
    await gateway.resumeNextStatusRead()
    await waitUntil("the read ends") { !controller.developerTools.hasActiveOperation }
  }

  @Test
  func closingTheWindowDuringTheReadLeavesTheDiagnosticsNotLoaded() async throws {
    let gateway = await gatedGateway()
    let sandbox = try CommandLineToolSandbox()
    defer { sandbox.remove() }
    let (controller, _) = try controller(gateway: gateway, commandLineTool: sandbox.model())
    await startRead(controller, gateway)

    controller.close()
    await finishRead(controller, gateway)

    #expect(controller.developerTools.loadState == .idle)
  }

  @Test
  func switchingPaneDuringTheReadLeavesTheDiagnosticsNotLoaded() async throws {
    let gateway = await gatedGateway()
    let sandbox = try CommandLineToolSandbox()
    defer { sandbox.remove() }
    let (controller, _) = try controller(gateway: gateway, commandLineTool: sandbox.model())
    await startRead(controller, gateway)

    controller.showSettings(pane: .general)
    await finishRead(controller, gateway)

    #expect(controller.developerTools.loadState == .idle)
  }

  @Test
  func turningDeveloperToolsOffDuringTheReadLeavesTheDiagnosticsNotLoaded() async throws {
    let gateway = await gatedGateway()
    let sandbox = try CommandLineToolSandbox()
    defer { sandbox.remove() }
    let (controller, preferences) = try controller(
      gateway: gateway,
      commandLineTool: sandbox.model()
    )
    await startRead(controller, gateway)

    preferences.setDeveloperToolsEnabled(false)
    await waitUntil("the tools stop") { controller.developerTools.loadState == .idle }
    await finishRead(controller, gateway)

    #expect(controller.developerTools.loadState == .idle)
  }

  @Test
  func theCommandLineToolLinkIsReadWhenAdvancedIsShownNotWhenTheControllerIsMade() throws {
    let sandbox = try CommandLineToolSandbox()
    defer { sandbox.remove() }
    let model = sandbox.model()
    let (controller, _) = try controller(gateway: GatewayStub(), commandLineTool: model)
    try sandbox.link.install()
    #expect(model.status.state == .missing)

    controller.showSettings(pane: .advanced)
    controller.close()

    #expect(model.status.state == .installed)
  }
}
