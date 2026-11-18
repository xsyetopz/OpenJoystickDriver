import AppKit
import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverPresentation

@Suite
struct NotificationTests {
  @Test
  func statusItemImageAlwaysTemplateSymbol() {
    for name in ["gamecontroller", "exclamationmark.triangle"] {
      let image = MenuBarStatusItemImage.make(symbolName: name, accessibilityDescription: "x")
      #expect(image?.isTemplate == true, "\(name)")
    }
  }

  @Test
  @MainActor
  func permissionModelPublishesResolvedAuthorizationState() async {
    let authorization = NotificationPermissionAuthorizationStub(state: .allowed)
    let model = NotificationPermissionModel(authorization: authorization)

    model.refresh()
    await waitUntil("the permission state resolves") { model.state != .checking }

    #expect(model.state == .allowed)
  }

  @Test
  @MainActor
  func permissionModelPublishesBannerAndSoundSettings() async {
    let authorization = NotificationPermissionAuthorizationStub(
      state: .allowed,
      alertStyle: .none,
      soundsEnabled: false
    )
    let model = NotificationPermissionModel(authorization: authorization)

    model.refresh()
    await waitUntil("the permission state resolves") { model.state != .checking }

    #expect(model.settings.alertStyle == .none)
    #expect(model.settings.soundsEnabled == false)
  }

  @Test
  func detectsControllerAndProfileTransitionsWithoutBootNoise() {
    let before = RuntimeNotificationSnapshot(
      controllers: ["old": "Old Controller"],
      activeProfiles: ["1:2": "Desktop"]
    )
    let after = RuntimeNotificationSnapshot(
      controllers: ["new": "New Controller"],
      activeProfiles: ["1:2": "Racing"]
    )

    #expect(
      RuntimeNotificationDiff.events(from: before, to: after) == [
        .controllerConnected("New Controller"), .controllerDisconnected("Old Controller"),
        .activeProfileChanged(from: "Desktop", to: "Racing"),
      ]
    )
  }

  @Test
  func detectsProfileDeactivation() {
    let before = RuntimeNotificationSnapshot(controllers: [:], activeProfiles: ["1:2": "Desktop"])
    let after = RuntimeNotificationSnapshot(controllers: [:], activeProfiles: [:])

    #expect(
      RuntimeNotificationDiff.events(from: before, to: after) == [
        .activeProfileChanged(from: "Desktop", to: nil)
      ]
    )
  }

  @Test
  func reportsControllerHealthLossOnce() {
    let healthy = RuntimeControllerHealthSnapshot(name: "DualShock 4", state: .healthy)
    let stale = RuntimeControllerHealthSnapshot(name: "DualShock 4", state: .stale)
    let before = RuntimeNotificationSnapshot(
      controllers: ["ds4": "DualShock 4"],
      activeProfiles: [:],
      controllerHealth: ["ds4": healthy]
    )
    let after = RuntimeNotificationSnapshot(
      controllers: ["ds4": "DualShock 4"],
      activeProfiles: [:],
      controllerHealth: ["ds4": stale]
    )

    #expect(
      RuntimeNotificationDiff.events(from: before, to: after) == [
        .controllerNeedsAttention("DualShock 4")
      ]
    )
    #expect(RuntimeNotificationDiff.events(from: after, to: after).isEmpty)
  }

  @Test
  func unavailableSourceDoesNotBlockOrInventEventsForOtherSource() {
    let before = RuntimeNotificationSnapshot(
      controllers: ["old": "Old Controller"],
      activeProfiles: nil
    )
    let after = RuntimeNotificationSnapshot(
      controllers: ["new": "New Controller"],
      activeProfiles: ["1:2": "Desktop"]
    )

    #expect(
      RuntimeNotificationDiff.events(from: before, to: after) == [
        .controllerConnected("New Controller"), .controllerDisconnected("Old Controller"),
      ]
    )
  }

  @Test
  @MainActor
  func monitorSuppressesBootNoiseAndHonorsPreferences() throws {
    let settings = SettingsStore(directory: RootedDataDirectory.temporary())
    try settings.set(.notifyControllerConnected, to: true)
    try settings.set(.notifyControllerDisconnected, to: true)
    let delivery = NotificationDeliverySpy()
    let monitor = RuntimeNotificationMonitor(settings: settings, delivery: delivery)

    monitor.observe(
      RuntimeNotificationSnapshot(controllers: ["old": "Old Controller"], activeProfiles: [:])
    )
    #expect(delivery.messages.isEmpty)

    monitor.observe(
      RuntimeNotificationSnapshot(controllers: ["new": "New Controller"], activeProfiles: [:])
    )
    #expect(delivery.messages.count == 2)
    #expect(delivery.messages.allSatisfy { $0.sound })

    try settings.set(.notifyControllerConnected, to: false)
    monitor.observe(
      RuntimeNotificationSnapshot(controllers: ["third": "Third Controller"], activeProfiles: [:])
    )
    #expect(delivery.messages.count == 3)
  }

  @Test
  @MainActor
  func damagedSettingsFileDeliversNoNotification() throws {
    let settings = SettingsStore(directory: RootedDataDirectory.temporary())
    try settings.set(.notifyControllerConnected, to: true)
    try Data("not json".utf8).write(to: settings.userFileURL)
    let delivery = NotificationDeliverySpy()
    let monitor = RuntimeNotificationMonitor(settings: settings, delivery: delivery)

    monitor.observe(RuntimeNotificationSnapshot(controllers: [:], activeProfiles: [:]))
    monitor.observe(
      RuntimeNotificationSnapshot(controllers: ["new": "New Controller"], activeProfiles: [:])
    )
    // The stored choice to notify cannot be read, so nothing is delivered.
    #expect(delivery.messages.isEmpty)
    #expect(throws: SettingsStoreError.self) { try settings.load() }
  }
}

private struct NotificationPermissionAuthorizationStub: NotificationAuthorizationControlling {
  let currentState: RuntimeNotificationAuthorizationState
  let alertStyle: RuntimeNotificationAlertStyle
  let soundsEnabled: Bool?

  init(
    state: RuntimeNotificationAuthorizationState,
    alertStyle: RuntimeNotificationAlertStyle = .unknown,
    soundsEnabled: Bool? = nil
  ) {
    currentState = state
    self.alertStyle = alertStyle
    self.soundsEnabled = soundsEnabled
  }

  func state() -> RuntimeNotificationAuthorizationState { currentState }

  func request() -> (RuntimeNotificationAuthorizationState, String?) { (currentState, nil) }

  func settings() -> RuntimeNotificationSettings {
    RuntimeNotificationSettings(
      authorization: currentState,
      alertStyle: alertStyle,
      soundsEnabled: soundsEnabled
    )
  }

  @MainActor
  func openSystemSettings() {}
}

private final class NotificationDeliverySpy: RuntimeNotificationDelivering {
  private(set) var messages: [(title: String, body: String, sound: Bool)] = []

  func deliver(title: String, body: String, sound: Bool) { messages.append((title, body, sound)) }
  nonisolated(nonsending) func deliverAwaitingSystem(
    title: String,
    body: String,
    sound: Bool
  ) async {
    await Task.yield()
    messages.append((title, body, sound))
  }
}
