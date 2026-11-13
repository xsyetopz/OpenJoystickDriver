import CoreFoundation
import Testing

@testable import OpenJoystickDriverPresentation

@Suite
struct OJDLayoutTests {
  @Test
  func sheetsHaveThreeWidths() {
    #expect(OJDSheetWidth.allCases.map(\.rawValue) == [420, 480, 520])
  }

  @Test
  func spacingScaleGrows() {
    let scale = OJDSpacing.scale
    #expect(scale == scale.sorted())
    #expect(Set(scale).count == scale.count)
  }

  @Test
  func sheetPaddingOnScale() {
    #expect(OJDSpacing.scale.contains(OJDSpacing.sheetPadding))
  }
}
