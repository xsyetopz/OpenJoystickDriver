import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct RemappingTouchMappingTests {
  @Test func touchContractRoundTripsWithoutChangingTypedSources() throws {
    let mapping = RemappingTouchMapping(
      id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
      surface: .right,
      mode: .pointer,
      pointerSensitivity: 750,
      stickRadius: 0.3,
      deadzone: 0.05
    )
    let sources: [RemappingSource] = [
      .touchContact(.right),
      .touchGrid(
        RemappingTouchGridSource(surface: .right, columns: 3, rows: 2, column: 2, row: 1)
      ),
      .touchSwipe(
        RemappingTouchSwipeSource(surface: .right, direction: .up, minimumDistance: 0.3)
      )
    ]
    let profile = RemappingProfile(
      name: "Touch",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      touchMappings: [mapping],
      bindings: sources.map {
        RemappingBinding(source: $0, destination: .keyboard(key: .space, modifiers: []))
      }
    )

    try profile.validate()
    let decoded = try JSONDecoder().decode(
      RemappingProfile.self, from: JSONEncoder().encode(profile)
    )
    #expect(decoded == profile)
  }

  @Test func invalidGridSwipeAndDuplicateContinuousMappingAreRejected() {
    let invalidGrid = profile(
      touchMappings: [],
      source: .touchGrid(
        RemappingTouchGridSource(surface: .primary, columns: 2, rows: 2, column: 2, row: 0)
      )
    )
    #expect(throws: RemappingValidationError.invalidTouchGrid) { try invalidGrid.validate() }

    let invalidSwipe = profile(
      touchMappings: [],
      source: .touchSwipe(
        RemappingTouchSwipeSource(surface: .primary, direction: .left, minimumDistance: .nan)
      )
    )
    #expect(throws: RemappingValidationError.invalidTouchSwipe) { try invalidSwipe.validate() }

    let duplicate = profile(
      touchMappings: [
        RemappingTouchMapping(surface: .left, mode: .pointer),
        RemappingTouchMapping(surface: .left, mode: .pointer)
      ],
      source: .touchContact(.left)
    )
    #expect(throws: RemappingValidationError.duplicateTouchMapping(.left)) {
      try duplicate.validate()
    }
  }

  @Test func touchStickRequiresVirtualOutput() {
    let value = profile(
      touchMappings: [RemappingTouchMapping(surface: .primary, mode: .rightStick)],
      source: .touchContact(.primary)
    )
    #expect(throws: RemappingValidationError.virtualOutputRequired) { try value.validate() }
  }

  private func profile(
    touchMappings: [RemappingTouchMapping], source: RemappingSource
  ) -> RemappingProfile {
    RemappingProfile(
      name: "Touch",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      touchMappings: touchMappings,
      bindings: [
        RemappingBinding(source: source, destination: .keyboard(key: .space, modifiers: []))
      ]
    )
  }
}
