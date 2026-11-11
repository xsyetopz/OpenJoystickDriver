import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverService

struct RemappingForegroundPolicyTests {
  @Test
  func applicationScopeRequiresExactFrontmostAppID() {
    let scope = RemappingApplicationScope.application(appIDs: ["com.example.Game"])
    #expect(
      RemappingForegroundPolicy.eligibility(
        for: scope,
        frontmostAppID: "com.example.Game",
        accessState: .granted,
        outputSuppressed: false
      ) == .eligible
    )
    #expect(
      RemappingForegroundPolicy.eligibility(
        for: scope,
        frontmostAppID: "com.example.Game.Helper",
        accessState: .granted,
        outputSuppressed: false
      ) == .targetApplicationNotFrontmost
    )
    #expect(
      RemappingForegroundPolicy.eligibility(
        for: scope,
        frontmostAppID: nil,
        accessState: .granted,
        outputSuppressed: false
      ) == .targetApplicationNotFrontmost
    )
  }

  @Test
  func applicationScopeWithTwoAppsIsEligibleForEitherOne() {
    let scope = RemappingApplicationScope.application(appIDs: [
      "com.example.One", "com.example.Two",
    ])
    for (front, expected) in [
      ("com.example.One", RemappingRouteEligibility.eligible),
      ("com.example.Two", .eligible),
      ("com.example.Three", .targetApplicationNotFrontmost),
    ] {
      #expect(
        RemappingForegroundPolicy.eligibility(
          for: scope,
          frontmostAppID: front,
          accessState: .granted,
          outputSuppressed: false
        ) == expected
      )
    }
  }

  @Test
  func globalScopeStillRequiresPostEventAuthorization() {
    #expect(
      RemappingForegroundPolicy.eligibility(
        for: .global,
        frontmostAppID: nil,
        accessState: .granted,
        outputSuppressed: false
      ) == .eligible
    )
    #expect(
      RemappingForegroundPolicy.eligibility(
        for: .global,
        frontmostAppID: nil,
        accessState: .notAuthorized,
        outputSuppressed: false
      ) == .postEventAccessNotAuthorized
    )
  }

  @Test
  func explicitSuppressionPrecedesOtherEligibilityStates() {
    #expect(
      RemappingForegroundPolicy.eligibility(
        for: .application(appIDs: ["com.example.Game"]),
        frontmostAppID: nil,
        accessState: .notAuthorized,
        outputSuppressed: true
      ) == .outputSuppressed
    )
  }
}
