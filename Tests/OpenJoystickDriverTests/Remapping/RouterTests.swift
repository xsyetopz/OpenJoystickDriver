import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriver

struct RemappingOutputRouterTests {
  @Test func activeProfileExclusivelyReplacesCompatibilityOutput() async throws {
    let profile = remappingRouterProfile()
    let harness = try await RemappingRouterHarness.make(profile: profile)
    defer { harness.removeFiles() }
    let mapped = remappingRouterDevice(1)
    let compatibility = remappingRouterDevice(2, vendorID: 1356, productID: 2508)

    try await harness.router.dispatchCausally(events: [.buttonPressed(.a)], from: mapped)
    try await harness.router.dispatchCausally(events: [.buttonPressed(.b)], from: compatibility)

    #expect(harness.recorder.snapshot() == [
      .system(.keyDown(.space)),
      .compatibility([.buttonPressed(.b)], compatibility),
    ])
    #expect(await harness.router.status(for: mapped)?.selection == .remapping(profileID: profile.id))
    #expect(await harness.router.status(for: compatibility)?.selection == .compatibility)
  }

  @Test func routeTransitionsNeutralizeBeforeTheNewRouteEmits() async throws {
    let harness = try await RemappingRouterHarness.make()
    defer { harness.removeFiles() }
    let device = remappingRouterDevice(1)
    try await harness.router.dispatchCausally(events: [.buttonPressed(.b)], from: device)
    let profile = remappingRouterProfile()
    try await harness.library.create(profile)
    try await harness.library.activate(profileID: profile.id)

    try await harness.router.refreshModel(vendorID: 1118, productID: 654)
    try await harness.router.dispatchCausally(events: [.buttonPressed(.a)], from: device)
    try await harness.library.deactivate(vendorID: 1118, productID: 654)
    try await harness.router.refreshModel(vendorID: 1118, productID: 654)
    try await harness.router.dispatchCausally(events: [.buttonPressed(.x)], from: device)

    #expect(harness.recorder.snapshot() == [
      .compatibility([.buttonPressed(.b)], device),
      .compatibilityStop(device),
      .system(.keyDown(.space)),
      .system(.keyUp(.space)),
      .compatibility([.buttonPressed(.x)], device),
    ])
  }

  @Test func sameModelControllersRetainExactIdentityAndAggregateHeldOutputs() async throws {
    let harness = try await RemappingRouterHarness.make(profile: remappingRouterProfile())
    defer { harness.removeFiles() }
    let first = remappingRouterDevice(1)
    let second = remappingRouterDevice(2)

    try await harness.router.dispatchCausally(events: [.buttonPressed(.a)], from: first)
    try await harness.router.dispatchCausally(events: [.buttonPressed(.a)], from: second)
    try await harness.router.stopController(first)
    try await harness.router.stopController(second)

    #expect(harness.recorder.snapshot() == [
      .system(.keyDown(.space)),
      .system(.keyUp(.space)),
    ])
    #expect(await harness.router.status(for: first) == nil)
    #expect(await harness.router.status(for: second) == nil)
  }

  @Test func compatibilityGateDoesNotSuppressRemappingRoute() async throws {
    let harness = try await RemappingRouterHarness.make(profile: remappingRouterProfile())
    defer { harness.removeFiles() }
    let mapped = remappingRouterDevice(1)
    let compatibility = remappingRouterDevice(2, vendorID: 1356, productID: 2508)
    try await harness.router.setCompatibilityOutputAllowed(false)

    try await harness.router.dispatchCausally(events: [.buttonPressed(.a)], from: mapped)
    try await harness.router.dispatchCausally(events: [.buttonPressed(.b)], from: compatibility)

    #expect(harness.recorder.snapshot() == [.system(.keyDown(.space))])
    #expect(await harness.router.status(for: mapped)?.eligibility == .eligible)
    #expect(await harness.router.status(for: compatibility)?.eligibility
      == .compatibilityOutputSuppressed)
  }

  @Test func compatibilityGateTearsDownTrackedRoutesBeforeReturning() async throws {
    let harness = try await RemappingRouterHarness.make(profile: remappingRouterProfile())
    defer { harness.removeFiles() }
    let compatibility = remappingRouterDevice(2, vendorID: 1356, productID: 2508)
    let mapped = remappingRouterDevice(1)
    try await harness.router.dispatchCausally(events: [.buttonPressed(.b)], from: compatibility)

    try await harness.router.setCompatibilityOutputAllowed(false)
    try await harness.router.dispatchCausally(events: [.buttonPressed(.a)], from: mapped)
    try await harness.router.setCompatibilityOutputAllowed(false)

    #expect(harness.recorder.snapshot() == [
      .compatibility([.buttonPressed(.b)], compatibility),
      .compatibilityStop(compatibility),
      .system(.keyDown(.space)),
    ])
    #expect(await harness.router.status(for: compatibility)?.eligibility
      == .compatibilityOutputSuppressed)
  }

  @Test func targetApplicationLossReleasesAndNeverFallsBack() async throws {
    let harness = try await RemappingRouterHarness.make(profile: remappingRouterProfile())
    defer { harness.removeFiles() }
    let device = remappingRouterDevice(1)
    try await harness.router.dispatchCausally(events: [.buttonPressed(.a)], from: device)
    harness.foreground.set("com.example.Other")
    try await harness.router.refreshEligibility()
    try await harness.router.dispatchCausally(events: [.buttonPressed(.b)], from: device)
    harness.foreground.set("com.example.Game")
    try await harness.router.refreshEligibility()
    try await harness.router.dispatchCausally(events: [.buttonPressed(.a)], from: device)

    #expect(harness.recorder.snapshot() == [
      .system(.keyDown(.space)),
      .system(.keyUp(.space)),
      .system(.keyDown(.space)),
    ])
    #expect(await harness.router.status(for: device)?.eligibility == .eligible)
  }

  @Test func productionForegroundCallbackCausallyReleasesOnSameCompatibilityValue() async throws {
    let harness = try await RemappingRouterHarness.make(profile: remappingRouterProfile())
    defer { harness.removeFiles() }
    let device = remappingRouterDevice(1)
    try await harness.router.dispatchCausally(events: [.buttonPressed(.a)], from: device)
    harness.foreground.set("com.example.Other")
    harness.foreground.resetReadCount()
    harness.access.resetReadCount()

    try await harness.router.foregroundStateDidChange(compatibilityOutputAllowed: true)

    #expect(harness.foreground.readCount == 1)
    #expect(harness.access.readCount == 1)
    #expect(harness.recorder.snapshot() == [
      .system(.keyDown(.space)),
      .system(.keyUp(.space)),
    ])
    #expect(await harness.router.status(for: device)?.eligibility
      == .targetApplicationNotFrontmost)

    try await harness.router.foregroundStateDidChange(compatibilityOutputAllowed: true)
    #expect(harness.recorder.snapshot() == [
      .system(.keyDown(.space)),
      .system(.keyUp(.space)),
    ])
  }

  @Test func foregroundCallbackPreservesPermissionAndSuppressionPrecedence() async throws {
    let harness = try await RemappingRouterHarness.make(profile: remappingRouterProfile())
    defer { harness.removeFiles() }
    let device = remappingRouterDevice(1)
    try await harness.router.dispatchCausally(events: [.buttonPressed(.a)], from: device)

    harness.access.set(.notAuthorized)
    try await harness.router.foregroundStateDidChange(compatibilityOutputAllowed: true)
    #expect(await harness.router.status(for: device)?.eligibility
      == .postEventAccessNotAuthorized)

    try await harness.router.setOutputSuppressed(true)
    harness.foreground.set("com.example.Other")
    try await harness.router.foregroundStateDidChange(compatibilityOutputAllowed: true)
    #expect(await harness.router.status(for: device)?.eligibility == .outputSuppressed)
    #expect(harness.recorder.snapshot() == [
      .system(.keyDown(.space)),
      .system(.keyUp(.space)),
    ])
  }

  @Test func statusReportsTheSameProviderSampleUsedForEligibility() async throws {
    let harness = try await RemappingRouterHarness.make(profile: remappingRouterProfile())
    defer { harness.removeFiles() }
    let device = remappingRouterDevice(1)
    try await harness.router.dispatchCausally(events: [.buttonPressed(.a)], from: device)
    harness.foreground.setSequence(["com.example.Game", "com.example.Other"])
    harness.access.setSequence([.granted, .notAuthorized])
    harness.foreground.resetReadCount()
    harness.access.resetReadCount()

    let status = try #require(await harness.router.status(for: device))

    #expect(status.eligibility == .eligible)
    #expect(status.frontmostBundleIdentifier == "com.example.Game")
    #expect(status.postEventAccessState == .granted)
    #expect(harness.foreground.readCount == 1)
    #expect(harness.access.readCount == 1)
  }

  @Test func permissionLossReleasesAndReportsTruthfulState() async throws {
    let harness = try await RemappingRouterHarness.make(profile: remappingRouterProfile())
    defer { harness.removeFiles() }
    let device = remappingRouterDevice(1)
    try await harness.router.dispatchCausally(events: [.buttonPressed(.a)], from: device)
    harness.access.set(.notAuthorized)
    try await harness.router.refreshEligibility()
    try await harness.router.dispatchCausally(events: [.buttonPressed(.b)], from: device)

    let deniedStatus = try #require(await harness.router.status(for: device))
    #expect(deniedStatus.selection != .compatibility)
    #expect(deniedStatus.eligibility == .postEventAccessNotAuthorized)
    #expect(deniedStatus.postEventAccessState == .notAuthorized)

    harness.access.set(.granted)
    try await harness.router.refreshEligibility()
    try await harness.router.dispatchCausally(events: [.buttonReleased(.a)], from: device)
    #expect(harness.recorder.snapshot() == [
      .system(.keyDown(.space)),
      .system(.keyUp(.space)),
    ])
    try await harness.router.dispatchCausally(events: [.buttonPressed(.a)], from: device)
    let restoredStatus = try #require(await harness.router.status(for: device))
    #expect(restoredStatus.selection != .compatibility)
    #expect(restoredStatus.eligibility == .eligible)
    #expect(restoredStatus.postEventAccessState == .granted)
    #expect(harness.recorder.snapshot() == [
      .system(.keyDown(.space)),
      .system(.keyUp(.space)),
      .system(.keyDown(.space)),
    ])
  }

  @Test func activeProfileUpdateAndSwitchReleaseOldStateImmediately() async throws {
    let original = remappingRouterProfile()
    let harness = try await RemappingRouterHarness.make(profile: original)
    defer { harness.removeFiles() }
    let device = remappingRouterDevice(1)
    try await harness.router.dispatchCausally(events: [.buttonPressed(.a)], from: device)

    let edited = remappingRouterProfile(
      id: original.id,
      name: "Edited",
      destination: .keyboard(key: .returnKey, modifiers: [])
    )
    try await harness.library.update(edited, expectedCurrent: original)
    try await harness.router.refreshModel(vendorID: 1118, productID: 654)
    try await harness.router.dispatchCausally(events: [.buttonPressed(.a)], from: device)

    let replacement = remappingRouterProfile(
      name: "Replacement",
      destination: .mouseButton(.left)
    )
    try await harness.library.create(replacement)
    try await harness.library.activate(profileID: replacement.id)
    try await harness.router.refreshModel(vendorID: 1118, productID: 654)

    #expect(harness.recorder.snapshot() == [
      .system(.keyDown(.space)),
      .system(.keyUp(.space)),
      .system(.keyDown(.returnKey)),
      .system(.keyUp(.returnKey)),
    ])
    #expect(await harness.router.status(for: device)?.selection
      == .remapping(profileID: replacement.id))
  }

  @Test func causalSuppressionReleasesMappingAndIsIdempotent() async throws {
    let harness = try await RemappingRouterHarness.make(profile: remappingRouterProfile())
    defer { harness.removeFiles() }
    let device = remappingRouterDevice(1)
    let compatibility = remappingRouterDevice(2, vendorID: 1356, productID: 2508)
    try await harness.router.dispatchCausally(events: [.buttonPressed(.a)], from: device)
    try await harness.router.dispatchCausally(events: [.buttonPressed(.b)], from: compatibility)
    try await harness.router.setOutputSuppressed(true)
    try await harness.router.setOutputSuppressed(true)
    try await harness.router.dispatchCausally(events: [.buttonPressed(.b)], from: device)
    try await harness.router.setOutputSuppressed(false)

    #expect(harness.recorder.snapshot() == [
      .system(.keyDown(.space)),
      .compatibility([.buttonPressed(.b)], compatibility),
      .compatibilityStop(compatibility),
      .system(.keyUp(.space)),
    ])
    #expect(await harness.router.status(for: device)?.selection != .compatibility)
  }

  @Test func synchronousSuppressionPropertyPreventsNewOutputUntilCausalDrain() async throws {
    let harness = try await RemappingRouterHarness.make(profile: remappingRouterProfile())
    defer { harness.removeFiles() }
    let device = remappingRouterDevice(1)
    try await harness.router.dispatchCausally(events: [.buttonPressed(.a)], from: device)

    harness.router.suppressOutput = true
    harness.router.suppressOutput = true
    try await harness.router.dispatchCausally(events: [.buttonPressed(.b)], from: device)

    #expect(harness.recorder.snapshot() == [
      .system(.keyDown(.space)),
      .system(.keyUp(.space)),
    ])
    #expect(harness.router.suppressOutput)
  }

  @Test func corruptLibraryFailsClosedAndPropagatesTypedStatus() async throws {
    let harness = try await RemappingRouterHarness.make()
    defer { harness.removeFiles() }
    try Data("not json".utf8).write(to: harness.fileURL)
    let device = remappingRouterDevice(1)

    await #expect(throws: RemappingOutputRoutingError.library(.corruptLibrary)) {
      try await harness.router.dispatchCausally(events: [.buttonPressed(.a)], from: device)
    }
    let status = try #require(await harness.router.status(for: device))
    #expect(status.selection == .unavailable)
    #expect(status.error == .library(.corruptLibrary))
    #expect(harness.recorder.snapshot().isEmpty)
  }

  @Test func ticksAdvanceOnlyEligibleRemappingRoutes() async throws {
    let profile = remappingRouterProfile(
      turbo: RemappingTurbo(repeatRateHz: 10, dutyCycle: 0.25)
    )
    let harness = try await RemappingRouterHarness.make(profile: profile)
    defer { harness.removeFiles() }
    let device = remappingRouterDevice(1)
    try await harness.router.dispatchCausally(events: [.buttonPressed(.a)], from: device)
    try await harness.router.tick(at: 1_025_000_000)
    harness.foreground.set("com.example.Other")
    try await harness.router.tick(at: 1_100_000_000)
    try await harness.router.tick(at: 1_200_000_000)

    #expect(harness.recorder.snapshot() == [
      .system(.keyDown(.space)),
      .system(.keyUp(.space)),
    ])
    #expect(await harness.router.status(for: device)?.eligibility
      == .targetApplicationNotFrontmost)
  }

  @Test func continuousTicksStopAtFocusLossAndDoNotResumeWithoutInput() async throws {
    let profile = RemappingProfile(
      name: "Pointer",
      device: RemappingDeviceScope(vendorID: 1118, productID: 654),
      applicationScope: .application(bundleIdentifier: "com.example.Game"),
      bindings: [
        RemappingBinding(
          source: .axis(.rightStickX),
          destination: .mouseMovement(.x),
          axisTuning: RemappingAxisTuning(deadzone: 0, gain: 1)
        ),
      ]
    )
    let harness = try await RemappingRouterHarness.make(profile: profile)
    defer { harness.removeFiles() }
    let device = remappingRouterDevice(1)
    try await harness.router.dispatchCausally(
      events: [.rightStickChanged(x: 0.75, y: 0)],
      from: device
    )
    try await harness.router.tick(at: 1_010_000_000)
    harness.foreground.set("com.example.Other")
    try await harness.router.tick(at: 1_020_000_000)
    harness.foreground.set("com.example.Game")
    try await harness.router.tick(at: 1_030_000_000)

    #expect(harness.recorder.snapshot() == [
      .system(.mouseMoved(axis: .x, amount: 0.75)),
      .system(.mouseMoved(axis: .x, amount: 0)),
    ])
  }

  @Test func controllerStopAndShutdownDrainRoutesIdempotently() async throws {
    let profile = remappingRouterProfile(applicationScope: .global)
    let harness = try await RemappingRouterHarness.make(profile: profile)
    defer { harness.removeFiles() }
    let mapped = remappingRouterDevice(1)
    let compatibility = remappingRouterDevice(2, vendorID: 1356, productID: 2508)
    try await harness.router.dispatchCausally(events: [.buttonPressed(.a)], from: mapped)
    try await harness.router.dispatchCausally(events: [.buttonPressed(.b)], from: compatibility)

    try await harness.router.shutdown()
    try await harness.router.shutdown()

    #expect(harness.recorder.snapshot() == [
      .system(.keyDown(.space)),
      .compatibility([.buttonPressed(.b)], compatibility),
      .system(.keyUp(.space)),
      .compatibilityStop(compatibility),
    ])
    #expect(await harness.router.statuses().isEmpty)
    await #expect(throws: RemappingOutputRoutingError.shutDown) {
      try await harness.router.dispatchCausally(events: [.buttonPressed(.a)], from: mapped)
    }
  }
}
