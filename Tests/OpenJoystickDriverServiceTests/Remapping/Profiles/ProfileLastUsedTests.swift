import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverService

struct ProfileLastUsedTests {
  private final class Clock: @unchecked Sendable {
    private let lock = NSLock()
    private var seconds: Double

    init(_ seconds: Double) { self.seconds = seconds }

    func advance(to value: Double) { lock.withLock { seconds = value } }

    var now: Date { lock.withLock { Date(timeIntervalSince1970: seconds) } }
  }

  private static func profile(_ name: String, productID: UInt16 = 654) -> RemappingProfile {
    RemappingProfile(
      name: name,
      device: RemappingDeviceScope(vendorID: 1118, productID: productID),
      applicationScope: .global,
      bindings: []
    )
  }

  private static func withLibrary(
    clock: Clock,
    _ body: @Sendable (RemappingProfileLibrary, URL) async throws -> Void
  ) async throws {
    let directory = MacOSDataDirectory().url(for: .temporary).appendingPathComponent(
      UUID().uuidString,
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try await body(RemappingProfileLibrary(directory: directory) { clock.now }, directory)
  }

  @Test
  func aNeverActivatedProfileHasNoLastUse() async throws {
    try await Self.withLibrary(clock: Clock(100)) { library, _ in
      try await library.create(Self.profile("Idle"))
      #expect(try await library.snapshot().lastUsed.isEmpty)
    }
  }

  @Test
  func activatingAProfileRecordsTheTime() async throws {
    let clock = Clock(1_000)
    try await Self.withLibrary(clock: clock) { library, _ in
      let first = Self.profile("First")
      let second = Self.profile("Second", productID: 655)
      try await library.create(first)
      try await library.create(second)
      try await library.activate(profileID: first.id)
      clock.advance(to: 2_000)
      try await library.activate(profileID: second.id)
      clock.advance(to: 3_000)
      try await library.activate(profileID: first.id)

      let lastUsed = try await library.snapshot().lastUsed
      #expect(lastUsed[first.id] == 3_000)
      #expect(lastUsed[second.id] == 2_000)
    }
  }

  @Test
  func theLastUseSurvivesANewLibraryInstance() async throws {
    let clock = Clock(1_000)
    try await Self.withLibrary(clock: clock) { library, directory in
      let profile = Self.profile("Kept")
      try await library.create(profile)
      try await library.activate(profileID: profile.id)

      let restored = RemappingProfileLibrary(directory: directory) { clock.now }
      #expect(try await restored.snapshot().lastUsed[profile.id] == 1_000)
    }
  }

  @Test
  func deactivatingAProfileKeepsItsLastUse() async throws {
    try await Self.withLibrary(clock: Clock(1_000)) { library, _ in
      let profile = Self.profile("Kept")
      try await library.create(profile)
      try await library.activate(profileID: profile.id)
      try await library.deactivate(profileID: profile.id)
      #expect(try await library.snapshot().lastUsed[profile.id] == 1_000)
    }
  }

  @Test
  func aRefusedActivationRecordsNothing() async throws {
    try await Self.withLibrary(clock: Clock(1_000)) { library, directory in
      let missing = UUID()
      await #expect(throws: RemappingProfileLibraryError.profileNotFound(missing)) {
        try await library.activate(profileID: missing)
      }
      let lastUsed = try await library.snapshot().lastUsed
      #expect(lastUsed.isEmpty)
      #expect(
        !FileManager.default.fileExists(
          atPath: directory.appendingPathComponent("LastUsed.plist").path
        )
      )
    }
  }

  @Test
  func aDeletedProfileLeavesTheLastUseList() async throws {
    try await Self.withLibrary(clock: Clock(1_000)) { library, _ in
      let profile = Self.profile("Gone")
      try await library.create(profile)
      try await library.activate(profileID: profile.id)
      try await library.delete(id: profile.id)
      #expect(try await library.snapshot().lastUsed.isEmpty)
    }
  }

  @Test
  func aDamagedLastUseFileDoesNotBlockActivationAndIsReplaced() async throws {
    try await Self.withLibrary(clock: Clock(1_000)) { library, directory in
      let profile = Self.profile("Resilient")
      try await library.create(profile)
      let file = directory.appendingPathComponent("LastUsed.plist")
      try Data("not a plist".utf8).write(to: file)
      #expect(try await library.snapshot().lastUsed.isEmpty)

      try await library.activate(profileID: profile.id)

      #expect(try await library.snapshot().lastUsed[profile.id] == 1_000)
    }
  }

  @Test
  func theLastUseFileHoldsOnlyTextAndNumbers() async throws {
    try await Self.withLibrary(clock: Clock(1_000)) { library, directory in
      let profile = Self.profile("Plain")
      try await library.create(profile)
      try await library.activate(profileID: profile.id)

      let data = try Data(contentsOf: directory.appendingPathComponent("LastUsed.plist"))
      let tree = try #require(
        try unsafe PropertyListSerialization.propertyList(from: data, options: 0, format: nil)
          as? [String: Any]
      )
      #expect(tree[profile.id.uuidString] as? Double == 1_000)
      let text = try #require(String(bytes: data, encoding: .utf8))
      #expect(!text.contains("<date>") && !text.contains("<data>"))
    }
  }
}
