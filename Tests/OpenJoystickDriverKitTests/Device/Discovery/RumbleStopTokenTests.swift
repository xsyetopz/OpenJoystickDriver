import Testing

@testable import OpenJoystickDriverKit

struct RumbleStopTokenTests {
  @Test func replacingTokenInvalidatesPreviousDelayedStop() {
    let identifier = DeviceIdentifier(vendorID: 1, productID: 2, locationID: 3)
    var registry = RumbleStopTokenRegistry()

    let previous = registry.replace(for: identifier)
    let current = registry.replace(for: identifier)

    #expect(!registry.isCurrent(previous, for: identifier))
    #expect(registry.isCurrent(current, for: identifier))
  }

  @Test func tokensAreIndependentPerPhysicalController() {
    let first = DeviceIdentifier(vendorID: 1, productID: 2, locationID: 3)
    let second = DeviceIdentifier(vendorID: 1, productID: 2, locationID: 4)
    var registry = RumbleStopTokenRegistry()

    let firstToken = registry.replace(for: first)
    let secondToken = registry.replace(for: second)
    _ = registry.replace(for: first)

    #expect(!registry.isCurrent(firstToken, for: first))
    #expect(registry.isCurrent(secondToken, for: second))
  }

  @Test func removingTokenPreventsDelayedStop() {
    let identifier = DeviceIdentifier(vendorID: 1, productID: 2, locationID: 3)
    var registry = RumbleStopTokenRegistry()
    let token = registry.replace(for: identifier)

    registry.remove(identifier)

    #expect(!registry.isCurrent(token, for: identifier))
  }
}
