import Foundation
import Testing

@testable import OpenJoystickDriverKit

/// The bundled `044F:B671` wheel reads steering from bytes 6 to 7 and the brake from bytes 10 to 11
/// of GIP report `0x20`; the packets are the reporter's of issue #58.
struct Wheel044FB671RecordTests {
  private static let model = ControllerModelID(vendorID: 0x044F, productID: 0xB671)

  private func capture(_ reports: [String]) -> Data {
    Data(
      reports.map { #"{"direction":"Rx","hex":"\#($0)","length":21}"# }
        .joined(separator: "\n").utf8
    )
  }

  private func expectation(leftStickX: Int, leftTrigger: Int, rightTrigger: Int) -> Data {
    Data(
      """
      {"pressed":[],"hat":"Neutral","leftStick":{"x":\(leftStickX),"y":0},\
      "rightStick":{"x":0,"y":4096},"leftTrigger":\(leftTrigger),"rightTrigger":\(rightTrigger),\
      "pointer":{"x":0,"y":0},"touch":[]}
      """.utf8
    )
  }

  private func difference(_ reports: [String], _ expected: Data) throws -> Int {
    let record = try #require(ControllerRecordSet.bundled.records[Self.model])
    return try record.test(capture: capture(reports), expectation: expected).differences.count
  }

  @Test
  func steeringReadsAsTheLeftStickInsteadOfTheLeftTrigger() throws {
    let report = "20 00 61 11 00 00 B8 03 00 00 00 00 00 00 00 00 00 F0 00 00 C0"
    #expect(
      try difference([report], expectation(leftStickX: -31815, leftTrigger: 0, rightTrigger: 0))
        == 0
    )
  }

  @Test
  func theBrakeReadsAsTheLeftTrigger() throws {
    let report = "20 00 61 11 00 00 00 80 00 00 FF 03 00 00 00 00 00 F0 00 00 C0"
    #expect(
      try difference([report], expectation(leftStickX: 0, leftTrigger: 65535, rightTrigger: 0)) == 0
    )
  }
}
