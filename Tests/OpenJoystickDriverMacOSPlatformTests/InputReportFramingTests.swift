import Testing

@testable import OpenJoystickDriverMacOSPlatform

struct InputReportFramingTests {
  @Test
  func numberedReportWithoutItsIDGetsIDPrefixed() {
    #expect(
      HIDDeviceStream.framedInputReport(reportID: 0x11, bytes: [0xC0, 0x00]) == [0x11, 0xC0, 0x00]
    )
  }

  @Test
  func numberedReportThatAlreadyStartsWithItsIDIsUnchanged() {
    #expect(
      HIDDeviceStream.framedInputReport(reportID: 0x01, bytes: [0x01, 0x80]) == [0x01, 0x80]
    )
  }

  @Test
  func unnumberedReportIsUnchanged() {
    #expect(HIDDeviceStream.framedInputReport(reportID: 0, bytes: [0x05, 0x06]) == [0x05, 0x06])
  }
}
