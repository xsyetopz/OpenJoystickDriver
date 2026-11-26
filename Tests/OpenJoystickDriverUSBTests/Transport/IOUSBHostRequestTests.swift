import Foundation
import IOKit
import Testing

@testable import OpenJoystickDriverUSB

struct IOUSBHostRequestTests {
  @Test
  func enqueueThatFailsThrowsItsError() async {
    let refusal = NSError(domain: NSPOSIXErrorDomain, code: Int(EBUSY))

    await #expect(throws: refusal) {
      _ = try await IOUSBHostRequest.run { _ in throw refusal }
    }
  }

  @Test
  func completedRequestReturnsStatusAndCount() async throws {
    let (status, count) = try await IOUSBHostRequest.run { completion in
      DispatchQueue.global().async { completion(kIOReturnSuccess, 7) }
    }

    #expect(status == kIOReturnSuccess)
    #expect(count == 7)
  }

  @Test
  func handlerAfterFailedEnqueueIsIgnored() async {
    let refusal = NSError(domain: NSPOSIXErrorDomain, code: Int(EBUSY))
    let captured = CapturedCompletion()

    await #expect(throws: refusal) {
      _ = try await IOUSBHostRequest.run { completion in
        captured.store(completion)
        throw refusal
      }
    }

    // The request already failed, so a completion arriving afterwards must not resume it again.
    captured.complete(kIOReturnSuccess, 1)
  }
}

/// Holds the completion handler of a request so a test can call it at a chosen moment.
private final class CapturedCompletion: @unchecked Sendable {
  private let lock = NSLock()
  private var handler: ((IOReturn, Int) -> Void)?

  func store(_ completion: @escaping (IOReturn, Int) -> Void) {
    lock.withLock { handler = completion }
  }

  func complete(_ status: IOReturn, _ count: Int) {
    lock.withLock { handler }?(status, count)
  }
}
