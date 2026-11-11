import Carbon
import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverPresentation

@Suite(.serialized)
struct PauseShortcutPresentationTests {
  private func pad(
    _ token: String,
    _ state: ControllerSessionState
  ) -> ApplicationServiceDeviceDescription {
    ApplicationServiceDeviceDescription(
      name: "Test Pad",
      vendorID: 0x1234,
      productID: 0x5678,
      protocolBinding: ProtocolBindingID(.hidDescriptor),
      connection: "USB",
      discoverySource: .rawUSB,
      serialNumber: nil,
      bindingResult: .hidDescriptorFixture,
      recordServer: .system,
      recordAccessRoute: .system,
      sessionState: state,
      sessionToken: .fixture(token)
    )
  }

  private func requests(for devices: [ApplicationServiceDeviceDescription]) async -> [String] {
    let gateway = GatewayStub(
      statusPayload: ApplicationServiceStatusPayload(
        inputRead: .granted,
        inputInject: .granted,
        connectedDevices: devices,
        userSpaceVirtualDeviceEnabled: true,
        userSpaceVirtualDeviceStatus: .backend("ready")
      )
    )
    let viewModel = await MainActor.run { RuntimeViewModel(gateway: gateway) }
    await viewModel.refresh()
    await viewModel.togglePauseAll()
    return await gateway.sessionRequests
  }

  @Test
  func pausingSuspendsEveryActiveControllerAndSkipsSuspendedOnes() async {
    let sent = await requests(for: [pad("a", .active), pad("b", .suspended), pad("c", .active)])

    #expect(sent.count == 2)
    #expect(sent.allSatisfy { $0.hasPrefix("suspend") })
    #expect(sent[0].contains("a") && sent[1].contains("c"))
  }

  @Test
  func whenEveryControllerIsSuspendedTheShortcutResumesThem() async {
    let sent = await requests(for: [pad("a", .suspended), pad("b", .suspended)])

    #expect(sent.count == 2)
    #expect(sent.allSatisfy { $0.hasPrefix("resume") })
  }

  @Test
  func withNoControllerNothingIsRequested() async {
    #expect(await requests(for: []).isEmpty)
  }

  @Test
  func modifiersMapToTheCarbonMasks() {
    #expect(
      PauseHotKey.carbonModifiers([.command, .control, .option, .shift])
        == UInt32(cmdKey | controlKey | optionKey | shiftKey)
    )
    #expect(PauseHotKey.carbonModifiers([.control, .option]) == UInt32(controlKey | optionKey))
  }

  @Test
  func theDisplayUsesTheMenuGlyphsInTheMacOSOrder() throws {
    #expect(
      try PauseShortcutDisplay.text(PauseShortcut(parsing: "command+control+option+shift+P"))
        == "⌃⌥⇧⌘P"
    )
    #expect(try PauseShortcutDisplay.text(PauseShortcut(parsing: "control+Space")) == "⌃Space")
  }

  @Test
  @MainActor
  func theHotKeyRegistersAndReleasesAShortcut() throws {
    let hotKey = PauseHotKey {}
    try hotKey.register(PauseShortcut(parsing: "control+option+command+shift+F12"))
    #expect(hotKey.isRegistered)
    try hotKey.register(nil)
    #expect(!hotKey.isRegistered)
  }

  @Test
  @MainActor
  func theModelStoresAndPublishesTheShortcut() throws {
    let settings = SettingsStore(directory: RootedDataDirectory.temporary())
    let model = SettingsPreferencesModel(
      testNotifications: TestNotificationRequestStub(),
      settings: settings,
      launchAtLogin: LaunchAtLoginStub(isEnabled: false),
      notificationAuthorization: NotificationAuthorizationStub(state: .denied)
    )
    #expect(model.pauseShortcut == nil)

    let shortcut = try PauseShortcut(parsing: "control+option+P")
    model.setPauseShortcut(shortcut)
    #expect(model.pauseShortcut == shortcut)
    #expect(try settings.pauseShortcut() == shortcut)

    model.setPauseShortcut(nil)
    #expect(model.pauseShortcut == nil)
    #expect(try settings.pauseShortcut() == nil)
  }
}
