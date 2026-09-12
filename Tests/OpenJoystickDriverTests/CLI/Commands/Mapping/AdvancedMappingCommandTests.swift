import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriver

struct AdvancedMappingCommandTests {
  @Test func advancedStickTriggerAndLeanOptionsReachCreateAndRendering() async throws {
    let creator = MockMappingClient(snapshotValue: snapshot([]))
    _ = try await MappingInvocation(arguments: [
      "create", "Driving", "--vid", "1", "--pid", "2", "--global",
      "--virtual-gamepad", "mapped", "--stick-source", "left", "--stick-mode", "steering",
      "--stick-steering-degrees-at-full-scale", "270",
      "--stick-steering-return-degrees-per-second", "180", "--stick-passthrough", "true",
      "--trigger-source", "right", "--trigger-mode", "prefer_full_combined",
      "--trigger-soft-threshold", "0.2", "--trigger-full-threshold", "0.8",
      "--trigger-skip-window-ms", "125", "--motion-lean", "true",
      "--motion-lean-threshold-degrees", "20", "--motion-lean-hysteresis-degrees", "3",
    ]).execute(client: creator)
    let profile = try #require(await creator.submittedProfile)
    #expect(profile.stickMappings.first?.mode == .steering)
    #expect(profile.stickMappings.first?.steeringDegreesAtFullScale == 270)
    #expect(profile.stickMappings.first?.passthrough == true)
    #expect(profile.triggerMappings.first?.mode == .preferFullCombined)
    #expect(profile.triggerMappings.first?.skipWindowMs == 125)
    #expect(profile.motionTuning.lean == RemappingMotionLean(
      thresholdDegrees: 20, hysteresisDegrees: 3
    ))

    let binder = MockMappingClient(snapshotValue: snapshot([profile]))
    _ = try await MappingInvocation(arguments: [
      "bind", profile.id.uuidString, "--source", "trigger:right:full", "--target", "key:space",
    ]).execute(client: binder)
    let bound = try #require(await binder.submittedProfile)
    let leanBinder = MockMappingClient(snapshotValue: snapshot([bound]))
    _ = try await MappingInvocation(arguments: [
      "bind", bound.id.uuidString, "--source", "motion:lean:right", "--target", "key:d",
    ]).execute(client: leanBinder)
    let complete = try #require(await leanBinder.submittedProfile)
    let rendered = MappingRenderer.profile(complete)
    #expect(rendered.contains("trigger:right:full"))
    #expect(rendered.contains("motion:lean:right"))
    #expect(rendered.contains("steering"))
    #expect(rendered.contains("prefer_full_combined"))
  }

  private func snapshot(
    _ profiles: [RemappingProfile]
  ) -> ApplicationServiceRemappingSnapshotPayload {
    ApplicationServiceRemappingSnapshotPayload(
      profiles: profiles,
      activeProfiles: [],
      routes: [],
      postEventAccess: .granted
    )
  }
}
