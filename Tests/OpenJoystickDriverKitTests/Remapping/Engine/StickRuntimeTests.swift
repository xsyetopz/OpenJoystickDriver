import Testing
@testable import OpenJoystickDriverKit

struct StickRuntimeTests {
  @Test func aimIntegratesTimeAndStopsOnRelease() {
    var stick = RemappingStickRuntime(mapping: RemappingStickMapping(
      source: .right, aimDegreesPerSecond: 100, pointerPointsPerDegree: 2
    ))
    let initial = stick.update(x: 1, y: 0, at: 0)
    #expect(initial == .zero)
    #expect(stick.needsTicks)
    let movement = stick.advance(at: 10_000_000)
    #expect(movement.pointerDelta == SIMD2(2, 0))
    let release = stick.update(x: 0, y: 0, at: 20_000_000)
    #expect(release.pointerDelta == SIMD2(2, 0))
    #expect(!stick.needsTicks)
    let stopped = stick.advance(at: 30_000_000)
    #expect(stopped == .zero)
  }

  @Test func flickCompletesAfterStickReturnsToCenter() {
    var stick = RemappingStickRuntime(mapping: RemappingStickMapping(source: .right, mode: .flick))
    _ = stick.update(x: 1, y: 0, at: 0)
    #expect(stick.needsTicks)
    let half = stick.update(x: 0, y: 0, at: 50_000_000)
    #expect(half.pointerDelta == SIMD2(45, 0))
    let completed = stick.advance(at: 100_000_000)
    #expect(completed.pointerDelta == SIMD2(45, 0))
    #expect(!stick.needsTicks)
  }

  @Test func rotateOnlySkipsInitialFlickAndInvalidInputCancels() {
    var stick = RemappingStickRuntime(mapping: RemappingStickMapping(
      source: .right, mode: .rotateOnly
    ))
    let first = stick.update(x: 1, y: 0, at: 0)
    #expect(first == .zero)
    let rotation = stick.update(x: 0, y: 1, at: 1)
    #expect(rotation.pointerDelta == SIMD2(-90, 0))
    let invalid = stick.update(x: .nan, y: 0, at: 2)
    #expect(invalid == .zero)
    #expect(!stick.needsTicks)
  }

  @Test func areaAndRingReturnToTheirActivationAnchor() {
    var area = RemappingStickRuntime(mapping: RemappingStickMapping(
      source: .left,
      mode: .pointerArea,
      tuning: RemappingStickTuning(innerDeadzone: 0),
      pointerRadiusPoints: 100
    ))
    #expect(area.update(x: 0.5, y: 0, at: 0).pointerDelta == SIMD2(50, 0))
    #expect(area.update(x: 0, y: 0, at: 1).pointerDelta == SIMD2(-50, 0))

    var ring = RemappingStickRuntime(mapping: RemappingStickMapping(
      source: .right,
      mode: .pointerRing,
      tuning: RemappingStickTuning(innerDeadzone: 0),
      pointerRadiusPoints: 80
    ))
    #expect(ring.update(x: 0.25, y: 0, at: 0).pointerDelta == SIMD2(80, 0))
    #expect(ring.update(x: 0, y: 0, at: 1).pointerDelta == SIMD2(-80, 0))
  }

  @Test func scrollAccumulatesShortestAngularTravelAcrossWrap() {
    var stick = RemappingStickRuntime(mapping: RemappingStickMapping(
      source: .left,
      mode: .scrollWheel,
      tuning: RemappingStickTuning(innerDeadzone: 0),
      scrollDegreesPerLine: 30,
      rotationDirection: .counterclockwise
    ))
    _ = stick.update(x: -1, y: 0.01, at: 0)
    let wrapped = stick.update(x: -1, y: -1, at: 1)
    #expect(wrapped.scrollLines == SIMD2(0, 1))
    #expect(!stick.needsTicks)
  }

  @Test func steeringWindsAndReturnsAtConfiguredRate() {
    var stick = RemappingStickRuntime(mapping: RemappingStickMapping(
      source: .left,
      mode: .steering,
      tuning: RemappingStickTuning(innerDeadzone: 0),
      rotationDirection: .counterclockwise,
      steeringDegreesAtFullScale: 180,
      steeringReturnDegreesPerSecond: 90
    ))
    _ = stick.update(x: 1, y: 0, at: 0)
    let wound = stick.update(x: 0, y: 1, at: 1)
    #expect(wound.virtualAxes[.leftStickX] == 0.5)
    _ = stick.update(x: 0, y: 0, at: 1)
    #expect(stick.needsTicks)
    var returned = RemappingStickRuntimeOutput()
    for step in 1...10 {
      returned = stick.advance(at: UInt64(step) * 100_000_000 + 1)
    }
    #expect(returned.virtualAxes[.leftStickX] == 0)
    #expect(!stick.needsTicks)
  }
}
