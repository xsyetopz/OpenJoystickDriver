import Foundation
import Testing

@testable import OpenJoystickDriverKit

/// The Switch 1 subcommand report, its rolling counter rule and its startup requests come from
/// `defaults.session.subcommands` in the family's description.
///
/// The decoder is the only validator of these documents (the protocol description tests); the bytes
/// the driver sends are pinned in `Switch1SubcommandBytesTests`.
struct SubcommandDescriptionTests {
  private static let plain = #"{"subcommand": 3, "data": "30"}"#
  private static let factoryRead =
    #"{"subcommand": 16, "spiRead": {"address": 24608, "length": 24, "#
    + #""purpose": "FactoryMotionCalibration"}}"#

  private static let indicator =
    #"{"subcommand": 48, "patterns": {"off": 0, "player1": 1, "player2": 3, "#
    + #""player3": 7, "player4": 15}}"#

  private func decode(
    family: PhysicalProtocolID,
    _ body: String
  ) throws(ProtocolDescriptionProblem) -> ProtocolDescription {
    let json = """
      {"apiVersion": "\(OpenJoystickDriverAPI.version)", "kind": "ProtocolDescription",
       "family": "\(family.rawValue)", \(ProtocolDescriptionFixture.variantMembers(of: family))
       \(ProtocolDescriptionFixture.sessionKeyMembers(of: family))
       "endpoints": {"in": 130, "out": 2}, \(body)}
      """
    return try ProtocolDescription.decode(
      Data(json.utf8),
      fileName: "\(family.descriptionFileStem).json"
    )
  }

  private func rejection(family: PhysicalProtocolID, _ body: String) -> ProtocolDescriptionProblem?
  {
    do {
      _ = try decode(family: family, body)
      return nil
    } catch { return error }
  }

  private func switch1(_ subcommands: String) -> String {
    #""defaults": {"session": {"subcommands": \#(subcommands)}}"#
  }

  private func plan(
    modulus: Int = 16,
    _ requests: [String]
  ) -> String {
    let list = requests.joined(separator: ",")
    return
      #"{"reportID": 1, "counterModulus": \#(modulus), "requests": [\#(list)], "#
      + #""playerIndicator": \#(Self.indicator)}"#
  }

  @Test
  func acceptsTheRequestsAndTheCounterRule() throws {
    let description = try decode(
      family: .nintendoSwitch1,
      switch1(plan(modulus: 4, [Self.plain, Self.factoryRead]))
    )
    let subcommands = try #require(description.subcommands)
    #expect(subcommands.reportID == 1)
    #expect(subcommands.requests.count == 2)
    #expect(subcommands.requests[0].data == [48])
    #expect(subcommands.requests[1].data == [32, 96, 0, 0, 24])
    #expect([0, 1, 2, 3, 4].map { subcommands.nextCounter(after: UInt8($0)) } == [1, 2, 3, 0, 1])
  }

  @Test
  func theBundledSwitch1DescriptionHoldsTheFiveStartupRequests() throws {
    let subcommands = try #require(
      PhysicalProtocolID.nintendoSwitch1.protocolDescription.subcommands
    )
    #expect(subcommands.counterModulus == 16)
    #expect(subcommands.requests.map(\.subcommand) == [3, 64, 72, 16, 16])
    #expect(
      subcommands.requests.map(\.data) == [
        [48], [1], [1], [32, 96, 0, 0, 24], [38, 128, 0, 0, 20],
      ]
    )
  }

  @Test
  func rejectsMalformedSubcommands() {
    let badRequests = [
      #"{"subcommand": 3}"#,
      #"{"subcommand": 3, "data": "01", "spiRead": {"address": 0, "length": 1, "#
        + #""purpose": "FactoryMotionCalibration"}}"#,
      #"{"subcommand": 3, "data": ""}"#,
      #"{"subcommand": 3, "data": "100"}"#,
      #"{"subcommand": 256, "data": "01"}"#,
      #"{"subcommand": 3, "data": "01", "extra": 1}"#,
      #"{"subcommand": 16, "spiRead": {"address": 0, "length": 0, "#
        + #""purpose": "FactoryMotionCalibration"}}"#,
      #"{"subcommand": 16, "spiRead": {"address": 0, "length": 30, "#
        + #""purpose": "FactoryMotionCalibration"}}"#,
      #"{"subcommand": 16, "spiRead": {"address": 4294967296, "length": 1, "#
        + #""purpose": "FactoryMotionCalibration"}}"#,
      #"{"subcommand": 16, "spiRead": {"address": 0, "length": 1, "purpose": "other"}}"#,
      #"{"subcommand": 16, "spiRead": {"address": 0, "length": 1}}"#,
    ]
    for request in badRequests {
      #expect(
        rejection(family: .nintendoSwitch1, switch1(plan([request])))?.code
          == .invalidProtocolDescription,
        "\(request)"
      )
    }
    let bad = [
      plan(modulus: 1, [Self.plain]),
      plan(modulus: 257, [Self.plain]),
      plan([]),
      plan(Array(repeating: Self.plain, count: 17)),
      plan([Self.factoryRead, Self.factoryRead]),
      #"{"reportID": 1, "counterModulus": 16, "playerIndicator": \#(Self.indicator)}"#,
      #"{"reportID": 1, "counterModulus": 16, "requests": [\#(Self.plain)]}"#,
      #"{"counterModulus": 16, "requests": [\#(Self.plain)], "#
        + #""playerIndicator": \#(Self.indicator)}"#,
      #"{"reportID": 1, "counterModulus": 16, "requests": [\#(Self.plain)], "#
        + #""playerIndicator": \#(Self.indicator), "extra": 1}"#,
    ]
    for subcommands in bad {
      #expect(
        rejection(family: .nintendoSwitch1, switch1(subcommands))?.code
          == .invalidProtocolDescription,
        "\(subcommands)"
      )
    }
  }

  @Test
  func rejectsMalformedPlayerIndicators() {
    let patterns =
      #""patterns": {"off": 0, "player1": 1, "player2": 3, "player3": 7, "player4": 15}"#
    let bad = [
      #"{"subcommand": 48}"#,
      "{\(patterns)}",
      #"{"subcommand": 256, \#(patterns)}"#,
      #"{"subcommand": 48, "patterns": {"off": 0, "player1": 1}}"#,
      #"{"subcommand": 48, "patterns": {"off": 256, "player1": 1, "player2": 3, "#
        + #""player3": 7, "player4": 15}}"#,
      #"{"subcommand": 48, "patterns": {"off": 0, "player1": 1, "player2": 3, "#
        + #""player3": 7, "player4": 15, "player5": 31}}"#,
      #"{"subcommand": 48, \#(patterns), "extra": 1}"#,
    ]
    for indicator in bad {
      let subcommands =
        #"{"reportID": 1, "counterModulus": 16, "requests": [\#(Self.plain)], "#
        + #""playerIndicator": \#(indicator)}"#
      #expect(
        rejection(family: .nintendoSwitch1, switch1(subcommands))?.code
          == .invalidProtocolDescription,
        "\(indicator)"
      )
    }
  }

  @Test
  func theBundledSwitch1DescriptionHoldsThePlayerPatterns() throws {
    let indicator = try #require(
      PhysicalProtocolID.nintendoSwitch1.protocolDescription.subcommands?.playerIndicator
    )
    #expect(indicator.subcommand == 0x30)
    #expect(PhysicalPlayerIndicator.allCases.map(indicator.pattern(for:)) == [0, 1, 3, 7, 15])
  }
}
