import Foundation
import Testing

@testable import OpenJoystickDriverKit

@Suite
struct ControllerRecordStartupDecodeMessageTests {
  private static let report = #""report": {"kind": "Output", "id": 1, "length": 7}"#

  private static func message(_ json: String) -> String? {
    do {
      _ = try JSONDecoder().decode(
        ControllerRecordDocument.StartupWrite.self,
        from: Data(json.utf8)
      )
      return nil
    } catch {
      return ControllerRecordSet.problemDescription(
        error,
        document: "record",
        localization: Localization(preferredLanguages: ["en-US"]),
        file: "046d-c21d.plist"
      )
    }
  }

  @Test
  func packetReferenceInRecordNamesKey() {
    #expect(
      Self.message(#"{"packet": "xbox/start-input"}"#)
        == "046d-c21d.plist, session.startup[].packet: A startup packet reference is only for "
        + "protocol descriptions. Fix: Write the bytes in the record instead of packet."
    )
  }

  @Test
  func unknownTransportNamesKey() {
    #expect(
      Self.message("{\(Self.report), \"transport\": \"Radio\"}")
        == "046d-c21d.plist, session.startup[].transport: A startup transport must be USB, "
        + "BluetoothClassic or BluetoothLE. Fix: Set transport to one of them, or leave it out."
    )
  }

  @Test
  func unknownPhaseNamesKey() {
    #expect(
      Self.message("{\(Self.report), \"phase\": \"Boot\"}")
        == "046d-c21d.plist, session.startup[].phase: A startup phase must be Startup or "
        + "Activation. Fix: Set phase to one of them, or leave it out."
    )
  }

  @Test
  func seedOutsideItsRangeNamesKey() {
    #expect(
      Self.message("{\(Self.report), \"crc32Seed\": 256}")
        == "046d-c21d.plist, session.startup[].crc32Seed: A startup crc32Seed must be 0...255. "
        + "Fix: Set crc32Seed to 0...255, or leave it out."
    )
  }

  @Test
  func usbEndpointOutsideItsRangeNamesKey() {
    #expect(
      Self.message(#"{"bytes": "01", "endpoint": 128}"#)
        == "046d-c21d.plist, session.startup[].endpoint: A USB startup endpoint must be "
        + "1...127. Fix: Set endpoint to 1...127, or leave it out."
    )
  }
}
