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

    await #expect(throws: refusal) {
      _ = try await IOUSBHostRequest.run { completion in
        DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(10)) {
          completion(kIOReturnSuccess, 1)
        }
        throw refusal
      }
    }
  }
}
