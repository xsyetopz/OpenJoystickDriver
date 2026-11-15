import Foundation
import IOKit
import OpenJoystickDriverKit
import SwifterKit
import Testing

@testable import OpenJoystickDriverUSB

struct USBDriverKitPendingTransfersTests {
  @Test
  func completionBeforeEnqueueResponseIsNotLost() async throws {
    let pending = USBDriverKitPendingTransfers {}
    try await pending.beginSubmission()
    await pending.receive(try completion(id: 1, data: [0x20, 0, 1]))
    let received = try await pending.wait(requestID: 1, timeout: 100)
    #expect(received.data == [0x20, 0, 1])
    await pending.close(error: .disconnected)
  }

  @Test
  func simultaneousRequestsMatchTheirOwnCompletion() async throws {
    let pending = USBDriverKitPendingTransfers {}
    try await pending.beginSubmission()
    try await pending.beginSubmission()
    await pending.receive(try completion(id: 2, data: [2]))
    await pending.receive(try completion(id: 1, data: [1]))
    let first = try await pending.wait(requestID: 1, timeout: 100)
    let second = try await pending.wait(requestID: 2, timeout: 100)
    #expect(first.data == [1])
    #expect(second.data == [2])
    await pending.close(error: .disconnected)
  }

  @Test
  func lateCompletionResumesTheWaitingRequest() async throws {
    let pending = USBDriverKitPendingTransfers {}
    try await pending.beginSubmission()
    let waiter = Task { try await pending.wait(requestID: 1, timeout: 1_000) }
    while await pending.waitingCount == 0 { await Task.yield() }
    await pending.receive(try completion(id: 1, data: [0x07]))
    #expect(try await waiter.value.data == [0x07])
    await pending.close(error: .disconnected)
  }

  @Test
  func idleDeadlineClosesTheRuntimeAndResumesAllRequests() async throws {
    let closes = RuntimeCloseCount()
    let pending = USBDriverKitPendingTransfers { await closes.increment() }
    try await pending.beginSubmission()
    try await pending.beginSubmission()
    let other = Task { try await pending.wait(requestID: 2, timeout: 0) }
    while await pending.waitingCount == 0 { await Task.yield() }
    await #expect(throws: USBTransportError.timeout) {
      try await pending.wait(requestID: 1, timeout: 10)
    }
    await #expect(throws: USBTransportError.timeout) { try await other.value }
    await pending.close(error: .disconnected)
    #expect(await closes.calls == 1)
    await #expect(throws: USBTransportError.disconnected) { try await pending.beginSubmission() }
  }

  @Test
  func closeDuringEnqueueCannotInstallAnOrphanedWaiter() async throws {
    let pending = USBDriverKitPendingTransfers {}
    try await pending.beginSubmission()
    await pending.close(error: .disconnected)
    await pending.receive(try completion(id: 1, data: [1]))
    await #expect(throws: USBTransportError.disconnected) {
      try await pending.wait(requestID: 1, timeout: 0)
    }
    #expect(await pending.waitingCount == 0)
  }

  @Test
  func failedNativeCompletionPreservesItsError() async throws {
    let pending = USBDriverKitPendingTransfers {}
    try await pending.beginSubmission()
    await pending.receive(try completion(id: 1, status: kIOReturnTimeout))
    await #expect(throws: USBTransportError.timeout) {
      try await pending.wait(requestID: 1, timeout: 100)
    }
    await pending.close(error: .disconnected)
  }

  @Test
  func idlePipeAbortAllowsTheNextRequestWithoutClosingTheConnection() async throws {
    let closes = RuntimeCloseCount()
    let aborts = RuntimeCloseCount()
    let pending = USBDriverKitPendingTransfers { await closes.increment() }
    try await pending.beginSubmission()
    await #expect(throws: USBTransportError.timeout) {
      try await pending.wait(requestID: 1, timeout: 10) {
        await aborts.increment()
      }
    }
    #expect(await aborts.calls == 1)
    #expect(await closes.calls == 0)
    #expect(await pending.isClosed == false)
    try await pending.beginSubmission()
    // A delayed abort completion belongs to the expired request, not the new read.
    await pending.receive(try completion(id: 1, status: kIOReturnAborted))
    await pending.receive(try completion(id: 2, data: [0x20]))
    #expect(try await pending.wait(requestID: 2, timeout: 100).data == [0x20])
    await pending.close(error: .disconnected)
  }

  @Test
  func abortFailureClosesTheConnectionAndWakesTheCaller() async throws {
    let pending = USBDriverKitPendingTransfers {}
    try await pending.beginSubmission()
    await #expect(throws: USBTransportError.disconnected) {
      try await pending.wait(requestID: 1, timeout: 10) {
        throw USBTransportError.disconnected
      }
    }
    #expect(await pending.isClosed)
  }

  private func completion(
    id: UInt32,
    status: Int32 = 0,
    data: [UInt8] = []
  ) throws
    -> USBPipeIOCompletion
  {
    var payload = [UInt8](repeating: 0, count: 24)
    for (offset, value) in [(0, id), (4, UInt32(bitPattern: status)), (8, UInt32(data.count))] {
      for byte in 0..<4 { payload[offset + byte] = UInt8(truncatingIfNeeded: value >> (byte * 8)) }
    }
    payload[12] = 0x81
    payload += data
    // SwifterKit's runtime wire id for a pipe-I/O completion.
    let event = DriverEvent(type: 0x0200, payload: payload)
    guard case .pipeIO(let completion) = try event.usb() else {
      throw USBTransportError.notSupported
    }
    return completion
  }
}

private actor RuntimeCloseCount {
  private(set) var calls = 0
  func increment() { calls += 1 }
}
