import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverService

extension ProfileLibraryTests {
  private static let firstUnit = "U-AbCd_123-xyzW09q"
  private static let secondUnit = "U-0000000000000000"

  private func makeUnitProfile(name: String, unit: String) -> RemappingProfile {
    RemappingProfile(
      id: UUID(),
      name: name,
      device: RemappingDeviceScope(vendorID: 1118, productID: 654, unit: unit),
      applicationScope: .global,
      bindings: []
    )
  }

  @Test
  func aUnitProfileAppliesToItsUnitAndTheModelProfileToTheOthers() async throws {
    try await withLibrary { library, _ in
      let model = makeProfile(name: "Model")
      let first = makeUnitProfile(name: "First", unit: Self.firstUnit)
      for profile in [first, model] {
        try await library.create(profile)
        try await library.activate(profileID: profile.id)
      }

      let snapshot = try await library.snapshot()
      #expect(Set(snapshot.activeProfiles.map(\.profileID)) == [model.id, first.id])
      #expect(try await library.activeProfile(vendorID: 1118, productID: 654) == model)
      #expect(
        try await library.activeProfile(vendorID: 1118, productID: 654, unit: Self.firstUnit)
          == first
      )
      #expect(
        try await library.activeProfile(vendorID: 1118, productID: 654, unit: Self.secondUnit)
          == model
      )
    }
  }

  @Test
  func activatingAUnitProfileReplacesOnlyThatUnitsProfile() async throws {
    try await withLibrary { library, _ in
      let first = makeUnitProfile(name: "First", unit: Self.firstUnit)
      let second = makeUnitProfile(name: "Second", unit: Self.secondUnit)
      let replacement = makeUnitProfile(name: "Replacement", unit: Self.firstUnit)
      for profile in [first, second, replacement] {
        try await library.create(profile)
        try await library.activate(profileID: profile.id)
      }

      let snapshot = try await library.snapshot()
      #expect(Set(snapshot.activeProfiles.map(\.profileID)) == [second.id, replacement.id])
      #expect(try await library.activeProfile(vendorID: 1118, productID: 654) == nil)
      #expect(
        try await library.activeProfile(vendorID: 1118, productID: 654, unit: Self.secondUnit)
          == second
      )
    }
  }
}
