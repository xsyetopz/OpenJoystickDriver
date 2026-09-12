import Foundation
import Testing
@testable import OpenJoystickDriverKit

struct StickTransformTests {
  @Test func radialCalibrationPreservesDirectionAndBoundsDiagonalSpeed() throws {
    let tuning = RemappingStickTuning(innerDeadzone: 0.2, outerDeadzone: 0.2)
    #expect(RemappingStickTransform.value(x: 0.1, y: 0.1, tuning: tuning) == .zero)
    let middle = try #require(RemappingStickTransform.value(x: 0.5, y: 0, tuning: tuning))
    #expect(abs(middle.x - 0.5) < 1e-12)
    let diagonal = try #require(RemappingStickTransform.value(x: 1, y: 1, tuning: tuning))
    #expect(abs(hypot(diagonal.x, diagonal.y) - 1) < 1e-12)
    #expect(diagonal.x == diagonal.y)
  }

  @Test func rejectsInvalidCalibrationAndInput() {
    #expect(RemappingStickTransform.value(x: .nan, y: 0, tuning: .default) == nil)
    #expect(RemappingStickTransform.value(
      x: 1, y: 0, tuning: RemappingStickTuning(innerDeadzone: 0.5, outerDeadzone: 0.5)
    ) == nil)
    #expect(RemappingStickTransform.value(
      x: 1, y: 0, tuning: RemappingStickTuning(responseExponent: .infinity)
    ) == nil)
  }
}
