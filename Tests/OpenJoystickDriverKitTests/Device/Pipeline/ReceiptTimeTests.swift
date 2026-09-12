import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct ReceiptTimeTests {
  @Test func hidAndUSBParsingDeliverReceiptTimeToTheProtocolHook() async throws {
    let parser = ReceiptTimeParser()
    let pipeline = DevicePipeline(
      identifier: DeviceIdentifier(vendorID: 1, productID: 2),
      transport: .hid(locationID: 77),
      parser: parser,
      dispatcher: LoggingOutputDispatcher()
    )
    await pipeline.start()
    let before = DispatchTime.now().uptimeNanoseconds
    await pipeline.feedHIDData(Data([1]))
    let after = DispatchTime.now().uptimeNanoseconds
    let observed = try #require(parser.receipts.first)
    #expect((before...after).contains(observed))
    _ = try await pipeline.parseEvents(from: [2], receivedAtNanoseconds: 123)
    #expect(parser.receipts.count == 2)
    #expect(parser.receipts.last == 123)
    #expect(parser.untimedCalls == 0)
    await pipeline.stop()
  }
}

private final class ReceiptTimeParser: InputParser, @unchecked Sendable {
  private let lock = NSLock()
  private var times: [UInt64] = []
  private var oldCalls = 0
  var receipts: [UInt64] { lock.withLock { times } }
  var untimedCalls: Int { lock.withLock { oldCalls } }
  func performHandshake(handle: (any USBTransportSession)?) throws {}
  func parse(data: Data) throws -> [ControllerEvent] {
    lock.withLock { oldCalls += 1 }
    return []
  }
  func parse(data: Data, receivedAtNanoseconds: UInt64) throws -> [ControllerEvent] {
    lock.withLock { times.append(receivedAtNanoseconds) }
    return []
  }
}
