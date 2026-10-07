import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverService

extension RemappingOutputRouterTests {
  @Test


  func targetApplicationLossReleasesAndNeverFallsBack() async throws {
    let harness = try await RemappingRouterHarness.make(profile: remappingRouterProfile())
    defer { harness.removeFiles() }
    let device = remappingRouterDevice(1)
    try await harness.router.dispatchCausally(changes: [.press(.faceSouth)], from: device)
    harness.foreground.set("com.example.Other")
    try await harness.router.refreshEligibility()
    try await harness.router.refreshEligibility()

    try await harness.router.dispatchCausally(changes: [.press(.faceEast)], from: device)
    harness.foreground.set("com.example.Game")
    try await harness.router.refreshEligibility()
    try await harness.router.dispatchCausally(changes: [.press(.faceSouth)], from: device)

    #expect(
      harness.recorder.snapshot() == [
        .system(.keyDown(.space)), .system(.keyUp(.space)), .system(.keyDown(.space)),
      ]
    )
    #expect(await harness.router.status(for: device)?.eligibility == .eligible)
  }

  @Test
  func outputSuppressionTakesPrecedenceOverPermissionAndForeground() async throws {
    let harness = try await RemappingRouterHarness.make(profile: remappingRouterProfile())
    defer { harness.removeFiles() }
    let device = remappingRouterDevice(1)
    try await harness.router.dispatchCausally(changes: [.press(.faceSouth)], from: device)

    harness.access.set(.notAuthorized)
    try await harness.router.refreshEligibility()
    #expect(await harness.router.status(for: device)?.eligibility == .postEventAccessNotAuthorized)

    harness.foreground.set("com.example.Other")
    harness.router.setOutputSuppressed(true)
    try await harness.router.refreshEligibility()
    #expect(await harness.router.status(for: device)?.eligibility == .outputSuppressed)
    #expect(harness.recorder.snapshot() == [.system(.keyDown(.space)), .system(.keyUp(.space))])
  }

  @Test
  func statusReportsTheSameProviderSampleUsedForEligibility() async throws {
    let harness = try await RemappingRouterHarness.make(profile: remappingRouterProfile())
    defer { harness.removeFiles() }
    let device = remappingRouterDevice(1)
    try await harness.router.dispatchCausally(changes: [.press(.faceSouth)], from: device)
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

  @Test
  func permissionLossReleasesAndReportsTruthfulState() async throws {
    let harness = try await RemappingRouterHarness.make(profile: remappingRouterProfile())
    defer { harness.removeFiles() }
    let device = remappingRouterDevice(1)
    try await harness.router.dispatchCausally(changes: [.press(.faceSouth)], from: device)
    harness.access.set(.notAuthorized)
    try await harness.router.refreshEligibility()
    try await harness.router.dispatchCausally(changes: [.press(.faceEast)], from: device)

    let deniedStatus = try #require(await harness.router.status(for: device))
    #expect(deniedStatus.selection != .virtualGamepad)
    #expect(deniedStatus.eligibility == .postEventAccessNotAuthorized)
    #expect(deniedStatus.postEventAccessState == .notAuthorized)

    harness.access.set(.granted)
    try await harness.router.refreshEligibility()
    try await harness.router.dispatchCausally(changes: [.release(.faceSouth)], from: device)
    #expect(harness.recorder.snapshot() == [.system(.keyDown(.space)), .system(.keyUp(.space))])
    try await harness.router.dispatchCausally(changes: [.press(.faceSouth)], from: device)
    let restoredStatus = try #require(await harness.router.status(for: device))
    #expect(restoredStatus.selection != .virtualGamepad)
    #expect(restoredStatus.eligibility == .eligible)
    #expect(restoredStatus.postEventAccessState == .granted)
    #expect(
      harness.recorder.snapshot() == [
        .system(.keyDown(.space)), .system(.keyUp(.space)), .system(.keyDown(.space)),
      ]
    )
  }

  @Test
  func activeProfileUpdateAndSwitchReleaseOldStateImmediately() async throws {
    let original = remappingRouterProfile()
    let harness = try await RemappingRouterHarness.make(profile: original)
    defer { harness.removeFiles() }
    let device = remappingRouterDevice(1)
    try await harness.router.dispatchCausally(changes: [.press(.faceSouth)], from: device)

    let edited = remappingRouterProfile(
      id: original.id,
      name: "Edited",
      destination: .keyboard(key: .returnKey, modifiers: [])
    )
    try await harness.library.update(edited, expectedCurrent: original)
    try await harness.router.refreshModel(vendorID: 1118, productID: 654)
    try await harness.router.dispatchCausally(changes: [.press(.faceSouth)], from: device)

    let replacement = remappingRouterProfile(name: "Replacement", destination: .mouseButton(.left))
    try await harness.library.create(replacement)
    try await harness.library.activate(profileID: replacement.id)
    try await harness.router.refreshModel(vendorID: 1118, productID: 654)

    #expect(
      harness.recorder.snapshot() == [
        .system(.keyDown(.space)), .system(.keyUp(.space)), .system(.keyDown(.returnKey)),
        .system(.keyUp(.returnKey)),
      ]
    )
    #expect(
      await harness.router.status(for: device)?.selection == .remapping(profileID: replacement.id)
    )
  }

  @Test
  func causalSuppressionReleasesMappingAndIsIdempotent() async throws {
    let harness = try await RemappingRouterHarness.make(profile: remappingRouterProfile())
    defer { harness.removeFiles() }
    let device = remappingRouterDevice(1)
    let virtualOutput = remappingRouterDevice(2, vendorID: 1356, productID: 2508)
    try await harness.router.dispatchCausally(changes: [.press(.faceSouth)], from: device)
    try await harness.router.dispatchCausally(changes: [.press(.faceEast)], from: virtualOutput)
    harness.router.setOutputSuppressed(true)
    harness.router.setOutputSuppressed(true)
    try await harness.router.dispatchCausally(changes: [.press(.faceEast)], from: device)
    harness.router.setOutputSuppressed(false)

    #expect(
      harness.recorder.snapshot() == [
        .system(.keyDown(.space)),
        .virtualGamepad(ControllerState.neutral.applying([.press(.faceEast)]), virtualOutput),
        .virtualOutputStop(virtualOutput), .system(.keyUp(.space)),
      ]
    )
    #expect(await harness.router.status(for: device)?.selection != .virtualGamepad)
  }

  @Test
  func synchronousSuppressionPropertyPreventsNewOutputUntilCausalDrain() async throws {
    let harness = try await RemappingRouterHarness.make(profile: remappingRouterProfile())
    defer { harness.removeFiles() }
    let device = remappingRouterDevice(1)
    try await harness.router.dispatchCausally(changes: [.press(.faceSouth)], from: device)

    harness.router.suppressOutput = true
    harness.router.suppressOutput = true
    try await harness.router.dispatchCausally(changes: [.press(.faceEast)], from: device)

    #expect(harness.recorder.snapshot() == [.system(.keyDown(.space)), .system(.keyUp(.space))])
    #expect(harness.router.suppressOutput)
  }

  @Test
  func corruptLibraryFailsClosedAndPropagatesTypedStatus() async throws {
    let harness = try await RemappingRouterHarness.make()
    defer { harness.removeFiles() }
    try Data("not json".utf8).write(to: harness.library.selectionsURL)
    let device = remappingRouterDevice(1)

    await #expect(throws: RemappingOutputRoutingError.library(.corruptLibrary)) {
      try await harness.router.dispatchCausally(changes: [.press(.faceSouth)], from: device)
    }
    let status = try #require(await harness.router.status(for: device))
    #expect(status.selection == .unavailable)
    #expect(status.error == .library(.corruptLibrary))
    #expect(harness.recorder.snapshot().isEmpty)
  }

  @Test
  func ticksAdvanceOnlyEligibleRemappingRoutes() async throws {
    let profile = remappingRouterProfile(turbo: RemappingTurbo(repeatRateHz: 10, dutyCycle: 0.25))
    let harness = try await RemappingRouterHarness.make(profile: profile)
    defer { harness.removeFiles() }
    let device = remappingRouterDevice(1)
    try await harness.router.dispatchCausally(changes: [.press(.faceSouth)], from: device)
    try await harness.router.tick(at: 1_025_000_000)
    harness.foreground.set("com.example.Other")
    try await harness.router.tick(at: 1_100_000_000)
    try await harness.router.tick(at: 1_200_000_000)

    #expect(harness.recorder.snapshot() == [.system(.keyDown(.space)), .system(.keyUp(.space))])
    #expect(await harness.router.status(for: device)?.eligibility == .targetApplicationNotFrontmost)
  }

  @Test
  func continuousTicksStopAtFocusLossAndDoNotResumeWithoutInput() async throws {
    let profile = RemappingProfile(
      name: "Pointer",
      device: RemappingDeviceScope(vendorID: 1118, productID: 654),
      applicationScope: .application(bundleIdentifier: "com.example.Game"),
      bindings: [
        RemappingBinding(
          source: .axis(.rightStickX),
          destination: .mouseMovement(.x),
          axisTuning: RemappingAxisTuning(deadzone: 0, gain: 1)
        )
      ]
    )
    let harness = try await RemappingRouterHarness.make(profile: profile)
    defer { harness.removeFiles() }
    let device = remappingRouterDevice(1)
    try await harness.router.dispatchCausally(changes: [.rightStick(x: 0.75, y: 0)], from: device)
    try await harness.router.tick(at: 1_010_000_000)
    harness.foreground.set("com.example.Other")
    try await harness.router.tick(at: 1_020_000_000)
    harness.foreground.set("com.example.Game")
    try await harness.router.tick(at: 1_030_000_000)

    #expect(
      harness.recorder.snapshot() == [
        .system(.mouseMoved(axis: .x, amount: quantizedStick(0.75))),
        .system(.mouseMoved(axis: .x, amount: 0)),
      ]
    )
  }

  @Test
  func controllerStopAndShutdownDrainRoutesIdempotently() async throws {
    let profile = remappingRouterProfile(applicationScope: .global)
    let harness = try await RemappingRouterHarness.make(profile: profile)
    defer { harness.removeFiles() }
    let mapped = remappingRouterDevice(1)
    let virtualOutput = remappingRouterDevice(2, vendorID: 1356, productID: 2508)
    try await harness.router.dispatchCausally(changes: [.press(.faceSouth)], from: mapped)
    try await harness.router.dispatchCausally(changes: [.press(.faceEast)], from: virtualOutput)

    try await harness.router.shutdown()
    try await harness.router.shutdown()

    #expect(
      harness.recorder.snapshot() == [
        .system(.keyDown(.space)),
        .virtualGamepad(ControllerState.neutral.applying([.press(.faceEast)]), virtualOutput),
        .system(.keyUp(.space)), .virtualOutputStop(virtualOutput),
      ]
    )
    #expect(await harness.router.statuses().isEmpty)
    await #expect(throws: RemappingOutputRoutingError.shutDown) {
      try await harness.router.dispatchCausally(changes: [.press(.faceSouth)], from: mapped)
    }
  }
}

extension RemappingOutputRouterTests {
  @Test
  func releaseOnVirtualGamepadRouteDoesNotSwallowTheNextRemappedPress() async throws {
    let profile = remappingRouterProfile()
    let harness = try await RemappingRouterHarness.make(profile: profile)
    defer { harness.removeFiles() }
    let device = remappingRouterDevice(1)
    try await harness.router.dispatchCausally(changes: [.press(.faceSouth)], from: device)

    try await harness.library.deactivate(profileID: profile.id)
    try await harness.router.refreshModel(vendorID: 1118, productID: 654)
    #expect(await harness.router.status(for: device)?.selection == .virtualGamepad)
    try await harness.router.dispatchCausally(changes: [.release(.faceSouth)], from: device)

    try await harness.library.activate(profileID: profile.id)
    try await harness.router.refreshModel(vendorID: 1118, productID: 654)
    try await harness.router.dispatchCausally(changes: [.press(.faceSouth)], from: device)

    let system = harness.recorder.snapshot().filter {
      if case .system = $0 { return true }
      return false
    }
    #expect(
      system == [.system(.keyDown(.space)), .system(.keyUp(.space)), .system(.keyDown(.space))]
    )
  }
}
