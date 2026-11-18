import CoreFoundation
import Foundation
import Testing

@testable import OpenJoystickDriverMacOSPlatform

struct HIDPlugInBundlesTests {
  private static let ioHIDLib = "IOHIDFamily.kext/Contents/PlugIns/IOHIDLib.plugin"

  /// A HID service names one plug-in for several types; it is held once, at its path under the
  /// extensions directory.
  @Test
  func plugInTypesResolveToEachBundleOnce() {
    let types = [
      "FA12FA38-6F1A-11D4-BA0C-0005028F18D5": Self.ioHIDLib,
      "7DDEECA8-A7B4-11DA-8A0E-0014519758EF": Self.ioHIDLib,
      "E071DA1B-55D5-4D29-B6BE-D47438269B7B": "/Library/Custom.plugin",
    ]

    let paths = HIDPlugInBundles.plugInURLs(types).map(\.path)

    #expect(
      paths == [
        "/Library/Custom.plugin",
        "/System/Library/Extensions/IOHIDFamily.kext/Contents/PlugIns/IOHIDLib.plugin",
      ]
    )
  }

  /// The held bundle is the one `CFPlugInCreate` gives IOKit, so the hold keeps that plug-in from
  /// being deallocated when its last device instance goes.
  @Test
  func heldBundleIsThePlugInIOKitCreates() throws {
    let url = HIDPlugInBundles.extensionsDirectory.appendingPathComponent(Self.ioHIDLib)

    let held = try #require(HIDPlugInBundles.hold(url))
    let again = try #require(HIDPlugInBundles.hold(url))
    let plugIn = try #require(CFPlugInCreate(kCFAllocatorDefault, url as CFURL))

    #expect(held === again)
    #expect(held === plugIn)
  }

  @Test
  func missingBundleIsNotHeld() {
    let url = URL(fileURLWithPath: "/nonexistent/OJD.plugin", isDirectory: true)

    #expect(HIDPlugInBundles.hold(url) == nil)
  }
}
