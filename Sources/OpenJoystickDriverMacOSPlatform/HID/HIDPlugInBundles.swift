import CoreFoundation
import Foundation
import IOKit

/// Holds the IOKit plug-in bundle of each matched HID device for the life of the process.
///
/// On macOS 27 a Sony pad or a GameSir G7 SE loads Apple's `GCHIDLib` plug-in, not `IOHIDLib`.
/// When IOHIDManager drops a removed device, `CFPlugInRemoveInstanceForFactory` releases the
/// reference that the device's instance holds on its plug-in. Releasing the last one deallocates
/// the bundle, and that deallocation can trap with `CFRelease() called with NULL`, with no OJD
/// frame on the stack. `CFBundleCreate` and `CFPlugInCreate` return the one bundle a URL has, so
/// a reference held here keeps every plug-in instance's bundle alive and out of that path.
enum HIDPlugInBundles {
  /// The directory that `IOCFPlugInTypes` paths are relative to.
  static let extensionsDirectory = URL(
    fileURLWithPath: "/System/Library/Extensions",
    isDirectory: true
  )

  /// The held bundles, by standardized plug-in path.
  ///
  /// `@unchecked Sendable` safety: `lock` guards `bundles`, and a held bundle is never released or
  /// mutated, only compared and kept.
  private final class Store: @unchecked Sendable {
    /// The lock that guards ``bundles``.
    let lock = NSLock()
    /// The held bundles, by standardized plug-in path.
    var bundles: [String: CFBundle] = [:]
  }

  /// The bundles this process holds.
  private static let store = Store()

  /// Holds the plug-in bundles that the `IOCFPlugInTypes` of `service` names.
  static func holdPlugIns(of service: io_service_t) {
    guard service != 0,
      let types = unsafe IORegistryEntryCreateCFProperty(
        service,
        kIOCFPlugInTypesKey as CFString,
        kCFAllocatorDefault,
        0
      )?.takeRetainedValue() as? [String: String]
    else { return }
    for url in plugInURLs(types) { hold(url) }
  }

  /// The plug-in bundle URLs of an `IOCFPlugInTypes` value: each path once, relative paths resolved
  /// against ``extensionsDirectory``.
  static func plugInURLs(_ types: [String: String]) -> [URL] {
    Set(types.values).sorted().map {
      $0.hasPrefix("/")
        ? URL(fileURLWithPath: $0, isDirectory: true)
        : extensionsDirectory.appendingPathComponent($0, isDirectory: true)
    }
  }

  /// Holds the bundle at `url`, once per path; returns the held bundle, or nil when there is no
  /// bundle there.
  @discardableResult
  static func hold(_ url: URL) -> CFBundle? {
    let path = url.standardizedFileURL.path
    return store.lock.withLock {
      if let bundle = store.bundles[path] { return bundle }
      guard let bundle = CFBundleCreate(kCFAllocatorDefault, url as CFURL) else { return nil }
      store.bundles[path] = bundle
      return bundle
    }
  }
}
