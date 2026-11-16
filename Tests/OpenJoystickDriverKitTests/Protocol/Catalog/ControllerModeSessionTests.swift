import Foundation
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit

/// A mode's `session` is data: vendor control transfers gated by match keys, startup, settle and
/// shutdown steps, and bytes written as uppercase hex pairs separated by single spaces.
struct ControllerModeSessionTests {
  private static func record(family: String, session: [String: Any]) -> [String: Any] {
    var mode: [String: Any] = ["id": "default", "protocol": ["family": family], "session": session]
    if family == "XboxXUSB" { mode["protocol"] = ["family": family, "variant": "Wired"] }
    return [
      "apiVersion": OpenJoystickDriverAPI.version, "kind": ControllerRecordDocument.kind,
      "vendorID": 0x1234, "productID": 0xABCD, "modes": [mode],
    ]
  }

  private static func validated(_ record: [String: Any]) throws -> ValidatedControllerRecord {
    try ControllerRecordSet.validate(PropertyListFixture.data(tree: record))
  }

  private static func problem(_ record: [String: Any]) -> String? {
    do {
      _ = try validated(record)
      return nil
    } catch { return ControllerRecordSet.problemDescription(error, document: "record") }
  }

  private static func read(_ request: Int, gate: [String: Any]) -> [String: Any] {
    [
      "bmRequestType": 192, "bRequest": request, "wValue": 0, "wIndex": 0, "wLength": 8,
      "match": gate,
    ]
  }

  @Test
  func gatedVendorReadsRunOnlyForMatchingManufacturer() throws {
    let gate: [String: Any] = ["manufacturer": "SHANWAN"]
    let reads = (1...3).map { Self.read($0, gate: gate) }
    let session = try #require(
      try Self.validated(Self.record(family: "XboxXUSB", session: ["control": reads])).record
    ).profile.session
    #expect(session.controlTransfers.map(\.bRequest) == [1, 2, 3])
    for transfer in session.controlTransfers {
      #expect(transfer.match.holds(manufacturer: "SHANWAN", product: nil, release: nil))
      #expect(!transfer.match.holds(manufacturer: "OTHER", product: nil, release: nil))
      #expect(!transfer.match.holds(manufacturer: nil, product: nil, release: nil))
    }
  }

  @Test
  func controlTransferCarriesItsFiveSetupFields() throws {
    let session = try #require(
      try Self.validated(
        Self.record(
          family: "XboxXUSB",
          session: ["control": [Self.read(5, gate: ["product": "Pad"])]]
        )
      ).record
    ).profile.session
    let transfer = try #require(session.controlTransfers.first)
    #expect(transfer.bmRequestType == 0xC0)
    #expect(transfer.bRequest == 5)
    #expect(transfer.wValue == 0)
    #expect(transfer.wIndex == 0)
    #expect(transfer.wLength == 8)
    #expect(transfer.match.product == "Pad")
  }

  @Test
  func bytesAreUppercaseHexPairsSeparatedBySingleSpaces() throws {
    func startup(_ bytes: String) -> [String: Any] {
      Self.record(family: "XboxXUSB", session: ["startup": [["bytes": bytes]]])
    }
    for text in ["0x1a 2b", "1a 2b", "1A  2B", "1A2B", " 1A", "1A ", "1A\n", ""] {
      #expect(Self.problem(startup(text)) != nil, "\(text.debugDescription)")
    }
    let accepted = try Self.validated(startup("1A 2B")).record?.profile.session
    #expect(accepted?.usbStartupWrites.count == 1)
  }

  @Test
  func settleAndShutdownAreStepsOfSession() throws {
    let session = try #require(
      try Self.validated(
        Self.record(
          family: "XboxXUSB",
          session: ["settleMilliseconds": 200, "shutdown": [["bytes": "01 02"]]]
        )
      ).record
    ).profile.session
    #expect(session.settleMilliseconds == 200)
    #expect(session.shutdownWrites.count == 1)
  }

  @Test
  func sessionStepOfAnotherTransportIsRejected() {
    let reads = [Self.read(1, gate: ["manufacturer": "SHANWAN"])]
    for session: [String: Any] in [
      ["control": reads], ["settleMilliseconds": 200], ["shutdown": [["bytes": "01 02"]]],
    ] {
      #expect(Self.problem(Self.record(family: "SonySixaxis", session: session)) != nil)
    }
  }

  @Test
  func unknownSessionKeyIsRejected() {
    #expect(
      Self.problem(Self.record(family: "XboxXUSB", session: ["unknownKey": 5])) != nil
    )
  }
}
