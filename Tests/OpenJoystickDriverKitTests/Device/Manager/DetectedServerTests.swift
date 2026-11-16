import Testing

@testable import OpenJoystickDriverKit

struct DetectedServerTests {
  @Test(arguments: [
    (true, true, ControllerServer.system),
    (false, true, .ojd),
    (false, false, .system),
    (true, false, .system),
  ])
  func padMacOSCanServeButLeftToOJDServedByOJD(
    _ native: Bool,
    _ supported: Bool,
    _ server: ControllerServer
  ) {
    let device = PhysicalDevice(nativePassThrough: native, gameControllerSupported: supported)
    #expect(device.detectedServer == server)
  }
}
