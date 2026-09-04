import AppKit
import Foundation
import Testing

@testable import OpenJoystickDriver

@Suite struct NotificationTests {
  @Test func prefersApplicationIconOverTemplateSymbol() {
    let representation = NSBitmapImageRep(
      bitmapDataPlanes: nil,
      pixelsWide: 32,
      pixelsHigh: 32,
      bitsPerSample: 8,
      samplesPerPixel: 4,
      hasAlpha: true,
      isPlanar: false,
      colorSpaceName: .deviceRGB,
      bytesPerRow: 0,
      bitsPerPixel: 0
    )
    let icon = NSImage(size: NSSize(width: 32, height: 32))
    if let representation { icon.addRepresentation(representation) }
    let image = MenuBarStatusItemImage.make(
      applicationIcon: icon,
      accessibilityDescription: "OpenJoystickDriver"
    )
    #expect(image?.isTemplate == false)
    #expect(image?.size == MenuBarStatusItemImage.statusItemSize)
  }

  @Test func fallsBackToTemplateSymbolWhenApplicationIconIsMissing() {
    let image = MenuBarStatusItemImage.make(
      applicationIcon: nil,
      accessibilityDescription: "OpenJoystickDriver"
    )
    #expect(image?.isTemplate == true)
  }

  @Test @MainActor func permissionModelPublishesTheResolvedAuthorizationState() async {
    let authorization = NotificationPermissionAuthorizationStub(state: .allowed)
    let model = NotificationPermissionModel(authorization: authorization)

    model.refresh()
    for _ in 0..<100 where model.state == .checking { await Task.yield() }

    #expect(model.state == .allowed)
  }

  @Test @MainActor func permissionModelPublishesBannerAndSoundSettings() async {
    let authorization = NotificationPermissionAuthorizationStub(
      state: .allowed,
      alertStyle: .none,
      soundsEnabled: false
    )
    let model = NotificationPermissionModel(authorization: authorization)

    model.refresh()
    for _ in 0..<100 where model.state == .checking { await Task.yield() }

    #expect(model.settings.alertStyle == .none)
    #expect(model.settings.soundsEnabled == false)
  }

  @Test func detectsControllerAndProfileTransitionsWithoutBootNoise() {
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
        .activeProfileChanged(from: "Desktop", to: "Racing")
      ]
    )
  }

  @Test func detectsProfileDeactivation() {
    let before = RuntimeNotificationSnapshot(controllers: [:], activeProfiles: ["1:2": "Desktop"])
    let after = RuntimeNotificationSnapshot(controllers: [:], activeProfiles: [:])

    #expect(
      RuntimeNotificationDiff.events(from: before, to: after) == [
        .activeProfileChanged(from: "Desktop", to: nil)
      ]
    )
  }

  @Test func unavailableSourceDoesNotBlockOrInventEventsForTheOtherSource() {
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
        .controllerConnected("New Controller"), .controllerDisconnected("Old Controller")
      ]
    )
  }

  @Test @MainActor func monitorSuppressesBootNoiseAndHonorsPreferences() throws {
    let suiteName = "NotificationTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    defaults.set(true, forKey: ApplicationPreferenceKeys.controllerNotifications)
    defaults.set(true, forKey: ApplicationPreferenceKeys.controllerDisconnectedNotifications)
    let delivery = NotificationDeliverySpy()
    let monitor = RuntimeNotificationMonitor(defaults: defaults, delivery: delivery)

    monitor.observe(
      RuntimeNotificationSnapshot(controllers: ["old": "Old Controller"], activeProfiles: [:])
    )
    #expect(delivery.messages.isEmpty)

    monitor.observe(
      RuntimeNotificationSnapshot(controllers: ["new": "New Controller"], activeProfiles: [:])
    )
    #expect(delivery.messages.count == 2)
    #expect(delivery.messages.allSatisfy { $0.sound })

    defaults.set(false, forKey: ApplicationPreferenceKeys.controllerNotifications)
    monitor.observe(
      RuntimeNotificationSnapshot(controllers: ["third": "Third Controller"], activeProfiles: [:])
    )
    #expect(delivery.messages.count == 3)
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

  func state(completion: @escaping @Sendable (RuntimeNotificationAuthorizationState) -> Void) {
    completion(currentState)
  }

  func request(
    completion: @escaping @Sendable (RuntimeNotificationAuthorizationState, String?) -> Void
  ) { completion(currentState, nil) }

  func settings(completion: @escaping @Sendable (RuntimeNotificationSettings) -> Void) {
    completion(
      RuntimeNotificationSettings(
        authorization: currentState,
        alertStyle: alertStyle,
        soundsEnabled: soundsEnabled
      )
    )
  }

  @MainActor func openSystemSettings() {}
}

private final class NotificationDeliverySpy: RuntimeNotificationDelivering {
  private(set) var messages: [(title: String, body: String, sound: Bool)] = []

  func deliver(title: String, body: String, sound: Bool) { messages.append((title, body, sound)) }
}
