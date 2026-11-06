import Foundation

/// Reads and writes profile files, validating every profile on the way.
public enum RemappingProfileFileStore {
  /// Loads and validates a profile from a file.
  /// - Throws: a file read error, ``RemappingValidationError/encodedSizeExceeded(_:)``, a
  ///   `DecodingError`, or the error of ``RemappingProfile/validate()``.
  public static func load(from url: URL) throws -> RemappingProfile {
    try load(from: Data(contentsOf: url))
  }

  /// Loads and validates a profile from JSON data.
  /// - Throws: ``RemappingValidationError/encodedSizeExceeded(_:)`` for data over
  ///   ``RemappingProfile/maximumEncodedBytes``, a `DecodingError`, or the error of
  ///   ``RemappingProfile/validate()``.
  public static func load(from data: Data) throws -> RemappingProfile {
    guard data.count <= RemappingProfile.maximumEncodedBytes else {
      throw RemappingValidationError.encodedSizeExceeded(data.count)
    }
    let profile = try JSONDecoder().decode(RemappingProfile.self, from: data)
    try profile.validate()
    return profile
  }

  /// Returns the error code of a profile that ``load(from:)`` refused.
  ///
  /// It is the code of a document header problem when there is one, otherwise
  /// ``ErrorCode/invalidProfile`` for a profile that is too large, does not decode, or does not
  /// validate.
  public static func problemCode(_ error: any Error) -> ErrorCode {
    (error as? DocumentHeaderProblem)?.code ?? .invalidProfile
  }

  /// Encodes a validated profile as pretty-printed JSON with sorted keys.
  /// - Throws: the error of ``RemappingProfile/validate()``, or ``RemappingValidationError`` when
  ///   the
  ///   encoding fails or is too large.
  public static func encodedJSON(_ profile: RemappingProfile) throws -> String {
    let data = try encodedData(profile)
    guard let text = String(data: data, encoding: .utf8) else {
      throw RemappingValidationError.encodingFailed
    }
    return text
  }

  /// Writes a validated profile to a file atomically.
  /// - Throws: the errors of ``encodedJSON(_:)``, or a file write error.
  public static func write(_ profile: RemappingProfile, to url: URL) throws {
    try encodedData(profile).write(to: url, options: .atomic)
  }

  /// Validates and encodes a profile, within the size limit.
  private static func encodedData(_ profile: RemappingProfile) throws -> Data {
    try profile.validate()
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(profile)
    guard data.count <= RemappingProfile.maximumEncodedBytes else {
      throw RemappingValidationError.encodedSizeExceeded(data.count)
    }
    return data
  }
}
