import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverPresentation

struct ProfileListSortTests {
  private static func profile(
    _ name: String,
    vendorID: UInt16 = 1,
    productID: UInt16 = 1
  )
    -> RemappingProfile
  {
    RemappingProfile(
      name: name,
      device: RemappingDeviceScope(vendorID: vendorID, productID: productID),
      applicationScope: .global,
      bindings: []
    )
  }

  private static func names(_ profiles: [RemappingProfile]) -> [String] { profiles.map(\.name) }

  @Test
  func byNameIgnoresCaseAndKeepsNumbersInOrder() {
    let profiles = [
      Self.profile("beta"), Self.profile("Profile 10"), Self.profile("Alpha"),
      Self.profile("Profile 2"),
    ]
    let sorted = ProfileListSort.name.sorted(profiles, lastUsed: [:])
    #expect(Self.names(sorted) == ["Alpha", "beta", "Profile 2", "Profile 10"])
  }

  @Test
  func byControllerGroupsByVendorThenProductThenName() {
    let profiles = [
      Self.profile("Z", vendorID: 2, productID: 1),
      Self.profile("B", vendorID: 1, productID: 9),
      Self.profile("A", vendorID: 1, productID: 9),
      Self.profile("C", vendorID: 1, productID: 2),
    ]
    let sorted = ProfileListSort.controller.sorted(profiles, lastUsed: [:])
    #expect(Self.names(sorted) == ["C", "A", "B", "Z"])
  }

  @Test
  func byLastUseListsTheNewestFirstAndTheNeverUsedLastByName() {
    let old = Self.profile("Old")
    let new = Self.profile("New")
    let never = Self.profile("Never")
    let alsoNever = Self.profile("Also never")
    let sorted = ProfileListSort.lastUsed.sorted(
      [never, old, alsoNever, new],
      lastUsed: [old.id: 10, new.id: 20]
    )
    #expect(Self.names(sorted) == ["New", "Old", "Also never", "Never"])
  }

  @Test
  func byLastUseBreaksATieByName() {
    let first = Self.profile("A")
    let second = Self.profile("B")
    let sorted = ProfileListSort.lastUsed.sorted(
      [second, first],
      lastUsed: [first.id: 5, second.id: 5]
    )
    #expect(Self.names(sorted) == ["A", "B"])
  }

  @Test
  func anEmptyListStaysEmpty() {
    for sort in ProfileListSort.allCases {
      #expect(sort.sorted([], lastUsed: [:]).isEmpty)
    }
  }

  @Test
  func theLastUseOfASnapshotIsKeyedByProfile() {
    let id = UUID()
    let payload = ApplicationServiceRemappingSnapshotPayload(
      profiles: [],
      activeProfiles: [],
      routes: [],
      lastUsed: [ApplicationServiceRemappingProfileUse(profileID: id, usedAt: 7)],
      postEventAccess: .granted
    )
    #expect(ProfileListSort.lastUsed(in: payload) == [id: 7])
  }
}
