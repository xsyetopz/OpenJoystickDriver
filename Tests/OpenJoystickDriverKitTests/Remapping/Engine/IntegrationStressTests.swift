import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct RemappingIntegrationStressTests {
  @Test(.timeLimit(.minutes(1)))
  func repeatedMultiControllerSessionsReleaseAllEngineStorage() throws {
    let profile = try stressProfile()
    var state = RemappingEngineState()
    var actionCount = 0
    let controllerCount = 256

    for location in 1...controllerCount {
      let identifier = DeviceIdentifier(
        vendorID: 1,
        productID: 2,
        locationID: UInt32(location)
      )
      actionCount += state.process(
        events: [
          .buttonPressed(.a),
          .buttonPressed(.b),
          .buttonPressed(.x),
          .buttonPressed(.y),
          .buttonPressed(.l1),
          .buttonPressed(.r1),
          .buttonPressed(.back),
          .buttonPressed(.start),
          .buttonPressed(.share),
          .buttonPressed(.options),
        ],
        from: identifier,
        profile: profile,
        at: UInt64(location)
      ).count
    }

    #expect(state.devices.count == controllerCount)
    #expect(actionCount > controllerCount)
    #expect(actionCount <= controllerCount * 20)
    _ = state.drain()
    #expect(state.devices.isEmpty)
    #expect(state.keyReferences.isEmpty)
    #expect(state.modifierReferences.isEmpty)
    #expect(state.mouseButtonReferences.isEmpty)
  }

  @Test(.timeLimit(.minutes(1)))
  func repeatedInputKeepsHistoryAndScheduledStorageBounded() throws {
    let profile = try stressProfile()
    let identifier = DeviceIdentifier(vendorID: 1, productID: 2, locationID: 1)
    var state = RemappingEngineState()

    for time in 0..<10_000 {
      _ = state.process(
        events: [.buttonPressed(.back), .buttonReleased(.back)],
        from: identifier,
        profile: profile,
        at: UInt64(time) * 1_000_000
      )
    }

    let device = try #require(state.devices[identifier])
    #expect(device.sequenceHistory.count <= 4)
    #expect(device.deferredSequences.count <= profile.sequences.count)
    #expect(device.pendingChordPresses.count <= profile.chords.flatMap(\.sources).count)
    #expect(device.pulseDeadlines.count <= profile.bindings.count)
    #expect(device.turbos.count <= profile.bindings.count)
    _ = state.drain()
    #expect(state.devices.isEmpty)
  }

  @Test(.timeLimit(.minutes(1)))
  func repeatedPhysicalUpdatesReplaceClaimsInsteadOfAccumulating() {
    let identifier = DeviceIdentifier(vendorID: 1, productID: 2, locationID: 1)
    let owner = UUID()
    var ownership = PhysicalOutputOwnership()

    for step in 0..<10_000 {
      ownership.setMapping(
        .brightness(Double(step % 100) / 100),
        active: true,
        owner: owner,
        for: identifier
      )
    }

    #expect(ownership.mappingClaimCount == 1)
    #expect(ownership.releaseMappings(for: identifier) == [.brightness])
    #expect(ownership.mappingClaimCount == 0)
  }

  private func stressProfile() throws -> RemappingProfile {
    let profile = RemappingProfile(
      name: "Stress",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      outputPolicy: RemappingOutputPolicy(
        virtualGamepad: .mapped,
        physicalInput: .exclusive
      ),
      bindings: [
        RemappingBinding(
          source: .button(.south),
          destination: .keyboard(key: .a, modifiers: [.shift]),
          behavior: .pulse,
          pulseDurationMs: 100
        ),
        RemappingBinding(
          source: .button(.east),
          destination: .gamepadButton(.north),
          behavior: .toggle
        ),
        RemappingBinding(
          source: .button(.west),
          destination: .physical(.rumble(motor: .leftMain, intensity: 0.5))
        ),
        RemappingBinding(
          source: .button(.north),
          destination: .mouseButton(.left),
          turbo: RemappingTurbo(repeatRateHz: 20, dutyCycle: 0.5)
        ),
      ],
      chords: [
        RemappingChord(
          sources: [.button(.leftShoulder), .button(.rightShoulder)],
          destination: .keyboard(key: .space, modifiers: []),
          mode: .simultaneous
        )
      ],
      sequences: [
        RemappingSequence(
          sources: [.button(.back), .button(.start), .button(.share), .button(.options)],
          windowMs: 1_000,
          destination: .gamepadButton(.south)
        )
      ]
    )
    try profile.validate()
    return profile
  }
}
