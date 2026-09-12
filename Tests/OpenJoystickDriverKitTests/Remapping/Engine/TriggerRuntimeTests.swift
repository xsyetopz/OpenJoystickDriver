import Testing

@testable import OpenJoystickDriverKit

struct TriggerRuntimeTests {
  @Test func simultaneousAndExclusiveModesOrderStageChanges() {
    var simultaneous = RemappingDualStageTriggerRuntime(mapping: mapping(.simultaneous))
    #expect(simultaneous.update(value: 0.2, at: 0) == [change(.soft, true)])
    #expect(simultaneous.update(value: 1, at: 1) == [change(.full, true)])
    #expect(simultaneous.update(value: 0, at: 2) == [change(.soft, false), change(.full, false)])

    var exclusive = RemappingDualStageTriggerRuntime(mapping: mapping(.exclusive))
    #expect(exclusive.update(value: 0.2, at: 0) == [change(.soft, true)])
    #expect(exclusive.update(value: 1, at: 1) == [change(.soft, false), change(.full, true)])
    #expect(exclusive.update(value: 0.2, at: 2) == [change(.full, false), change(.soft, true)])
  }

  @Test(arguments: [
    RemappingDualStageTriggerMode.preferFull,
    .preferFullCombined,
    .responsivePreferFull,
    .responsivePreferFullCombined,
  ])
  func quickFullPullSuppressesSoftUntilCompleteRelease(mode: RemappingDualStageTriggerMode) {
    var runtime = RemappingDualStageTriggerRuntime(mapping: mapping(mode))
    let started = runtime.update(value: 0.2, at: 0)
    #expect(started == (mode.emitsSoftWhileBuffered ? [change(.soft, true)] : []))
    #expect(runtime.deadline == 100_000_000)
    let full = runtime.update(value: 1, at: 50_000_000)
    let expected = mode.emitsSoftWhileBuffered
      ? [change(.soft, false), change(.full, true)] : [change(.full, true)]
    #expect(full == expected)
    #expect(runtime.update(value: 0.5, at: 60_000_000) == [change(.full, false)])
    #expect(runtime.update(value: 0.2, at: 70_000_000).isEmpty)
    #expect(runtime.update(value: 0, at: 80_000_000).isEmpty)
  }

  @Test(arguments: [
    RemappingDualStageTriggerMode.preferFull,
    .preferFullCombined,
    .responsivePreferFull,
    .responsivePreferFullCombined,
  ])
  func deadlineSelectsSoftAndOnlyCombinedModesPermitLateFull(
    mode: RemappingDualStageTriggerMode
  ) {
    var runtime = RemappingDualStageTriggerRuntime(mapping: mapping(mode))
    _ = runtime.update(value: 0.2, at: 0)
    let deadline = runtime.advance(at: 100_000_000)
    #expect(deadline == (mode.emitsSoftWhileBuffered ? [] : [change(.soft, true)]))
    let lateFull = runtime.update(value: 1, at: 100_000_001)
    #expect(lateFull == (mode.permitsLateFullPull ? [change(.full, true)] : []))
  }

  private func mapping(_ mode: RemappingDualStageTriggerMode) -> RemappingTriggerMapping {
    RemappingTriggerMapping(
      source: .left,
      mode: mode,
      softThreshold: 0.1,
      fullThreshold: 0.9,
      hysteresis: 0.05,
      skipWindowMs: 100
    )
  }

  private func change(
    _ stage: RemappingTriggerStage,
    _ active: Bool
  ) -> RemappingTriggerStageChange {
    RemappingTriggerStageChange(stage: stage, isActive: active)
  }
}
