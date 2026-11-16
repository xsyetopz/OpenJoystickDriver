public import CryptoKit
public import Foundation

/// The installation key of the port keys cannot be used.
///
/// The text names the file.
public enum PortKeyInstallationError: Error, Equatable, LocalizedError, Sendable {
  /// The key file is not 32 bytes, cannot be read, or cannot be created.
  case damaged(path: String)

  /// The code of the error, whose localized text `errorDescription` leads with.
  public var code: ErrorCode { .damagedPortKey }

  /// The error code, its localized explanation and the path of the key file.
  public var errorDescription: String? {
    switch self {
    case .damaged(let path): "\(code.rawValue): \(code.localizedExplanation) (\(path))"
    }
  }
}

/// Loads the installation key of the port keys from its private file in
/// ``DataLocation/applicationData``, through the `DataDirectory` port.
///
/// Every port key is an HMAC under this key, so a different key gives every port key a different
/// value. The file is therefore created once and never regenerated: a file that is not 32 bytes is
/// an error, and a missing file is created with 32 random bytes.
public struct PortKeyInstallationStore: Sendable {
  /// The name of the key file in ``location``.
  public static let fileName = "PortKeyInstallation.key"
  /// The location whose key file is read and created.
  public static let location = DataLocation.applicationData
  /// The length of the key in bytes.
  public static let keyLength = 32

  /// The data directory that holds the key file.
  private let directory: any DataDirectory

  /// Creates a store that reads and creates the key file through `directory`.
  public init(directory: any DataDirectory) { self.directory = directory }

  /// The key in the file, or a fresh key that this call writes to a missing file.
  ///
  /// - Throws: ``PortKeyInstallationError/damaged(path:)`` when the file cannot be read, is not
  ///   32 bytes, or cannot be created.
  public func load() throws -> SymmetricKey {
    let url = directory.fileURL(Self.fileName, in: Self.location)
    let data: Data
    do {
      data = try Data(contentsOf: url)
    } catch CocoaError.fileReadNoSuchFile {
      return try create(at: url)
    } catch {
      throw PortKeyInstallationError.damaged(path: url.path)
    }
    guard data.count == Self.keyLength else {
      throw PortKeyInstallationError.damaged(path: url.path)
    }
    return SymmetricKey(data: data)
  }

  /// Writes a random key to `url` in a private folder; the file is private from its creation.
  ///
  /// - Throws: ``PortKeyInstallationError/damaged(path:)`` when the folder or the file cannot be
  ///   created.
  private func create(at url: URL) throws -> SymmetricKey {
    let key = SymmetricKey(size: .bits256)
    let bytes = unsafe key.withUnsafeBytes { unsafe Data($0) }
    do {
      try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700]
      )
    } catch {
      throw PortKeyInstallationError.damaged(path: url.path)
    }
    guard
      FileManager.default.createFile(
        atPath: url.path,
        contents: bytes,
        attributes: [.posixPermissions: 0o600]
      )
    else { throw PortKeyInstallationError.damaged(path: url.path) }
    return key
  }
}
