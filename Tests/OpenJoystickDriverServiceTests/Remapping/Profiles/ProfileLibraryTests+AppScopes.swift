import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverService

extension ProfileLibraryTests {
  private func makeAppProfile(name: String, appIDs: [String]) -> RemappingProfile {
    RemappingProfile(
      name: name,
      device: RemappingDeviceScope(vendorID: 1118, productID: 654),
      applicationScope: .application(appIDs: appIDs),
      bindings: []
    )
  }

  @Test
  func profileForTwoAppsInForceForSecond() async throws {
    try await withLibrary { library, _ in
      let global = makeProfile(name: "Everywhere")
      let scoped = makeAppProfile(
        name: "Two apps",
        appIDs: ["com.example.First", "com.example.Second"]
      )
      for profile in [scoped, global] {
        try await library.create(profile)
        try await library.activate(profileID: profile.id)
      }

      for appID in ["com.example.First", "com.example.Second"] {
        let active = try await library.activeProfile(
          vendorID: 1118,
          productID: 654,
          unit: nil,
          frontmostAppID: appID
        )
        #expect(active == scoped, "\(appID)")
      }
      let other = try await library.activeProfile(
        vendorID: 1118,
        productID: 654,
        unit: nil,
        frontmostAppID: "com.example.Third"
      )
      #expect(other == global)
    }
  }

  @Test
  func selectionNamesAppChoseProfile() async throws {
    try await withLibrary { library, _ in
      let global = makeProfile(name: "Everywhere")
      let scoped = makeAppProfile(
        name: "Second",
        appIDs: ["com.example.First", "com.example.Second"]
      )
      for profile in [scoped, global] {
        try await library.create(profile)
        try await library.activate(profileID: profile.id)
      }

      let byApp = try await library.activeProfileSelection(
        vendorID: 1118,
        productID: 654,
        unit: nil,
        frontmostAppID: "com.example.Second"
      )
      #expect(byApp?.profile == scoped)
      #expect(byApp?.appID == "com.example.Second")

      let general = try await library.activeProfileSelection(
        vendorID: 1118,
        productID: 654,
        unit: nil,
        frontmostAppID: "com.example.Third"
      )
      #expect(general?.profile == global)
      #expect(general?.appID == nil)
    }
  }
}
