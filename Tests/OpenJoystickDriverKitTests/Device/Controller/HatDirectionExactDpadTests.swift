import Testing

@testable import OpenJoystickDriverKit

/// The D-pad initializers name a direction only for the eight valid flag combinations.
struct HatDirectionExactDpadTests {
  private static let expected:
    [(up: Bool, right: Bool, down: Bool, left: Bool, direction: HatDirection)] = [
      (true, false, false, false, .north),
      (true, true, false, false, .northEast),
      (false, true, false, false, .east),
      (false, true, true, false, .southEast),
      (false, false, true, false, .south),
      (false, false, true, true, .southWest),
      (false, false, false, true, .west),
      (true, false, false, true, .northWest),
    ]

  @Test
  func everyFlagCombinationMapsToItsDirectionOrNeutral() {
    for bits in 0..<16 {
      let up = bits & 1 != 0
      let right = bits & 2 != 0
      let down = bits & 4 != 0
      let left = bits & 8 != 0
      let direction =
        Self.expected.first {
          $0.up == up && $0.right == right && $0.down == down && $0.left == left
        }?.direction ?? .neutral
      #expect(HatDirection(exactUp: up, right: right, down: down, left: left) == direction)
    }
  }

  @Test
  func opposingDirectionsGiveNeutral() {
    #expect(HatDirection(exactUp: true, right: false, down: true, left: false) == .neutral)
    #expect(HatDirection(exactUp: false, right: true, down: false, left: true) == .neutral)
    #expect(HatDirection(exactUp: true, right: true, down: true, left: false) == .neutral)
    #expect(HatDirection(exactUp: true, right: true, down: true, left: true) == .neutral)
  }

  @Test
  func nibbleReadsUpDownLeftRightAsBitsOneTwoFourEight() {
    let table: [(UInt8, HatDirection)] = [
      (0, .neutral), (1, .north), (2, .south), (4, .west), (8, .east), (9, .northEast),
      (5, .northWest), (10, .southEast), (6, .southWest), (3, .neutral), (12, .neutral),
      (7, .neutral), (11, .neutral), (13, .neutral), (14, .neutral), (15, .neutral),
    ]
    for (bits, direction) in table { #expect(HatDirection(dpadNibble: bits) == direction) }
  }

  @Test
  func nibbleIgnoresHigherBits() {
    #expect(HatDirection(dpadNibble: 0xF1) == .north)
    #expect(HatDirection(dpadNibble: 0x10) == .neutral)
  }

  @Test
  func clockwiseValueRunsFromNorthAndAnythingElseIsNeutral() {
    let directions: [HatDirection] = [
      .north, .northEast, .east, .southEast, .south, .southWest, .west, .northWest,
    ]
    for (value, direction) in directions.enumerated() {
      #expect(HatDirection(clockwiseFromNorth: UInt8(value)) == direction)
    }
    for value: UInt8 in [8, 15, 16, 255] {
      #expect(HatDirection(clockwiseFromNorth: value) == .neutral)
    }
  }

  @Test
  func maskedBitsMapToTheDirectionOfTheirMasks() {
    func direction(_ bits: UInt32) -> HatDirection {
      HatDirection(exactBits: bits, up: 0x2000, right: 0x800, down: 0x400, left: 0x1000)
    }
    #expect(direction(0x2000) == .north)
    #expect(direction(0x2800) == .northEast)
    #expect(direction(0x0400) == .south)
    #expect(direction(0x1400) == .southWest)
    #expect(direction(0x2400) == .neutral)
    #expect(direction(0x0001) == .neutral)
    #expect(direction(0x3000 | 0x0001) == .northWest)
  }
}
