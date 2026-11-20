import Foundation
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit

// The ZD O+ Excellence answers 057E:2009 "Pro Controller" at bcdDevice 0x0020. Served with nothing
// sent, it re-enumerates as 11C0:5505 "Xbox 360 for Windows Controller" on the XUSB wired interface
// (255/93/1, IN 0x81), as its owner's plug-in log and support report show.
struct ZDOPlusRecordTests {
  private static let catalog = DeviceCatalog(records: .bundled)

  private static func switchPad(release: UInt16) -> PhysicalDevice {
    PhysicalDevice(
      vendorID: 0x057E,
      productID: 0x2009,
      deviceRelease: release,
      interfaces: [gamepadHIDInterface(host: .usb)]
    )
  }

  @Test
  func switchModeReleaseIsHeldByOJD() {
    #expect(Self.catalog.statedServer(of: Self.switchPad(release: 0x0020)) == .ojd)
  }

  // A Thunderobot G50S (0x0200) and a GameSir Cyclone 2 dongle (0x0116) share 057E:2009 and need
  // the Switch handshake.
  @Test
  func otherReleasesKeepTheSwitchProtocol() throws {
    let profile = try #require(
      Self.catalog.record(for: ControllerModelID(vendorID: 0x057E, productID: 0x2009))
    )
    #expect(profile.physicalProtocolID == .nintendoSwitch1)
    for release: UInt16 in [0x0200, 0x0116] {
      let device = Self.switchPad(release: release)
      #expect(Self.catalog.statedServer(of: device) == nil)
      #expect(!profile.modes.contains { $0.match.holds(for: device, receiverRecord: false) })
    }
  }

  @Test
  func xboxModeRecordRunsXUSBWired() throws {
    let model = ControllerModelID(vendorID: 0x11C0, productID: 0x5505)
    let profile = try #require(Self.catalog.record(for: model))
    #expect(profile.physicalProtocolID == .xboxXUSB)
    #expect(profile.physicalProtocolVariant == .wired)
    #expect(profile.playerIndicatorTemplate == nil)
  }
}
