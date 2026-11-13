import Foundation
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit

/// A pipeline sends a mode's gated vendor control transfers only when the gate holds for the
/// manufacturer, product and release the `USBTransportDevice` reports.
struct GatedControlTransferTests {
  private static let requests = [1, 2, 3]

  private static func read(_ request: Int) -> [String: Any] {
    [
      "bmRequestType": 192, "bRequest": request, "wValue": 0, "wIndex": 0, "wLength": 8,
      "match": ["manufacturer": "SHANWAN"],
    ]
  }

  private static func device(manufacturer: String?) -> USBTransportDevice {
    USBTransportDevice(
      route: .rawUSB,
      serviceID: 1,
      vendorID: 0x1234,
      productID: 0xABCD,
      locationID: 1,
      productName: "Pad",
      manufacturer: manufacturer
    )
  }

  private static func sentRequests(to device: USBTransportDevice) async throws -> [UInt8] {
    let mode: [String: Any] = [
      "id": "default",
      "protocol": ["family": "XboxXUSB", "variant": "Wired"],
      "session": ["control": requests.map(read)],
    ]
    let document: [String: Any] = [
      "apiVersion": OpenJoystickDriverAPI.version, "kind": ControllerRecordDocument.kind,
      "vendorID": 0x1234, "productID": 0xABCD, "modes": [mode],
    ]
    let validated = try ControllerRecordSet.validate(
      PropertyListFixture.data(tree: document)
    )
    let profile = try #require(validated.record).profile
    let pipeline = DevicePipeline(
      identifier: LogicalControllerID(vendorID: 0x1234, productID: 0xABCD),
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
        record: profile
      )
    )
    let session = ControlRecordingUSBTransportSession()
    try await pipeline.performControlTransfers(
      handle: session,
      device: device,
      runGeneration: nil
    )
    return await session.requests()
  }

  @Test
  func matchingManufacturerReceivesAllThreeReadsInOrder() async throws {
    let sent = try await Self.sentRequests(to: Self.device(manufacturer: "SHANWAN"))
    #expect(sent == [1, 2, 3])
  }

  @Test
  func differentManufacturerReceivesNone() async throws {
    let sent = try await Self.sentRequests(to: Self.device(manufacturer: "OTHER"))
    #expect(sent.isEmpty)
  }

  @Test
  func deviceWithoutManufacturerReceivesNone() async throws {
    let sent = try await Self.sentRequests(to: Self.device(manufacturer: nil))
    #expect(sent.isEmpty)
  }
}

private actor ControlRecordingUSBTransportSession: USBTransportSession {
  private var sent: [UInt8] = []

  func controlTransfer(_ request: USBControlTransferRequest, timeout _: UInt32) -> [UInt8] {
    sent.append(request.request)
    return []
  }

  func write(endpoint _: UInt8, data: [UInt8], timeout _: UInt32) -> Int { data.count }

  func read(endpoint _: UInt8, length _: Int, timeout _: UInt32) throws -> [UInt8] {
    throw USBTransportError.timeout
  }

  func requests() -> [UInt8] { sent }
}
