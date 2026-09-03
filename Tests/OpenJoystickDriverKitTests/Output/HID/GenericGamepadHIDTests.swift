import Testing

@testable import OpenJoystickDriverKit

struct GenericGamepadHIDTests {
  @Test func triggerAxesDeclareSignedLogicalRanges() {
    let descriptor = GamepadHIDDescriptor.descriptor

    #expect(
      containsSubsequence(
        in: descriptor,
        expected: [0x09, 0x32, 0x16, 0x01, 0x80, 0x26, 0xFF, 0x7F]
      )
    )
    #expect(
      containsSubsequence(
        in: descriptor,
        expected: [0x09, 0x35, 0x16, 0x01, 0x80, 0x26, 0xFF, 0x7F]
      )
    )
  }

  @Test func triggerReportsReturnToTheExactZeroIdleState() {
    let format = OJDGenericGamepadFormat()
    let neutral = format.buildInputReport(from: VirtualGamepadState())
    let active = format.buildInputReport(
      from: VirtualGamepadState(leftTrigger: 32_767, rightTrigger: 32_767)
    )
    let released = format.buildInputReport(from: VirtualGamepadState())

    #expect(Array(neutral[6...7]) == [0, 0])
    #expect(Array(neutral[12...13]) == [0, 0])
    #expect(Array(active[6...7]) == [0xFF, 0x7F])
    #expect(Array(active[12...13]) == [0xFF, 0x7F])
    #expect(released == neutral)
  }

  @Test func signedAxisNormalizationKeepsTriggerIdleAtZero() {
    #expect(chromiumAxisValue(raw: 0, logicalMinimum: -32_767, logicalMaximum: 32_767) == 0)
    #expect(chromiumAxisValue(raw: 32_767, logicalMinimum: -32_767, logicalMaximum: 32_767) == 1)
  }

  private func chromiumAxisValue(raw: Double, logicalMinimum: Double, logicalMaximum: Double)
    -> Double
  { ((raw - logicalMinimum) / (logicalMaximum - logicalMinimum) * 2) - 1 }

  private func containsSubsequence<T: Equatable>(in values: [T], expected: [T]) -> Bool {
    guard !expected.isEmpty, expected.count <= values.count else { return false }
    return values.indices.dropLast(expected.count - 1).contains { start in
      Array(values[start..<(start + expected.count)]) == expected
    }
  }
}
