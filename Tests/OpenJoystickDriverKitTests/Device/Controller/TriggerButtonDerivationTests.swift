import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct TriggerButtonDerivationTests {
  private static let analogOnly = ControllerCapabilities(controls: Control.xboxLayout)
  private static let digital = ControllerCapabilities(
    controls: Control.xboxLayout,
    digitalTriggers: [.leftTrigger, .rightTrigger]
  )

  private func derive(
    left: UInt16,
    right: UInt16 = 0,
    after previous: ControllerState = .neutral,
    capabilities: ControllerCapabilities = Self.analogOnly
  ) -> Set<Control> {
    var state = ControllerState.neutral
    state.leftTrigger = UnipolarValue(left)
    state.rightTrigger = UnipolarValue(right)
    return TriggerButtonDerivation.applying(
      to: state,
      previous: previous,
      capabilities: capabilities
    ).pressed
  }

  @Test
  func policyReusesRemappingDigitalActivationDefaults() {
    #expect(
      TriggerButtonDerivation.pressThreshold
        == UnipolarValue(normalized: Float(RemappingAxisTuning.defaultDigitalActivationThreshold))
    )
    #expect(
      TriggerButtonDerivation.releaseThreshold
        == UnipolarValue(
          normalized: Float(
            RemappingAxisTuning.defaultDigitalActivationThreshold
              - RemappingTransform.hysteresisWidth
          )
        )
    )
    #expect(TriggerButtonDerivation.pressThreshold.rawValue == 32_767)
    #expect(TriggerButtonDerivation.releaseThreshold.rawValue == 29_490)
  }

  @Test
  func pressesAtThresholdAndReleasesOnlyBelowHysteresisBand() {
    #expect(derive(left: 32_766).isEmpty)
    #expect(derive(left: 32_767) == [.leftTrigger])
    #expect(derive(left: 0, right: 65_535) == [.rightTrigger])

    let held = snapshot(.press(.leftTrigger))
    #expect(derive(left: 29_491, after: held) == [.leftTrigger])
    #expect(derive(left: 29_490, after: held).isEmpty)
    #expect(derive(left: 29_491).isEmpty)
  }

  @Test
  func declaredDigitalTriggerIsNeverDerived() {
    #expect(derive(left: 65_535, capabilities: Self.digital).isEmpty)
    var state = snapshot(.press(.rightTrigger))
    state.rightTrigger = .min
    let kept = TriggerButtonDerivation.applying(
      to: state,
      previous: .neutral,
      capabilities: Self.digital
    )
    #expect(kept == state)
  }

  @Test
  func digitalOnlyTriggerDerivesNothing() {
    let digitalOnly = ControllerCapabilities(
      controls: Control.xboxLayout.subtracting([.leftTrigger, .rightTrigger]),
      digitalTriggers: [.leftTrigger, .rightTrigger]
    )
    #expect(digitalOnly.controls.isSuperset(of: [.leftTrigger, .rightTrigger]))
    #expect(derive(left: 65_535, capabilities: digitalOnly).isEmpty)
    #expect(TriggerButtonDerivation.derivedSides(of: digitalOnly).isEmpty)
  }

  @Test
  func eachDriverDeclaresItsDigitalTriggersOrLeavesThemDerived() {
    #expect(TriggerButtonDerivation.derivedSides(of: Self.analogOnly).count == 2)
    #expect(TriggerButtonDerivation.derivedSides(of: Self.digital).isEmpty)
    #expect(!TriggerButtonDerivation.derivedSides(of: XUSBDriver().capabilities).isEmpty)
    #expect(DualShock4Driver().capabilities.digitalTriggers == [.leftTrigger, .rightTrigger])
    #expect(TriggerButtonDerivation.derivedSides(of: DualShock4Driver().capabilities).isEmpty)
  }

  @Test
  func digitalTriggersAreOptionalInStoredForm() throws {
    let encoded = try JSONEncoder().encode(Self.analogOnly)
    #expect(!(String(data: encoded, encoding: .utf8) ?? "").contains("digitalTriggers"))
    #expect(try JSONDecoder().decode(ControllerCapabilities.self, from: encoded) == Self.analogOnly)
    let round = try JSONDecoder().decode(
      ControllerCapabilities.self,
      from: JSONEncoder().encode(Self.digital)
    )
    #expect(round == Self.digital)
  }

  /// The pipeline derives the button with hysteresis against its last normalized state, and a
  /// resumed session starts that memory from neutral.
  @Test
  func pipelineDerivesTriggerButtonsAndResumeForgetsHysteresis() async {
    let driver = OutputCharacterizationTests.ScriptedBatches([
      [.leftTrigger(0.6)], [.leftTrigger(0.47)], [.leftTrigger(0.4)], [.leftTrigger(0.47)],
    ])
    let pipeline = DevicePipeline(
      identifier: LogicalControllerID(vendorID: 0x045E, productID: 0x028E),
      transport: .hid(address: .ioKit(locationID: 1, interfaceNumber: nil)),
      driver: driver,
      dispatcher: OutputCharacterizationTests.PipelineOutput(),
      idleTimeoutNanoseconds: 5_000_000_000,
      idleMonitorIntervalNanoseconds: 5_000_000_000
    )
    await pipeline.start()
    var pressed: [Bool] = []
    for batch in 0..<3 {
      _ = await pipeline.feedHIDData(Data([UInt8(batch)]))
      pressed.append(await pipeline.inputState().pressed.contains(.leftTrigger))
    }
    #expect(pressed == [true, true, false])
    _ = await pipeline.feedHIDData(Data([0]))
    #expect(await pipeline.inputState().pressed.contains(.leftTrigger))
    #expect(await pipeline.suspendControllerSession())
    #expect(await pipeline.resumeControllerSession())
    _ = await pipeline.feedHIDData(Data([3]))
    #expect(!(await pipeline.inputState().pressed.contains(.leftTrigger)))
    await pipeline.stop()
  }
}
