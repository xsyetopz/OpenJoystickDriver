import Foundation
import Testing

@testable import OpenJoystickDriverKit

/// The profile-value edit and the profile selector that `ojd profile set`, the endpoint, and the
/// App Intents share.
struct ProfileSetTests {
  private static func profile(_ name: String) -> RemappingProfile {
    RemappingProfile(
      id: UUID(),
      name: name,
      device: RemappingDeviceScope(vendorID: 0x054C, productID: 0x0CE6),
      applicationScope: .global,
      outputPolicy: RemappingOutputPolicy(virtualGamepad: .passthrough),
      bindings: []
    )
  }

  private static func profileKey(_ text: String) throws -> ProfileKey {
    try #require(ProfileKey(argument: text))
  }

  @Test
  func aValueIsSetAtItsKey() throws {
    let racing = Self.profile("Racing")

    let edited = try ProfileSetting.change(racing, key: Self.profileKey("name"), to: .string("Rally"))

    #expect(edited.name == "Rally")
    #expect(edited.id == racing.id)
  }

  @Test
  func aKeyWithNoParentIsRefusedWithTheUsageCode() throws {
    let failure = #expect(throws: CodedFailure.self) {
      try ProfileSetting.change(
        Self.profile("Racing"),
        key: Self.profileKey("missing.deeper"),
        to: .integer(1)
      )
    }
    #expect(failure?.id == .usage)
  }

  @Test
  func aValueThatMakesTheProfileInvalidIsRefusedWithTheProfileCode() throws {
    let failure = #expect(throws: CodedFailure.self) {
      try ProfileSetting.change(Self.profile("Racing"), key: Self.profileKey("name"), to: .integer(7))
    }
    #expect(failure?.id == .invalidProfile)
  }

  @Test
  func theIDCannotChange() throws {
    let failure = #expect(throws: CodedFailure.self) {
      try ProfileSetting.change(
        Self.profile("Racing"),
        key: Self.profileKey("id"),
        to: .string(UUID().uuidString)
      )
    }
    #expect(failure?.id == .usage)
  }

  @Test
  func aSelectorNamesAProfileByIDOrByNameWithoutRegardToCase() throws {
    let racing = Self.profile("Racing")
    let menus = Self.profile("Menus")
    let profiles = [racing, menus]

    #expect(
      try #require(ProfileSelector(argument: racing.id.uuidString)).resolve(in: profiles) == racing
    )
    #expect(try #require(ProfileSelector(argument: "menus")).resolve(in: profiles) == menus)
  }

  @Test
  func aSelectorThatMatchesNoProfileOrSeveralIsRefusedWithTheNotFoundCode() throws {
    let profiles = [Self.profile("Racing"), Self.profile("racing")]

    for text in ["Racing", "Rally"] {
      let failure = #expect(throws: CodedFailure.self) {
        try #require(ProfileSelector(argument: text)).resolve(in: profiles)
      }
      #expect(failure?.id == .notFound)
    }
    #expect(ProfileSelector(argument: "") == nil)
  }
}
