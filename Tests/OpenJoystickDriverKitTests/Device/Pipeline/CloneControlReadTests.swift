import Foundation
import OpenJoystickDriverTestSupport
import ProtocolPacketFixtures
import Testing

@testable import OpenJoystickDriverKit

/// The bundled `045e:028e` record gives the three clone control reads to a pad whose manufacturer
/// is `SHANWAN` and to no other pad, and the pipeline sends them before its first startup write.
struct CloneControlReadTests {
  private typealias Fixture = ProtocolPacketFixtures.XUSBCloneControlReads

  private static let model = ControllerModelID(vendorID: 0x045E, productID: 0x028E)

  private static func device(manufacturer: String?) -> USBTransportDevice {
    USBTransportDevice(
      route: .rawUSB,
      serviceID: 1,
      vendorID: 0x045E,
      productID: 0x028E,
      locationID: 1,
      productName: "Controller",
      manufacturer: manufacturer
    )
  }

  /// Runs startup for the bundled record against `manufacturer` and returns the wire events.
  private static func startupEvents(manufacturer: String?) async throws -> [String] {
    let device = device(manufacturer: manufacturer)
    let record = try #require(ControllerRecordSet.bundled.records[model])
    let pipeline = DevicePipeline(
      identifier: LogicalControllerID(vendorID: 0x045E, productID: 0x028E),
      transport: .usb(device: device),
      driver: XUSBDriver(),
      dispatcher: LoggingOutputDispatcher(),
      binding: ProtocolBinding(
        protocolID: .xboxXUSB,
        variant: nil,
        accessBackend: .rawUSB,
        interfaceNumber: nil,
        rule: .catalogRecord,
        matchedPredicates: [],
        record: record.profile
      ),
      startupPlayerIndicator: .player1
    )
    let session = EventRecordingUSBTransportSession()
    await pipeline.activateForTesting()
    await pipeline.setUSBHandleForTesting(session)
    #expect(await pipeline.performUSBHandshake(handle: session, device: device))
    return await session.events()
  }

  @Test
  func theRecordHoldsTheFixtureTableWithItsGateAndTimeout() throws {
    let record = try #require(ControllerRecordSet.bundled.records[Self.model])
    let transfers = record.profile.session.controlTransfers
    #expect(
      transfers.map {
        Fixture.Read(
          bmRequestType: $0.bmRequestType,
          bRequest: $0.bRequest,
          wValue: $0.wValue,
          wIndex: $0.wIndex,
          wLength: $0.wLength
        )
      } == Fixture.reads
    )
    for transfer in transfers {
      #expect(transfer.match.manufacturer == Fixture.manufacturer)
      #expect(transfer.timeoutMilliseconds == Fixture.timeoutMilliseconds)
      #expect(transfer.toleratesRejection)
    }
  }

  @Test
  func aShanwanPadGetsTheThreeReadsInOrderBeforeTheFirstStartupWrite() async throws {
    let events = try await Self.startupEvents(manufacturer: Fixture.manufacturer)
    let reads = Fixture.reads.map { "control \($0.bmRequestType) \($0.bRequest) \($0.wValue)" }
    #expect(Array(events.prefix(reads.count)) == reads)
    #expect(events.dropFirst(reads.count).first == "write")
  }

  @Test(arguments: ["Microsoft", "Logitech", nil])
  func anyOtherPadGetsNoRead(manufacturer: String?) async throws {
    let events = try await Self.startupEvents(manufacturer: manufacturer)
    #expect(events.first == "write")
    #expect(!events.contains { $0.hasPrefix("control") })
  }
}

private actor EventRecordingUSBTransportSession: USBTransportSession {
  private var recorded: [String] = []

  func controlTransfer(_ request: USBControlTransferRequest, timeout: UInt32) throws -> [UInt8] {
    recorded.append("control \(request.requestType) \(request.request) \(request.value)")
    return []
  }

  func write(endpoint: UInt8, data: [UInt8], timeout: UInt32) throws -> Int {
    recorded.append("write")
    return data.count
  }

  func read(endpoint: UInt8, length: Int, timeout: UInt32) throws -> [UInt8] {
    throw USBTransportError.timeout
  }

  func events() -> [String] { recorded }
}
