import Foundation
import OpenJoystickDriverKit

extension RemappingProfileLibrary {
  /// The URL of the file that holds when each profile was last activated.
  nonisolated var lastUsedURL: URL {
    directory.appendingPathComponent(Self.lastUsedFileName, isDirectory: false)
  }

  /// When each profile of `known` was last activated, in seconds since 1970.
  ///
  /// A missing or damaged file gives an empty list, because the list only orders the profiles.
  func lastUsed(among known: [RemappingProfile]) -> [UUID: Double] {
    let ids = Set(known.map(\.id))
    return storedLastUsed().reduce(into: [:]) { result, entry in
      if let id = UUID(uuidString: entry.key), ids.contains(id) { result[id] = entry.value }
    }
  }

  /// Records that the profile `id` is activated now.
  ///
  /// A write that fails is dropped: the time is not worth failing an activation for.
  func recordUse(of id: UUID, among known: [RemappingProfile]) {
    var stored = lastUsed(among: known).reduce(into: [String: Double]()) {
      $0[$1.key.uuidString] = $1.value
    }
    stored[id.uuidString] = clock().timeIntervalSince1970
    do {
      try Self.createPrivateDirectory(directory)
      try Self.writePrivate(DocumentCoder.encode(stored), to: lastUsedURL)
    } catch { return }
  }

  /// The entries of the file, or none when it is missing or cannot be read.
  private func storedLastUsed() -> [String: Double] {
    guard let data = try? Data(contentsOf: lastUsedURL),
      data.count <= Self.maximumEncodedBytes
    else { return [:] }
    return (try? DocumentCoder.decode([String: Double].self, from: data, file: lastUsedURL.path))
      ?? [:]
  }
}
