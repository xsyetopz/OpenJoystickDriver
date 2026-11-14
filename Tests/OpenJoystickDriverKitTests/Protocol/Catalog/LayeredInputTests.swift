import Foundation
import Testing

@testable import OpenJoystickDriverKit

/// A record of any family may hold `input.layouts`; the driver of the family
/// reads every report and the layouts decide the controls they name.
struct LayeredInputTests {
  private func layout(
    report: [String: any Sendable],
    button: String,
    bitOffset: Int
  ) -> [String: any Sendable] {
    [
      "layouts": [
        [
          "report": report,
          "buttons": [
            ["control": button, "bitOffset": bitOffset, "bitSize": 1] as [String: any Sendable]
          ],
        ] as [String: any Sendable]
      ]
    ]
  }

  private func driver(
    family: String,
    variant: String? = nil,
    input: [String: any Sendable],
    runtimeVariant: String? = nil
  ) throws -> any PhysicalProtocolDriver {
    var protocolInfo: [String: any Sendable] = ["family": family]
    protocolInfo["variant"] = variant
    let record: [String: Any] = [
      "apiVersion": OpenJoystickDriverAPI.version, "kind": ControllerRecordDocument.kind,
      "vendorID": 0x045E, "productID": 0x02EA, "input": input,
      "modes": [["id": "default", "protocol": protocolInfo]],
    ]
    let document = try JSONDecoder().decode(
      ControllerRecordDocument.self,
      from: JSONSerialization.data(withJSONObject: record)
    )
    let profile = try DeviceCatalog.makeRuntimeProfile(document)
    return try ProtocolDriverRegistry.makeUnobservedDriver(
      protocolID: profile.physicalProtocolID,
      variant: profile.physicalProtocolVariant
        ?? runtimeVariant.flatMap(PhysicalProtocolVariantID.init(rawValue:)),
      record: profile,
      model: ControllerModelID(vendorID: 0x045E, productID: 0x02EA),
      transportProfile: profile.transportProfile
    ).get()
  }

  @Test
  func gipRecordWithLayoutReadsLayoutAndKeepsFamilyDriver() throws {
    // Report 0x20 of 18 bytes; the layout names East at bit 0 of byte 5.
    let input = layout(
      report: ["id": 0x20, "length": ["atLeast": 18] as [String: Int]],
      button: "East",
      bitOffset: 40
    )
    let driver = try driver(family: "XboxGIP", input: input, runtimeVariant: "USB")
    var report: [UInt8] = [0x20, 0x00, 0x01, 0x0E, 0x04, 0x01]
    report += [UInt8](repeating: 0, count: 12)
    let event = try #require(try driver.parseReport(Data(report)))
    #expect(event.state.pressed.contains(.east))
    #expect(event.state.pressed.contains(.start))
  }

  @Test
  func xusbLayoutNamingOneButtonLeavesRestToFamily() throws {
    let input = layout(
      report: ["length": ["exactly": 20] as [String: Int]],
      button: "North",
      bitOffset: 24
    )
    let driver = try driver(family: "XboxXUSB", variant: "Wired", input: input)
    var report = [UInt8](repeating: 0, count: 20)
    report[1] = 0x14
    report[3] = 0x11  // bit 4 is South in the family, bit 0 is the layout's North
    let event = try #require(try driver.parseReport(Data(report)))
    #expect(event.state.pressed.contains(.north))
    #expect(event.state.pressed.contains(.south))
  }

  @Test
  func reportNoLayoutSelectsDecodedByFamilyAlone() throws {
    let input = layout(
      report: ["length": ["exactly": 20] as [String: Int]],
      button: "North",
      bitOffset: 24
    )
    let driver = try driver(family: "XboxXUSB", variant: "Wired", input: input)
    var report = [UInt8](repeating: 0, count: 21)
    report[1] = 0x14
    report[3] = 0x11
    let event = try #require(try driver.parseReport(Data(report)))
    #expect(event.state.pressed.contains(.south))
    #expect(!event.state.pressed.contains(.north))
  }

  @Test
  func hidDescriptorRecordTakesLayouts() throws {
    let input = layout(
      report: ["length": ["atLeast": 1] as [String: Int]],
      button: "South",
      bitOffset: 0
    )
    let driver = try driver(family: "HIDDescriptor", input: input)
    let event = try #require(try driver.parseReport(Data([0x01])))
    #expect(event.state.pressed.contains(.south))
  }

  @Test
  func gipRecordReadsLayoutOfReportThatIsNoGIPFrame() throws {
    // The layout selects report 0x07 of 8 bytes; its length field never ends, so GIP throws
    // on it.
    let input = layout(
      report: ["id": 0x07, "length": ["exactly": 8] as [String: Int]],
      button: "West",
      bitOffset: 8
    )
    let driver = try driver(family: "XboxGIP", input: input, runtimeVariant: "USB")
    let report: [UInt8] = [0x07, 0x01, 0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]
    let event = try #require(try driver.parseReport(Data(report)))
    #expect(event.state.pressed.contains(.west))
  }

  @Test
  func gipRecordStillThrowsOnMalformedReportNoLayoutSelects() throws {
    let input = layout(
      report: ["id": 0x07, "length": ["exactly": 8] as [String: Int]],
      button: "West",
      bitOffset: 8
    )
    let driver = try driver(family: "XboxGIP", input: input, runtimeVariant: "USB")
    #expect(throws: (any Error).self) {
      try driver.parseReport(Data([0x07, 0x01, 0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]))
    }
  }
}
