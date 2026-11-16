import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverPresentation

struct HiddenChangeNoticeTests {
  private static let device = RemappingDeviceScope(vendorID: 0x1234, productID: 0x5678)
  private static let binding = RemappingBinding(
    source: .button(.south),
    destination: .mouseButton(.left)
  )

  private static func profile(
    outputPolicy: RemappingOutputPolicy = .systemInput,
    motionTuning: RemappingMotionTuning = .default,
    gyroOutput: RemappingGyroOutput = .default,
    pointerSpeed: RemappingPointerSpeed? = nil,
    stickMappings: [RemappingStickMapping] = [],
    triggerMappings: [RemappingTriggerMapping] = [],
    bindings: [RemappingBinding] = [binding],
    layers: [RemappingLayer] = []
  ) -> RemappingProfile {
    RemappingProfile(
      name: "Test",
      device: device,
      applicationScope: .global,
      outputPolicy: outputPolicy,
      motionTuning: motionTuning,
      gyroOutput: gyroOutput,
      pointerSpeed: pointerSpeed,
      stickMappings: stickMappings,
      triggerMappings: triggerMappings,
      bindings: bindings,
      layers: layers
    )
  }

  @Test
  func noticeShowsOnlyInSimpleWithChange() {
    #expect(!HiddenChangeNotice.Content.changed(0).isShown(at: .simple))
    #expect(HiddenChangeNotice.Content.changed(1).isShown(at: .simple))
    #expect(!HiddenChangeNotice.Content.changed(1).isShown(at: .advanced))
    #expect(HiddenChangeNotice.Content.needsAdvanced.isShown(at: .simple))
    #expect(!HiddenChangeNotice.Content.needsAdvanced.isShown(at: .advanced))
  }

  @Test
  func noticeTextLocalizedWithPluralForm() {
    #expect(HiddenChangeNotice.Content.changed(1).message != "ui.interface.hiddenChanges")
    #expect(HiddenChangeNotice.Content.needsAdvanced.message != "ui.interface.areaNeedsAdvanced")
  }

  @Test
  func controllerWithOnlyDefaultsCountsNothing() {
    let rows = ControllerDetailRow.changedHiddenRows(
      virtualGamepadOverride: nil,
      stickDeadzone: nil
    )
    #expect(rows.isEmpty)
  }

  @Test
  func setVirtualGamepadKindCountsOne() {
    let rows = ControllerDetailRow.changedHiddenRows(
      virtualGamepadOverride: .generic,
      stickDeadzone: nil
    )
    #expect(rows == [.virtualGamepadKind])
  }

  @Test
  func defaultProfileCountsNothing() {
    #expect(ProfilesRow.changedHiddenRows(in: Self.profile()).isEmpty)
  }

  @Test
  func changedOutputPolicyCounts() {
    let mapped = RemappingOutputPolicy(virtualGamepad: .mapped, physicalInput: .shared)
    let exclusive = RemappingOutputPolicy(virtualGamepad: .disabled, physicalInput: .exclusive)
    #expect(
      ProfilesRow.changedHiddenRows(in: Self.profile(outputPolicy: mapped)) == [.outputPolicy]
    )
    #expect(
      ProfilesRow.changedHiddenRows(in: Self.profile(outputPolicy: exclusive)) == [.outputPolicy]
    )
  }

  @Test
  func adjustedAxisCountsAndDefaultAdjustmentDoesNot() {
    let axis = RemappingSource.axis(.leftStickX)
    let destination = RemappingDestination.mouseButton(.left)
    let adjusted = RemappingBinding(
      source: axis,
      destination: destination,
      axisTuning: RemappingAxisTuning(gain: 2)
    )
    let untouched = RemappingBinding(
      source: axis,
      destination: destination,
      axisTuning: .default
    )
    #expect(
      ProfilesRow.changedHiddenRows(in: Self.profile(bindings: [adjusted])) == [.axisAdjustment]
    )
    #expect(ProfilesRow.changedHiddenRows(in: Self.profile(bindings: [untouched])).isEmpty)
  }

  @Test
  func analogMappingsCountOnce() {
    let profile = Self.profile(
      stickMappings: [RemappingStickMapping(source: .left)],
      triggerMappings: [RemappingTriggerMapping(source: .left)]
    )
    #expect(ProfilesRow.changedHiddenRows(in: profile) == [.analogModes])
  }

  @Test
  func pointerSpeedCounts() {
    let speed = RemappingPointerSpeed(
      driver: RemappingPointerSpeedDriver(type: .trigger, side: .left),
      minScale: 0.5,
      maxScale: 2
    )
    #expect(ProfilesRow.changedHiddenRows(in: Self.profile(pointerSpeed: speed)) == [.pointerSpeed])
  }

  @Test
  func motionTuningAndGyroOutputCountOnce() {
    let tuned = RemappingMotionTuning(pitchSensitivity: 2)
    let gyro = RemappingGyroOutput(mode: .mouse)
    #expect(ProfilesRow.changedHiddenRows(in: Self.profile(motionTuning: tuned)) == [.motion])
    #expect(
      ProfilesRow.changedHiddenRows(in: Self.profile(motionTuning: tuned, gyroOutput: gyro))
        == [.motion]
    )
    #expect(ProfilesRow.changedHiddenRows(in: Self.profile(gyroOutput: gyro)) == [.motion])
  }

  @Test
  func regionSourceCounts() {
    let region = RemappingSource.stickRegion(
      RemappingStickRegionSource(stick: .left, innerRadius: 0.5, outerRadius: 1)
    )
    let regionBinding = RemappingBinding(
      source: region,
      destination: .mouseButton(.left)
    )
    #expect(
      ProfilesRow.changedHiddenRows(in: Self.profile(bindings: [regionBinding])) == [.regions]
    )
  }

  @Test
  func severalChangesCountEachRowOnce() {
    let profile = Self.profile(
      outputPolicy: RemappingOutputPolicy(virtualGamepad: .passthrough, physicalInput: .shared),
      gyroOutput: RemappingGyroOutput(mode: .mouse),
      stickMappings: [RemappingStickMapping(source: .left)]
    )
    #expect(ProfilesRow.changedHiddenRows(in: profile) == [.outputPolicy, .analogModes, .motion])
  }
}
