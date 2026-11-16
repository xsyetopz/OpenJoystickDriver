import Foundation
import Testing

@testable import OpenJoystickDriverKit

/// The 0x10 rumble report and the player-indicator subcommand of the Switch 1 driver, whose
/// layouts live in `nintendo-switch1.json`.
struct Switch1DescribedOutputTests {
  private static let intensities: [(left: UInt8, right: UInt8)] = [
    (0x00, 0x00), (0x12, 0x34), (0x80, 0x40), (0xFF, 0xFF),
  ]

  private func hex(_ write: PhysicalOutputWrite) -> String {
    guard case .hidOutput(let report) = write else { return "other" }
    return "\(report.reportID):" + report.bytes.map { unsafe String(format: "%02x", $0) }.joined()
  }

  /// Four rumble reports, then every player indicator, on one driver: the counter runs through
  /// all nine and each indicator report carries the last rumble.
  private func sequence(_ layout: NintendoControllerLayout) throws -> [String] {
    let driver = Switch1Driver(layout: layout)
    var lines: [String] = []
    for motors in Self.intensities {
      let rumble = RumbleIntensities(
        lowFrequency: UnipolarValue(UInt16(motors.left) << 8),
        highFrequency: UnipolarValue(UInt16(motors.right) << 8)
      )
      lines += try driver.encode(.setRumble(rumble, duration: .held)).writes.map(hex)
    }
    for indicator in PhysicalPlayerIndicator.allCases {
      lines += try driver.encode(.setPlayerIndicator(indicator)).writes.map(hex)
    }
    return lines
  }

  @Test
  func proRumbleAndPlayerIndicatorBytes() throws {
    #expect(
      try sequence(.pro) == [
        "16:10000001404000014040",
        "16:1001001bc047003bc04f",
        "16:1002008bc06300494052",
        "16:100300c9407200c94072",
        "1:010400c9407200c940723000",
        "1:010500c9407200c940723001",
        "1:010600c9407200c940723003",
        "1:010700c9407200c940723007",
        "1:010800c9407200c94072300f",
      ]
    )
  }

  @Test
  func leftJoyConDrivesOnlyItsOwnSide() throws {
    #expect(
      try sequence(.leftJoyCon) == [
        "16:10000001404000014040",
        "16:1001001bc04700014040",
        "16:1002008bc06300014040",
        "16:100300c9407200014040",
        "1:010400c94072000140403000",
        "1:010500c94072000140403001",
        "1:010600c94072000140403003",
        "1:010700c94072000140403007",
        "1:010800c9407200014040300f",
      ]
    )
  }

  @Test
  func rightJoyConDrivesOnlyItsOwnSide() throws {
    #expect(
      try sequence(.rightJoyCon) == [
        "16:10000001404000014040",
        "16:100100014040003bc04f",
        "16:10020001404000494052",
        "16:10030001404000c94072",
        "1:01040001404000c940723000",
        "1:01050001404000c940723001",
        "1:01060001404000c940723003",
        "1:01070001404000c940723007",
        "1:01080001404000c94072300f",
      ]
    )
  }

  /// The rumble report's counter byte is the session counter: 0 through 15, then 0 again.
  @Test
  func rumbleCounterProgressesAndWraps() throws {
    let driver = Switch1Driver()
    var counters: [UInt8] = []
    for _ in 0..<18 {
      guard case .hidOutput(let report) = try driver.encode(.stopRumble).writes[0] else {
        Issue.record("expected a HID output report")
        return
      }
      counters.append(report.bytes[1])
    }
    #expect(counters == Array(0..<16) + [0, 1])
  }

  /// A description holds the rumble report and the player-indicator patterns.
  @Test
  func descriptionNamesRumbleReportAndPlayerIndicatorPatterns() throws {
    let description = PhysicalProtocolID.nintendoSwitch1.protocolDescription
    let template = try #require(description.rumbleTemplate(variant: .usb))
    #expect(template.report == ControllerTemplateReport(kind: .output, reportID: 0x10, length: 10))
    #expect(template.counterByte == 1)
    #expect(template.motors[.lowFrequency]?.encoding == .switchHDRumble)
    let indicator = try #require(description.subcommands?.playerIndicator)
    #expect(indicator.subcommand == 0x30)
    #expect(indicator.pattern(for: .player3) == 0x07)
  }

  /// A record's template replaces the description's for its controller.
  @Test
  func recordTemplateOverridesDescriptionsTemplate() throws {
    let template = try RumbleOutputTemplate(
      target: .hid(ControllerTemplateReport(kind: .output, reportID: 0x10, length: 10)),
      motors: [.lowFrequency: .init(byte: 2, encoding: .switchHDRumble)],
      counterByte: 1
    )
    let driver = Switch1Driver(rumbleTemplate: template)
    let rumble = RumbleIntensities(
      lowFrequency: UnipolarValue(0xFF00),
      highFrequency: UnipolarValue(0xFF00)
    )
    let writes = try driver.encode(.setRumble(rumble, duration: .held)).writes
    #expect(writes.map(hex) == ["16:100000c9407200000000"])
  }

  private static func recordTemplate() throws -> RumbleOutputTemplate {
    try RumbleOutputTemplate(
      target: .hid(ControllerTemplateReport(kind: .output, reportID: 0x10, length: 10)),
      motors: [
        .lowFrequency: .init(byte: 6, encoding: .switchHDRumble),
        .highFrequency: .init(byte: 2, encoding: .switchHDRumble),
      ],
      counterByte: 1
    )
  }

  /// A record template places the motors where it names them, and a Joy-Con still drives only its
  /// own side.
  @Test
  func recordTemplateOnJoyConKeepsOtherSideOff() throws {
    let driver = Switch1Driver(layout: .leftJoyCon, rumbleTemplate: try Self.recordTemplate())
    let rumble = RumbleIntensities(
      lowFrequency: UnipolarValue(0xFF00),
      highFrequency: UnipolarValue(0xFF00)
    )
    let writes = try driver.encode(.setRumble(rumble, duration: .held)).writes
    #expect(writes.map(hex) == ["16:10000001404000c94072"])
  }

  /// The Bluetooth driver encodes from the description's template for its variant.
  @Test
  func bluetoothDriverEncodesFromDescriptionsTemplate() throws {
    let driver = Switch1Driver(layout: .rightJoyCon, isBluetooth: true)
    let rumble = RumbleIntensities(
      lowFrequency: UnipolarValue(0xFF00),
      highFrequency: UnipolarValue(0xFF00)
    )
    let writes = try driver.encode(.setRumble(rumble, duration: .held)).writes
    #expect(writes.map(hex) == ["16:10000001404000c94072"])
  }

  /// A record's template reaches the driver the registry builds.
  @Test
  func registryPassesRecordsTemplateToDriver() throws {
    let proController = ControllerModelID(vendorID: 0x057E, productID: 0x2009)
    var profile = try #require(ControllerRecordSet.bundled.records[proController]?.profile)
    #expect(profile.physicalProtocolID == .nintendoSwitch1)
    profile.session = ControllerSession(rumbleTemplate: try Self.recordTemplate())
    let variant = PhysicalProtocolVariantID.usb
    guard
      case .success(let built) = ProtocolDriverRegistry.makeUnobservedDriver(
        protocolID: .nintendoSwitch1,
        variant: variant,
        record: profile,
        model: ControllerModelID(vendorID: 0x057E, productID: 0x2009),
        transportProfile: profile.transportProfile
      )
    else {
      Issue.record("the registry builds a Switch 1 driver")
      return
    }
    let driver = try #require(built as? Switch1Driver)
    let rumble = RumbleIntensities(lowFrequency: UnipolarValue(0xFF00), highFrequency: .min)
    let writes = try driver.encode(.setRumble(rumble, duration: .held)).writes
    guard case .hidOutput(let report) = writes[0] else {
      Issue.record("expected a HID output report")
      return
    }
    #expect(Array(report.bytes[2..<6]) == [0x00, 0x01, 0x40, 0x40])
    #expect(Array(report.bytes[6..<10]) == [0x00, 0xC9, 0x40, 0x72])
  }
}
