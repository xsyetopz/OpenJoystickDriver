import Foundation

public enum RemappingProfileFileStore {
  public static func load(from url: URL) throws -> RemappingProfile {
    let data = try Data(contentsOf: url)
    guard data.count <= RemappingProfile.maximumEncodedBytes else {
      throw RemappingValidationError.encodedSizeExceeded(data.count)
    }
    let profile = try JSONDecoder().decode(RemappingProfile.self, from: data)
    try profile.validate()
    return profile
  }

  public static func encodedJSON(_ profile: RemappingProfile) throws -> String {
    let data = try encodedData(profile)
    guard let text = String(data: data, encoding: .utf8) else {
      throw RemappingValidationError.encodingFailed
    }
    return text
  }

  public static func write(_ profile: RemappingProfile, to url: URL) throws {
    try encodedData(profile).write(to: url, options: .atomic)
  }

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
