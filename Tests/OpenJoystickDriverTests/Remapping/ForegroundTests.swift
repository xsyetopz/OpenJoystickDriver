import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriver

struct RemappingForegroundPolicyTests {
  @Test func applicationScopeRequiresExactFrontmostBundleIdentifier() {
    let scope = RemappingApplicationScope.application(bundleIdentifier: "com.example.Game")
    #expect(RemappingForegroundPolicy.eligibility(
      for: scope,
      frontmostBundleIdentifier: "com.example.Game",
      accessState: .granted,
      outputSuppressed: false
    ) == .eligible)
    #expect(RemappingForegroundPolicy.eligibility(
      for: scope,
      frontmostBundleIdentifier: "com.example.Game.Helper",
      accessState: .granted,
      outputSuppressed: false
    ) == .targetApplicationNotFrontmost)
    #expect(RemappingForegroundPolicy.eligibility(
      for: scope,
      frontmostBundleIdentifier: nil,
      accessState: .granted,
      outputSuppressed: false
    ) == .targetApplicationNotFrontmost)
  }

  @Test func globalScopeStillRequiresPostEventAuthorization() {
    #expect(RemappingForegroundPolicy.eligibility(
      for: .global,
      frontmostBundleIdentifier: nil,
      accessState: .granted,
      outputSuppressed: false
    ) == .eligible)
    #expect(RemappingForegroundPolicy.eligibility(
      for: .global,
      frontmostBundleIdentifier: nil,
      accessState: .notAuthorized,
      outputSuppressed: false
    ) == .postEventAccessNotAuthorized)
  }

  @Test func explicitSuppressionPrecedesOtherEligibilityStates() {
    #expect(RemappingForegroundPolicy.eligibility(
      for: .application(bundleIdentifier: "com.example.Game"),
      frontmostBundleIdentifier: nil,
      accessState: .notAuthorized,
      outputSuppressed: true
    ) == .outputSuppressed)
  }
}
