import IOKit.hid
import Testing

@testable import OpenJoystickDriverKit

struct StreamConstructionTests {
  /// Constructing a stream must not enumerate attached devices. Each enumerated device loads the
  /// IOHID plug-in, and parallel tests that build many `DeviceManager`s crashed in CoreFoundation's
  /// plug-in teardown when those devices were released. On a host without a matching device the
  /// check passes either way.
  @Test
  func constructionDoesNotEnumerateDevices() {
    let stream = HIDDeviceStream()
    #expect(stream.manager == nil)
  }

  /// Matching is deferred, not dropped: each `deviceEvents()` applies it to a new manager, or the
  /// stream would never see a controller. A restarted stream, as after system sleep, never reuses
  /// the manager of the stream it replaced. Holds on a host without a matching device.
  @Test
  @MainActor
  func eachDeviceEventsUsesANewManager() throws {
    let stream = HIDDeviceStream()
    let first = stream.deviceEvents()
    let firstManager = try #require(stream.manager)
    stream.cleanup()
    #expect(stream.manager == nil)
    let second = stream.deviceEvents()
    // Unschedules the manager and finishes the stream, so no callbacks outlive the test.
    defer { stream.cleanup() }
    withExtendedLifetime((first, second)) {
      #expect(stream.manager.map { $0 !== firstManager } == true)
    }
  }
}
