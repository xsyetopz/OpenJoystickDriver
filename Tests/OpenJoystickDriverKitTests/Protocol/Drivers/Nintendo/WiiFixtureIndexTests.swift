import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct WiiFixtureIndexTests {
  private static let description = PhysicalProtocolID.nintendoWii.protocolDescription

  @Test
  func everyReportModeOfTheDescriptionHasAFixture() throws {
    let modes = try #require(Self.description.wiiRemote).reportModes
    for mode in modes {
      #expect(try !WiiFixtures.names(id: mode.id).isEmpty, "mode \(String(mode.id, radix: 16))")
    }
  }

  @Test
  func everyStatusReadReplyAndAcknowledgementCaseHasAFixture() throws {
    let names = try WiiFixtures.names()
    for name in [
      "20-status-no-extension", "20-status-extension", "20-status-battery-full",
      "20-status-battery-low", "21-read-success", "21-read-error", "22-ack-success",
      "22-ack-error",
    ] {
      #expect(names.contains(name), "\(name)")
    }
  }

  @Test
  func everyFixtureNamesItsSourceAndStartsWithItsReportId() throws {
    for name in try WiiFixtures.names() {
      #expect(try WiiFixtures.header(name).hasPrefix("# WiiBrew-derived ("), "\(name)")
      #expect(try WiiFixtures.report(name).first == UInt8(name.prefix(2), radix: 16), "\(name)")
    }
  }

  @Test
  func everyModeFixtureHasTheLengthOfItsLayout() throws {
    let modes = try #require(Self.description.wiiRemote).reportModes
    for mode in modes {
      let last = try #require(mode.blocks.last)
      for name in try WiiFixtures.names(id: mode.id) {
        #expect(try WiiFixtures.report(name).count == 1 + last.offset + last.length, "\(name)")
      }
    }
  }
}
