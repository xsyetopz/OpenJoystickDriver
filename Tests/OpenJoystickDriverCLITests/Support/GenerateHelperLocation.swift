import Foundation

/// Where the tests find the executable that `ojd generate` starts as its helper process.
enum GenerateHelperLocation {
  private final class Anchor {}

  /// The `OpenJoystickDriver` executable that `swift build` puts beside the test bundle.
  static var executable: URL {
    Bundle(for: Anchor.self).bundleURL.deletingLastPathComponent()
      .appendingPathComponent("OpenJoystickDriver")
  }
}
