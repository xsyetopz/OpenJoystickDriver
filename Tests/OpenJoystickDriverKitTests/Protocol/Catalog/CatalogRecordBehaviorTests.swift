import Foundation
import ProtocolPacketFixtures
import Testing

@testable import OpenJoystickDriverKit

/// Parser configuration each catalog row selects, keyed only by identity so the
/// expectations do not depend on how the record spells its selections.
struct CatalogRecordBehaviorTests {
  private let registry = ProtocolDriverRegistry()

  private static func powerOn(_ sequence: UInt8) -> [UInt8] { [5, 32, sequence, 1, 0] }
  private static func ledOn(_ sequence: UInt8) -> [UInt8] { [10, 32, sequence, 3, 0, 1, 20] }
  private static let authDone: [UInt8] = [6, 32, 1, 2, 1, 0]
  private static func xboxOneSInit(_ sequence: UInt8) -> [UInt8] { [5, 32, sequence, 15, 6] }
  private static func horiAck(_ sequence: UInt8) -> [UInt8] {
    [1, 32, sequence, 9, 0, 4, 32, 58, 0, 0, 0, 128, 0]
  }
  private static func rumbleBegin(_ sequence: UInt8) -> [UInt8] {
    [9, 0, sequence, 9, 0, 15, 0, 0, 29, 29, 255, 0, 0]
  }
  private static func rumbleEnd(_ sequence: UInt8) -> [UInt8] {
    [9, 0, sequence, 9, 0, 15, 0, 0, 0, 0, 0, 0, 0]
  }

  static let startupSequences: [(UInt16, UInt16, [[UInt8]])] = [
    (0x045E, 0x0B12, [powerOn(1), ledOn(2), authDone]),
    (0x045E, 0x02EA, [powerOn(1), xboxOneSInit(2), ledOn(3), authDone]),
    (0x045E, 0x0B00, [powerOn(1), xboxOneSInit(2), [77, 16, 1, 2, 7, 0], ledOn(3), authDone]),
    (0x0E6F, 0x0165, [horiAck(1), powerOn(2), ledOn(3), authDone]),
    (0x0F0D, 0x0067, [horiAck(1), powerOn(2), ledOn(3), authDone]),
    (0x24C6, 0x541A, [powerOn(1), ledOn(2), authDone, rumbleBegin(1), rumbleEnd(2)]),
    (0x24C6, 0x542A, [powerOn(1), ledOn(2), authDone, rumbleBegin(1), rumbleEnd(2)]),
    (0x24C6, 0x543A, [powerOn(1), ledOn(2), authDone, rumbleBegin(1), rumbleEnd(2)]),
  ]

  @Test(arguments: startupSequences)
  func gipRowsSendTheirInitializationBytes(
    vendorID: UInt16,
    productID: UInt16,
    expected: [[UInt8]]
  ) throws {
    let parser = try #require(
      try catalogParser(DeviceIdentifier(vendorID: vendorID, productID: productID)) as? GIPDriver
    )
    #expect(parser.startupWrites().usbBytes == expected)
  }

  /// A row's capability delta is evidence against the parser it configures: absences
  /// name declared controls, presences are controls the configured parser emits.
  @Test
  func everyCapabilityDeltaMatchesItsConfiguredParser() throws {
    for identifier in registry.rawUSBIdentifiers + registry.hidIdentifiers {
      let delta = try #require(registry.record(for: identifier)).capabilityDelta
      let parser = try catalogParser(identifier, registry: registry)
      #expect(delta.absentControls.isSubset(of: parser.capabilities.controls), "\(identifier)")
      #expect(delta.presentControls.isSubset(of: parser.capabilities.controls), "\(identifier)")
      if delta.rumbleAbsent {
        #expect(
          (parser as? GIPDriver)?.outputCapabilities.rumbleMotors.isEmpty == true,
          "\(identifier)"
        )
      }
    }
  }

  @Test
  func gameSirRowsSelectTheirProtocolAndQuirks() throws {
    // (product, protocol, inner grips, lighting slots)
    let expectations: [(UInt16, GameSirProtocol, Bool, Bool)] =
      [0x1003, 0x105D, 0x105E, 0x109B, 0x109C, 0x10BA].map { ($0, .g7ProUSB, false, false) }
      + [0x0575, 0x100B, 0x1053].map { ($0, .enhancedHID, false, true) }
      + [0x10C5, 0x10C6, 0x10C7, 0x10C8].map { ($0, .enhancedHID, true, false) }
    for (productID, gameSirProtocol, innerGrips, lightingSlots) in expectations {
      let parser = try #require(
        try catalogParser(DeviceIdentifier(vendorID: 0x3537, productID: productID))
          as? GameSirDriver
      )
      #expect(parser.gameSirProtocol == gameSirProtocol, "\(productID)")
      #expect(parser.hasInnerGrips == innerGrips, "\(productID)")
      #expect(parser.usesLightingSlots == lightingSlots, "\(productID)")
    }
  }

  @Test
  func gipRumbleFollowsTheRow() throws {
    let inputOnly = try #require(
      try catalogParser(DeviceIdentifier(vendorID: 0x3537, productID: 0x1022)) as? GIPDriver
    )
    let standard = try #require(
      try catalogParser(DeviceIdentifier(vendorID: 0x045E, productID: 0x0B12)) as? GIPDriver
    )
    #expect(inputOnly.outputCapabilities.rumbleMotors.isEmpty)
    #expect(
      Set(standard.outputCapabilities.rumbleMotors) == [
        .leftMain, .rightMain, .leftTrigger, .rightTrigger,
      ]
    )
  }

  @Test
  func dualSenseEdgeButtonsFollowTheRow() throws {
    let edge = try #require(
      try catalogParser(DeviceIdentifier(vendorID: 0x054C, productID: 0x0DF2)) as? DualSenseDriver
    )
    let standard = try #require(
      try catalogParser(DeviceIdentifier(vendorID: 0x054C, productID: 0x0CE6)) as? DualSenseDriver
    )
    #expect(edge.hasEdgeButtons)
    #expect(!standard.hasEdgeButtons)
  }

  @Test
  func nintendoRowsSelectTheirLayout() throws {
    let layouts: [(UInt16, NintendoControllerLayout)] = [
      (0x2006, .leftJoyCon), (0x2007, .rightJoyCon), (0x2009, .pro),
    ]
    for (productID, layout) in layouts {
      let parser = try #require(
        try catalogParser(DeviceIdentifier(vendorID: 0x057E, productID: productID))
          as? Switch1Driver
      )
      #expect(parser.layout == layout, "\(productID)")
    }
  }

  @Test
  func switchInputOnlyRowsBindTheFixedReportDriver() throws {
    // HORIPAD for Nintendo Switch and PowerA Wired Controller Plus (SDL SwitchInputOnlyController).
    for (vendorID, productID) in [(UInt16(0x0F0D), UInt16(0x00C1)), (0x20D6, 0xA711)] {
      let identifier = DeviceIdentifier(vendorID: vendorID, productID: productID)
      #expect(try catalogParser(identifier) is SwitchInputOnlyDriver, "\(identifier)")
    }
  }

  @Test
  func seriesXReadsShareFromTheEndRelativeOffset() throws {
    // The 44-byte Series X firmware 5.5 payload carries Share at byte 18 (SDL, xpad).
    var payload = Data(repeating: 0, count: 44)
    payload[18] = 1
    let packet = ProtocolPacketFixtures.GIP.inputPacket(payload: payload)
    let seriesX = try catalogParser(DeviceIdentifier(vendorID: 0x045E, productID: 0x0B12))
    let standard = try catalogParser(DeviceIdentifier(vendorID: 0x045E, productID: 0x02EA))
    #expect(try seriesX.parseReport(packet).contains(.press(.share)))
    #expect(try !standard.parseReport(packet).contains(.press(.share)))
  }
}
