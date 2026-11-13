import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct ProtocolBindingIDTests {
  @Test
  func writesFamilyAndOptionalVariant() {
    #expect(ProtocolBindingID(.xboxXUSB, variant: .receiver).rawValue == "XboxXUSB:Receiver")
    #expect(ProtocolBindingID(.valveSteamDeck).rawValue == "ValveSteamDeck")
    #expect(
      ProtocolBindingID(rawValue: "SonyDualShock4:BluetoothClassic")
        == ProtocolBindingID(.sonyDualShock4, variant: .bluetoothClassic)
    )
  }

  @Test
  func spellsEachSideOfTheBindingInKebabCaseOnTheCommandLine() {
    #expect(
      ProtocolBindingID(.xboxXUSB, variant: .receiver).commandLineName == "xbox-xusb:receiver"
    )
    #expect(
      ProtocolBindingID(.vendorGameSir, variant: .enhancedHID).commandLineName
        == "vendor-game-sir:enhanced-hid"
    )
    #expect(
      ProtocolBindingID(.valveSteamController, variant: .bluetoothLE).commandLineName
        == "valve-steam-controller:bluetooth-le"
    )
    #expect(ProtocolBindingID(.valveSteamDeck).commandLineName == "valve-steam-deck")
  }

  @Test(arguments: [
    "", "XboxXUSB:", "xboxOne", "GIP", "XboxGIP:USB:usb", "SonyDualSense:Receiver",
    "XboxXID:USB", "XboxXUSB:xbox360Wireless", "VendorGameSir:EnhancedHID-8k",
    // A binding is resolved: families with variants always name one.
    "XboxGIP", "XboxXUSB", "VendorGameSir", "SonyDualSense",
  ])
  func rejectsUnknownFamiliesAndVariantsOutsideTheFamily(_ text: String) throws {
    #expect(ProtocolBindingID(rawValue: text) == nil)
    let json = try JSONEncoder().encode([text])
    #expect(throws: DecodingError.self) {
      try JSONDecoder().decode([ProtocolBindingID].self, from: json)
    }
  }

  @Test
  func rawUSBRowsReportTheirResolvedBinding() throws {
    let registry = ProtocolDriverRegistry()
    let gip = try #require(
      registry.record(for: ControllerModelID(vendorID: 0x045E, productID: 0x02EA))
    )
    let receiver = try #require(
      registry.record(for: ControllerModelID(vendorID: 0x045E, productID: 0x0719))
    )
    let dualSense = try #require(
      registry.record(for: ControllerModelID(vendorID: 0x054C, productID: 0x0CE6))
    )
    #expect(gip.rawUSBBinding?.rawValue == "XboxGIP:USB")
    #expect(receiver.rawUSBBinding?.rawValue == "XboxXUSB:Receiver")
    #expect(dualSense.rawUSBBinding == nil)
  }

  @Test
  func encodesAsItsWrittenForm() throws {
    let binding = ProtocolBindingID(.valveSteamController, variant: .dongle)
    let json = try JSONEncoder().encode([binding])
    #expect(String(bytes: json, encoding: .utf8) == #"["ValveSteamController:Dongle"]"#)
    #expect(try JSONDecoder().decode([ProtocolBindingID].self, from: json) == [binding])
  }
}
