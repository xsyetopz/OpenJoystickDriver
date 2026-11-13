import CryptoKit
import Foundation
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit

struct PortKeyInstallationStoreTests {
  private let directory = RootedDataDirectory.temporary()

  private var keyURL: URL {
    directory.fileURL(PortKeyInstallationStore.fileName, in: PortKeyInstallationStore.location)
  }

  private func bytes(_ key: SymmetricKey) -> Data { unsafe key.withUnsafeBytes { unsafe Data($0) } }

  @Test
  func missingKeyIsCreatedOncePrivatelyAndThenReused() throws {
    defer { try? FileManager.default.removeItem(at: directory.url(for: .applicationData)) }
    let store = PortKeyInstallationStore(directory: directory)

    let first = try store.load()
    let stored = try Data(contentsOf: keyURL)
    let permissions =
      try FileManager.default.attributesOfItem(atPath: keyURL.path)[
        .posixPermissions
      ] as? Int

    #expect(stored.count == 32)
    #expect(stored == bytes(first))
    #expect(permissions == 0o600)
    #expect(bytes(try store.load()) == bytes(first))
  }

  @Test
  func keyFileOfWrongSizeFailsAndStaysUnchanged() throws {
    defer { try? FileManager.default.removeItem(at: directory.url(for: .applicationData)) }
    try FileManager.default.createDirectory(
      at: keyURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    let damaged = Data(repeating: 1, count: 31)
    try damaged.write(to: keyURL)

    #expect(throws: PortKeyInstallationError.damaged(path: keyURL.path)) {
      try PortKeyInstallationStore(directory: directory).load()
    }
    #expect(try Data(contentsOf: keyURL) == damaged)
  }

  @Test
  func messageLeadsWithCodeAndItsLocalizedText() {
    let error = PortKeyInstallationError.damaged(path: "/k")
    let text = ErrorCode.damagedPortKey.localizedExplanation

    #expect(error.code == .damagedPortKey)
    #expect(!text.isEmpty && !text.hasPrefix("error."))
    #expect(error.localizedDescription == "E5006: \(text) (/k)")
  }
}
