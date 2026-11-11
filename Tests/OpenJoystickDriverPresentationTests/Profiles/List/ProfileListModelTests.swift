import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverPresentation

struct ProfileListModelTests {
  private static func profile(
    named name: String,
    scope: RemappingApplicationScope = .global
  ) -> RemappingProfile {
    RemappingProfile(
      name: name,
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: scope,
      bindings: []
    )
  }

  @Test
  func aDuplicateCarriesTheContentUnderTheTypedName() {
    let source = Self.profile(named: "Racing", scope: .application(appID: "com.example.Game"))
    let copy = duplicatedProfile(source, named: " Racing 2 ", in: [source])
    #expect(copy?.name == "Racing 2")
    #expect(copy?.id != source.id)
    #expect(copy?.device == source.device)
    #expect(copy?.applicationScope == source.applicationScope)
  }

  @Test
  func aDuplicateNameThatIsTakenOrBlankMakesNoCopy() {
    let source = Self.profile(named: "Racing")
    #expect(duplicatedProfile(source, named: "racing", in: [source]) == nil)
    #expect(duplicatedProfile(source, named: "  ", in: [source]) == nil)
  }

  @Test
  func theDefaultDuplicateNameIsFreeOfExistingNames() {
    let source = Self.profile(named: "Racing")
    let first = defaultDuplicateName(of: source, in: [source])
    #expect(first == OJDLocalized.formatted("ui.profiles.copyName", "Racing"))
    let taken = Self.profile(named: first)
    #expect(defaultDuplicateName(of: source, in: [source, taken]) == "\(first) 2")
  }

  @Test
  func theScopeCaptionNamesTheApplicationOrShowsItsIdentifier() {
    let count = "12 assignments"
    #expect(ProfileScopeCaption.text(for: .global, assignments: count) { _ in "x" } == count)
    let safari = ProfileScopeCaption.text(
      for: .application(appID: "com.apple.Safari"),
      assignments: count
    ) { _ in "Safari" }
    #expect(safari == OJDLocalized.formatted("ui.profiles.scopedCaption", "Safari", count))
    #expect(safari.contains("Safari") && safari.contains(count))
    let gone = ProfileScopeCaption.text(
      for: .application(appID: "com.example.Gone"),
      assignments: count
    ) { _ in nil }
    #expect(gone.contains("com.example.Gone") && gone.contains(count))
  }

  @MainActor
  @Test
  func anApplicationNameIsLookedUpOncePerIdentifier() {
    let names = ProfileApplicationNames()
    let first = names.name(for: "com.example.NotInstalled.t209")
    #expect(first == nil)
    #expect(names.name(for: "com.example.NotInstalled.t209") == nil)
  }

  private static let validDocument = """
    {"apiVersion":"\(OpenJoystickDriverAPI.version)","kind":"Profile",\
    "applicationScope":{"type":"Global"},"bindings":[],"chords":[],\
    "device":{"productID":616,"vendorID":1356},"id":"1364CBAC-B60B-4E11-B3E7-C38AD809FE42",\
    "layers":[],"name":"Pad","outputPolicy":{"physicalInput":"Shared",\
    "virtualGamepad":"Passthrough"},"sequences":[],"stickMappings":[],"touchMappings":[],\
    "triggerMappings":[]}
    """

  @Test
  func aValidProfileFileShowsWhatItTargets() {
    let result = ProfileFileValidation.check(
      PropertyListFixture.bytes(json: Self.validDocument),
      fileName: "pad.plist"
    )
    #expect(
      result
        == .valid(
          name: "Pad",
          controller: "054C:0268",
          scope: RuntimePresentation.profileScopeLabel(.global)
        )
    )
    #expect(result.message.contains("Pad"))
  }

  @Test
  func anInvalidProfileFileShowsItsErrorCodeAndProblem() {
    let result = ProfileFileValidation.check(
      PropertyListFixture.bytes(
        json: #"{"apiVersion":"\#(OpenJoystickDriverAPI.version)","kind":"Profile","name":"Pad"}"#
      ),
      fileName: "bad.plist"
    )
    guard case .invalid(let fileName, let code, let problem) = result else {
      Issue.record("expected an invalid result")
      return
    }
    #expect(fileName == "bad.plist")
    #expect(code == ErrorCode.invalidProfile.rawValue)
    #expect(!problem.isEmpty)
    #expect(result.message.contains(code))
    #expect(result.message.contains("bad.plist"))
  }
}
