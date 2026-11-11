import Foundation

/// Parses USB configuration descriptor blobs.
///
/// The parser accepts at most ``maxBlobSize`` bytes, the largest value of a 16-bit total length.
public enum PassiveUSBConfigurationDescriptorParser {
  /// The largest blob the parser accepts, in bytes.
  public static let maxBlobSize = 65_535
}
