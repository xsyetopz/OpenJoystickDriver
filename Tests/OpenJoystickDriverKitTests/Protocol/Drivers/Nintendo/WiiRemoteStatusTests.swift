import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct WiiRemoteStatusTests {
  private let driver = WiiDriver()
  private let english = Localization(preferredLanguages: ["en-US"])

  @Test
  func aFreshSessionShowsTheNonIRModeNoExtensionAndMotionPlusOff() throws {
    let status = try #require(driver.wiiRemoteStatus)
    #expect(status.reportModeText == "0x31")
    #expect(status.extensionText(english) == "None")
    #expect(status.motionPlusText(english) == "Off")
  }

  @Test
  func aBoundPointerShowsTheBasicIRMode() throws {
    driver.setPointerInputWanted(true)
    #expect(try #require(driver.wiiRemoteStatus).reportModeText == "0x37")
  }

  @Test
  func aKnownExtensionShowsItsNameAndTheReportModeFollowsIt() throws {
    driver.extensionKind = .known("MotionPlusNunchuk")
    let status = try #require(driver.wiiRemoteStatus)
    #expect(status.extensionKind == .motionPlusNunchuk)
    #expect(status.reportMode != 0x31)
    #expect(status.extensionText(english) == "Motion Plus with Nunchuk")
  }

  @Test
  func anUnknownExtensionShowsItsSixBytesInHex() throws {
    driver.extensionKind = .unknown([0x00, 0x00, 0xA4, 0x20, 0x01, 0xFF])
    let status = try #require(driver.wiiRemoteStatus)
    #expect(status.unknownExtensionID == "0000A42001FF")
    #expect(status.extensionText(english) == "Unknown (ID 0000A42001FF)")
  }

  @Test
  func motionPlusShowsCalibratingUntilTheRestOffsetIsMeasured() {
    let calibrating = WiiRemoteStatus(
      reportMode: 0x35,
      extensionKind: nil,
      unknownExtensionID: nil,
      motionPlusActive: true,
      isGyroRestReady: false
    )
    let ready = WiiRemoteStatus(
      reportMode: 0x35,
      extensionKind: nil,
      unknownExtensionID: nil,
      motionPlusActive: true,
      isGyroRestReady: true
    )
    #expect(calibrating.motionPlusText(english) == "Calibrating")
    #expect(ready.motionPlusText(english) == "Ready")
  }

  @Test
  func theJSONNamesAreLowerCamelCaseAndOmitWhatIsAbsent() throws {
    let status = WiiRemoteStatus(
      reportMode: 0x32,
      extensionKind: .nunchuk,
      unknownExtensionID: nil,
      motionPlusActive: false,
      isGyroRestReady: false
    )
    let data = try JSONEncoder().encode(status)
    let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(
      Set(object.keys)
        == ["reportMode", "extensionKind", "motionPlusActive", "isGyroRestReady"]
    )
    #expect(object["extensionKind"] as? String == "Nunchuk")
  }

  @Test
  func everyExtensionKindOfTheDescriptionHasAName() throws {
    let wii = try #require(PhysicalProtocolID.nintendoWii.protocolDescription.wiiRemote)
    for kind in Set(wii.extensions.map(\.kind)) {
      #expect(WiiRemoteStatus.ExtensionKind(rawValue: kind) != nil)
    }
  }
}
