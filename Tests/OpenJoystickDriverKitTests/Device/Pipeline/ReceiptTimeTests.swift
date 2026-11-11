import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct ReceiptTimeTests {
  @Test
  func hidAndUSBParsingDeliverReceiptTimeToTheProtocolHook() async throws {
    let (calls, continuation) = AsyncStream<ReceiptTimeParser.Call>.makeStream()
    var iterator = calls.makeAsyncIterator()
    let parser = ReceiptTimeParser(continuation: continuation)
    let pipeline = DevicePipeline(
      identifier: LogicalControllerID(vendorID: 1, productID: 2),
      transport: .hid(address: .ioKit(locationID: 77, interfaceNumber: nil)),
      driver: parser,
      dispatcher: LoggingOutputDispatcher()
    )
    await pipeline.start()
    let before = DispatchTime.now().uptimeNanoseconds
    await pipeline.feedHIDData(Data([1]))
    let after = DispatchTime.now().uptimeNanoseconds
    guard case .timed(let observed) = await iterator.next() else {
      Issue.record("Expected a timestamped HID parse")
      return
    }
    #expect((before...after).contains(observed))
    _ = try await pipeline.parseReport(Data([2]), receivedAt: 123)
    #expect(await iterator.next() == .timed(123))
    await pipeline.stop()
  }
}

private final class ReceiptTimeParser: PhysicalProtocolDriver {
  let capabilities = ControllerCapabilities(controls: Control.xboxLayout)
  let sessionPlan = DriverSessionPlan()
  let outputCapabilities = PhysicalControllerOutputCapabilities.none
  let defaultColor: ControllerColor? = nil
  func consumeInputConnectionStateChange() -> ControllerInputConnectionState? { nil }
  enum Call: Equatable, Sendable { case timed(UInt64) }

  private let continuation: AsyncStream<Call>.Continuation

  init(continuation: AsyncStream<Call>.Continuation) { self.continuation = continuation }

  func parse(report _: Data, receivedAt: MonotonicTimestamp) -> ControllerEvent? {
    continuation.yield(.timed(receivedAt.nanoseconds))
    return nil
  }
}
