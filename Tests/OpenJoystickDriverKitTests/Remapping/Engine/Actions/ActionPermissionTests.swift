import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct ActionPermissionTests {
  private let system = RemappingDestination.keyboard(key: .space, modifiers: [])
  private let virtual = RemappingDestination.gamepadButton(.south)

  @Test
  func missingPostEventAccessThrowsANamedErrorAndSendsNothing() async {
    let performer = StubSystemActionPerformer(missing: [.postEvent])
    let expected = RemappingSystemActionError.permissionMissing(.postEvent, action: "VolumeUp")
    await #expect(throws: expected) { try await performer.postSystemKey(.volumeUp, pressed: true) }
    await #expect(
      throws: RemappingSystemActionError.permissionMissing(.postEvent, action: "TypeText")
    ) { try await performer.typeText("a") }
    #expect(performer.sent.isEmpty)
  }

  @Test
  func missingAutomationAccessThrowsANamedErrorAndSendsNothing() async {
    let performer = StubSystemActionPerformer(missing: [.automation])
    let expected = RemappingSystemActionError.permissionMissing(.automation, action: "RunShortcut")
    await #expect(throws: expected) { try await performer.runShortcut(name: "Morning") }
    #expect(performer.sent.isEmpty)
  }

  @Test
  func theErrorCodeNamesThePermissionAndTheMessageNamesTheAction() {
    let postEvent = RemappingSystemActionError.permissionMissing(.postEvent, action: "VolumeUp")
    let automation = RemappingSystemActionError.permissionMissing(
      .automation,
      action: "RunShortcut"
    )
    #expect(postEvent.errorCode == .postEventAccessMissing)
    #expect(automation.errorCode == .automationAccessMissing)
    #expect(postEvent.errorDescription?.contains("VolumeUp") == true)
    #expect(postEvent.errorDescription?.contains(postEvent.errorCode.localizedExplanation) == true)
  }

  @Test
  func grantedPermissionSendsTheAction() async throws {
    let performer = StubSystemActionPerformer(missing: [])
    try await performer.postSystemKey(.mute, pressed: false)
    #expect(performer.sent == ["Mute"])
  }

  @Test
  func destinationsInLayersAndMacrosNeedPostEvent() {
    let binding = RemappingBinding(source: .button(.south), destination: system)
    let layer = RemappingLayer(
      name: "Alternate",
      activationMode: .hold,
      activator: .button(.leftShoulder),
      bindings: [binding]
    )
    let macro = RemappingMacro(name: "M", steps: [.tap(system)])
    let profiles = [
      makeProfile(bindings: [binding]),
      makeProfile(layers: [layer]),
      makeProfile(macros: [macro]),
    ]
    for profile in profiles {
      #expect(profile.requiresSystemInputAccess)
      #expect(profile.neededPermissions == [.postEvent])
    }
  }

  @Test
  func virtualOnlyProfileNeedsNoPermission() {
    let binding = RemappingBinding(source: .button(.south), destination: virtual)
    #expect(makeProfile(bindings: [binding]).neededPermissions.isEmpty)
    #expect(makeProfile().neededPermissions.isEmpty)
  }

  @Test
  func eachPermissionIsListedOnce() {
    let bindings = [
      RemappingBinding(source: .button(.south), destination: system),
      RemappingBinding(source: .button(.east), destination: .mouseButton(.left)),
    ]
    #expect(makeProfile(bindings: bindings).neededPermissions == [.postEvent])
  }

  private func makeProfile(
    bindings: [RemappingBinding] = [],
    layers: [RemappingLayer] = [],
    macros: [RemappingMacro] = []
  ) -> RemappingProfile {
    RemappingProfile(
      name: "Permissions",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      outputPolicy: RemappingOutputPolicy(virtualGamepad: .mapped),
      bindings: bindings,
      layers: layers,
      macros: macros
    )
  }
}

// swiftlint:disable async_without_await

/// Reports the permissions in `missing` as not granted and records what it sends.
private final class StubSystemActionPerformer: RemappingSystemActionPerforming,
  @unchecked Sendable
{
  private let missing: Set<RemappingPermission>
  private(set) var sent: [String] = []

  init(missing: Set<RemappingPermission>) { self.missing = missing }

  private func send(_ action: String, needs permission: RemappingPermission? = nil) throws {
    if let permission, missing.contains(permission) {
      throw RemappingSystemActionError.permissionMissing(permission, action: action)
    }
    sent.append(action)
  }

  func postSystemKey(_ key: RemappingSystemKey, pressed: Bool) async throws {
    try send(key.rawValue, needs: .postEvent)
  }

  func typeText(_ text: String) async throws { try send("TypeText", needs: .postEvent) }
  func runShortcut(name: String) async throws { try send("RunShortcut", needs: .automation) }
  func openMissionControl() async throws { try send("MissionControl") }
  func openApplication(bundleIdentifier: String) async throws { try send("OpenApplication") }
  func openURL(_ url: URL) async throws { try send("OpenURL") }
}

// swiftlint:enable async_without_await
