import Foundation
import OpenJoystickDriverUSB
import Testing

@testable import OpenJoystickDriverKit

private let gamesirVID: UInt16 = 13623  // 0x3537
private let gamesirPID: UInt16 = 4112  // 0x1010
private let hardwareTestsEnabled = ProcessInfo.processInfo.environment["OJD_HARDWARE_TESTS"] == "1"
private let hardwareSkipMessage =
  "[HardwareTest] Skipping USB hardware test; set OJD_HARDWARE_TESTS=1 to require it."

struct HardwarePipelineTests {
  @Test(.enabled(if: hardwareTestsEnabled, Comment(rawValue: hardwareSkipMessage)))
  func testDeviceEnumeration() async throws {
    let devices = try await OpenJoystickDriverUSBTransportProvider().devices()
    let device = devices.first { $0.vendorID == gamesirVID && $0.productID == gamesirPID }
    let found = try #require(device)
    print("[HardwareTest] Found G7 SE: service=\(found.serviceID) location=\(found.locationID)")
  }

  @Test(.enabled(if: hardwareTestsEnabled, Comment(rawValue: hardwareSkipMessage)))
  func testGipHandshakeAndInput() async throws {
    let provider = OpenJoystickDriverUSBTransportProvider()
    let devices = try await provider.devices()
    let device = try #require(
      devices.first { $0.vendorID == gamesirVID && $0.productID == gamesirPID },
      "GameSir G7 SE not found through an available raw USB transport"
    )
    let session = try await provider.open(device, options: USBTransportOpenOptions())
    let parser = GIPParser()

    try await parser.performHandshake(handle: session)
    print("[HardwareTest] Handshake sent - G7 SE LED should be on")

    var gotReport = false
    var parseError: (any Error)?
    for _ in 0..<5 {
      do {
        let data = try await session.readInterruptPacket(endpoint: 0x82, length: 64, timeout: 1_000)
        print("[HardwareTest] Report bytes: \(Array(data).prefix(8))")
        let events = try parser.parse(data: Data(data))
        print("[HardwareTest] Parsed \(events.count) events")
        gotReport = true
        break
      } catch USBTransportError.timeout { continue } catch {
        parseError = error
        break
      }
    }
    await session.close()

    if let parseError { Issue.record("Parse/USB error: \(parseError)") }
    #expect(gotReport)
  }

  @Test func testParserRegistryDispatch() {
    let registry = ParserRegistry()
    let identifier = DeviceIdentifier(vendorID: gamesirVID, productID: gamesirPID)
    let parser = registry.parser(for: identifier)
    #expect(parser is GIPParser)
  }

  @Test func testDeviceIdentifierMatching() {
    let id1 = DeviceIdentifier(vendorID: gamesirVID, productID: gamesirPID, serialNumber: "ABC123")
    let id2 = DeviceIdentifier(vendorID: gamesirVID, productID: gamesirPID, serialNumber: "XYZ789")
    let id3 = DeviceIdentifier(vendorID: 0x045E, productID: 0x02EA)
    #expect(id1.modelMatches(id2))
    #expect(!id1.modelMatches(id3))
    #expect(!id1.exactlyMatches(id2))
  }
}
