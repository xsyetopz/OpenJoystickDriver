import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverUSB

/// The extension passes timeout 0 on interrupt pipes (#55): `IOUSBHostPipe::IO` answers
/// `kIOReturnBadArgument` to any other value there.
struct USBInterruptTimeoutTests {
  @Test
  func interruptPipesGetZeroWhateverTheRequestedTimeout() async {
    let policy = USBPipeTimeoutPolicy { _ in 0x03 }

    #expect(await policy.timeout(endpoint: 0x81, requestedMilliseconds: 2_000) == 0)
    #expect(await policy.timeout(endpoint: 0x01, requestedMilliseconds: 750) == 0)
  }

  @Test
  func bulkPipesKeepTheRequestedTimeout() async {
    let policy = USBPipeTimeoutPolicy { _ in 0x02 }

    #expect(await policy.timeout(endpoint: 0x02, requestedMilliseconds: 2_000) == 2_000)
  }

  @Test
  func anUnreadablePipeKeepsTheRequestedTimeoutAndIsAskedAgain() async {
    let lookups = LookupCounter()
    let policy = USBPipeTimeoutPolicy { _ in
      await lookups.increment()
      throw USBTransportError.notFound
    }

    #expect(await policy.timeout(endpoint: 0x81, requestedMilliseconds: 500) == 500)
    #expect(await policy.timeout(endpoint: 0x81, requestedMilliseconds: 500) == 500)
    #expect(await lookups.count == 2)
  }

  @Test
  func eachEndpointIsLookedUpOnce() async {
    let lookups = LookupCounter()
    let policy = USBPipeTimeoutPolicy { endpoint in
      await lookups.increment()
      return endpoint == 0x81 ? 0x03 : 0x02
    }

    _ = await policy.timeout(endpoint: 0x81, requestedMilliseconds: 10)
    _ = await policy.timeout(endpoint: 0x81, requestedMilliseconds: 10)
    #expect(await policy.timeout(endpoint: 0x02, requestedMilliseconds: 10) == 10)
    #expect(await lookups.count == 2)
  }
}

private actor LookupCounter {
  private(set) var count = 0
  func increment() { count += 1 }
}
