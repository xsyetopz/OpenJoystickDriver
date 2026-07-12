import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct LogitechF310MappingTests {
  private let identifier = DeviceIdentifier(vendorID: 1_133, productID: 49_693)

  @Test
  func profileSelectsUnverifiedXbox360Parser() {
    let profile = ParserRegistry().runtimeProfile(for: identifier)

    #expect(profile.parserName == "Xbox360")
    #expect(profile.protocolVariant == .xbox360)
    #expect(!profile.hardwareVerified)
    #expect(profile.transportProfile.inputEndpoint == 0x81)
    #expect(profile.transportProfile.outputEndpoint == 0x01)
  }

  @Test
  func xinputButtonsReachNamedDiagnosticState() throws {
    let expected: [(Int, Button)] = [
      (4, .start), (5, .back), (6, .leftStick), (7, .rightStick),
      (8, .a), (9, .b), (10, .x), (11, .y),
      (12, .leftBumper), (13, .rightBumper), (14, .guide),
    ]

    for (bit, button) in expected {
      let parser = Xbox360Parser()
      let events = try parser.parse(data: report(buttons: UInt16(1 << bit)))
      var state = DeviceInputState(vendorID: identifier.vendorID, productID: identifier.productID)
      state.apply(events: events)

      #expect(events.contains(.buttonPressed(button)))
      #expect(state.pressedButtons == [button.rawValue])
    }
  }

  @Test
  func inputTestUsesStableXboxLabelsInsteadOfOptionalSymbols() throws {
    #expect(Button.leftBumper.compactLabel == "LB")
    #expect(Button.rightBumper.compactLabel == "RB")
    #expect(Button.a.compactLabel == "A")
    #expect(Button.guide.compactLabel == "Guide")

    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let view = try String(
      contentsOf: root.appendingPathComponent(
        "Sources/OpenJoystickDriver/Views/InputTestWindowView.swift"
      ),
      encoding: .utf8
    )
    #expect(view.contains("Text(button.compactLabel)"))
    #expect(view.contains(#"case "Xbox360":"#))
    #expect(view.contains(".leftBumper, .rightBumper"))
  }

  private func report(buttons: UInt16) -> Data {
    var bytes = [UInt8](repeating: 0, count: 20)
    bytes[0] = 0x00
    bytes[1] = 0x14
    bytes[2] = UInt8(buttons & 0xFF)
    bytes[3] = UInt8(buttons >> 8)
    return Data(bytes)
  }
}
