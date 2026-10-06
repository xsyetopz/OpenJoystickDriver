import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverService

extension ProfileLibraryTests {
  private func makeEmptyProfile() -> RemappingProfile {
    RemappingProfile(
      id: UUID(),
      name: "Empty",
      device: RemappingDeviceScope(vendorID: 1118, productID: 654),
      applicationScope: .global,
      outputPolicy: RemappingOutputPolicy(virtualGamepad: .mapped),
      bindings: []
    )
  }

  @Test
  func aMappedKeyboardOnlyProfileActivatesWithoutAllowEmpty() async throws {
    try await withLibrary { library, _ in
      let keyboard = RemappingProfile(
        id: UUID(),
        name: "Keyboard",
        device: RemappingDeviceScope(vendorID: 1118, productID: 654),
        applicationScope: .global,
        outputPolicy: RemappingOutputPolicy(virtualGamepad: .mapped),
        bindings: [
          RemappingBinding(
            source: .button(.south),
            destination: .keyboard(key: .space, modifiers: [])
          )
        ]
      )
      try await library.create(keyboard)

      try await library.activate(profileID: keyboard.id)
      #expect(try await library.snapshot().activeProfiles.map(\.profileID) == [keyboard.id])
    }
  }

  @Test
  func activatingAProfileThatProducesNoOutputNeedsAllowEmpty() async throws {
    try await withLibrary { library, _ in
      let empty = makeEmptyProfile()
      try await library.create(empty)

      await #expect(throws: RemappingProfileLibraryError.profileProducesNoOutput(empty.id)) {
        try await library.activate(profileID: empty.id)
      }
      #expect(try await library.snapshot().activeProfiles.isEmpty)

      try await library.activate(profileID: empty.id, allowEmpty: true)
      #expect(try await library.snapshot().activeProfiles.map(\.profileID) == [empty.id])
    }
  }

  @Test
  func theRefusalReachesRPCClientsAsE3025() {
    let error = RemappingRequestCoordinator.rpcError(
      RemappingProfileLibraryError.profileProducesNoOutput(UUID())
    )

    #expect(error.code == .profileProducesNoOutput)
    #expect(error.code.errorCode.rawValue == "E3025")
  }
}
