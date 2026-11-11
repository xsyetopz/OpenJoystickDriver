import Foundation
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit

struct ModPackageStoreHardeningTests {
  private typealias Fixture = ModPackageFixture

  private func code(_ body: () throws -> Void) -> ErrorCode? {
    do {
      try body()
      return nil
    } catch let error as ModPackageError { return error.code } catch { return nil }
  }

  /// Every entry of the store folder, hidden ones included.
  private func entries(_ fixture: Fixture) -> [String] {
    ((try? FileManager.default.contentsOfDirectory(atPath: fixture.packages.path)) ?? []).sorted()
  }

  private func plainPackage(_ fixture: Fixture, _ name: String = "arcade-pack") throws -> URL {
    let record = try Fixture.record(0x1234, 0xabcd)
    return try fixture.makePackage(name, controllers: [record])
  }

  @Test
  func removeRefusesNamesThatLeaveTheStoreAndDeletesNothing() throws {
    try Fixture.with { fixture in
      let store = fixture.store()
      try store.install(plainPackage(fixture))
      let sentinel = fixture.root.appendingPathComponent("Controllers/mine.json")
      try FileManager.default.createDirectory(
        at: sentinel.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try Data("{}".utf8).write(to: sentinel)
      for name in ["..", ".", "a/b", "", ".hidden", "../Controllers", "arcade-pack/.."] {
        #expect(code { try store.remove(name) } == .packageNotInstalled, "\(name)")
      }
      #expect(FileManager.default.fileExists(atPath: sentinel.path))
      #expect(store.list().map(\.name) == ["arcade-pack"])
    }
  }

  @Test
  func aLinkInsideThePackageOrAsItsRootIsRefused() throws {
    try Fixture.with { fixture in
      let store = fixture.store()
      let outside = fixture.root.appendingPathComponent("outside.json")
      try Fixture.record(0x1234, 0xabcd).data.write(to: outside)

      let inside = try plainPackage(fixture)
      let link = inside.appendingPathComponent("Controllers/1234-abcd.plist")
      try FileManager.default.removeItem(at: link)
      try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
      #expect(code { try store.install(inside) } == .invalidPackageContent)
      #expect(code { try store.validate(inside) } == .invalidPackageContent)

      let real = try plainPackage(fixture, "second-pack")
      let rootLink = fixture.root.appendingPathComponent("root-link")
      try FileManager.default.createSymbolicLink(at: rootLink, withDestinationURL: real)
      #expect(code { try store.install(rootLink) } == .invalidPackageContent)

      let linkedKind = try plainPackage(fixture, "third-pack")
      let kind = linkedKind.appendingPathComponent("Controllers")
      let moved = fixture.root.appendingPathComponent("elsewhere")
      try FileManager.default.moveItem(at: kind, to: moved)
      try FileManager.default.createSymbolicLink(at: kind, withDestinationURL: moved)
      #expect(code { try store.install(linkedKind) } == .invalidPackageContent)

      #expect(entries(fixture).isEmpty)
    }
  }

  @Test
  func aFailedInstallLeavesNoStagingFolderAndAnOldPackageIntact() throws {
    try Fixture.with { fixture in
      let store = fixture.store()
      try store.install(plainPackage(fixture))
      let broken = try plainPackage(fixture)
      try Data("{".utf8).write(to: broken.appendingPathComponent("Controllers/1234-abcd.plist"))
      #expect(code { try store.install(broken, replace: true) } == .invalidPackageContent)
      #expect(entries(fixture) == ["arcade-pack"])
      #expect(store.list().first?.problem == nil)
    }
  }

  @Test
  func theInstalledCopyHasOnlyTheValidatedFiles() throws {
    try Fixture.with { fixture in
      let store = fixture.store()
      let folder = try plainPackage(fixture)
      try Data("junk".utf8).write(to: folder.appendingPathComponent(".DS_Store"))
      try Data("junk".utf8).write(to: folder.appendingPathComponent("Controllers/.hidden"))
      let installed = try store.install(folder)
      let names = FileManager.default.enumerator(atPath: installed.directory.path)?
        .compactMap { $0 as? String }
        .sorted()
      #expect(names == ["Controllers", "Controllers/1234-abcd.plist", "mod.plist"])

      let extra = try plainPackage(fixture, "other-pack")
      try Data("hello".utf8).write(to: extra.appendingPathComponent("README.md"))
      #expect(code { try store.validate(extra) } == .invalidPackageContent)
      #expect(code { try store.install(extra) } == .invalidPackageContent)
      #expect(entries(fixture) == ["arcade-pack"])
    }
  }

  @Test
  func aDanglingLinkInThePlaceOfAPackageIsHandled() throws {
    try Fixture.with { fixture in
      let store = fixture.store()
      try FileManager.default.createDirectory(
        at: fixture.packages,
        withIntermediateDirectories: true
      )
      let slot = fixture.packages.appendingPathComponent("arcade-pack")
      let missing = fixture.root.appendingPathComponent("missing")
      try FileManager.default.createSymbolicLink(at: slot, withDestinationURL: missing)
      let folder = try plainPackage(fixture)
      #expect(code { try store.install(folder) } == .packageAlreadyInstalled)
      try store.install(folder, replace: true)
      #expect(store.list().first?.problem == nil)
      #expect(!ModPackageStore.isLink(slot))

      try FileManager.default.removeItem(at: slot)
      try FileManager.default.createSymbolicLink(at: slot, withDestinationURL: missing)
      try store.remove("arcade-pack")
      #expect(entries(fixture).isEmpty)
    }
  }

  @Test
  func aPackageFileThatCannotBeReadIsContentNotARawError() throws {
    try Fixture.with { fixture in
      let store = fixture.store()
      let folder = try plainPackage(fixture)
      let file = folder.appendingPathComponent("Controllers/1234-abcd.plist")
      try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: file.path)
      defer {
        try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
      }
      #expect(code { try store.install(folder) } == .invalidPackageContent)
      #expect(entries(fixture).isEmpty)
    }
  }

  @Test
  func aFileNamedForAnotherIdentityIsContentWhenItsNameIsAllowedByTheManifest() throws {
    try Fixture.with { fixture in
      let store = fixture.store()
      let record = try Fixture.record(0x1234, 0xabcd)
      let misnamed = try fixture.makePackage(controllers: [("5678-abcd.plist", record.data)])
      #expect(code { try store.validate(misnamed) } == .invalidPackageContent)
      let persona = Fixture.persona(0x1234, 0xabcd)
      let wrong = try fixture.makePackage(virtualDevices: [("5678-abcd.plist", persona.data)])
      #expect(code { try store.validate(wrong) } == .invalidPackageContent)
      let outside = try fixture.makePackage(controllers: [("other.json", record.data)])
      #expect(code { try store.validate(outside) } == .invalidManifest)
    }
  }

  @Test
  func aFolderWhoseNameDiffersFromItsManifestIsReportedAsAProblem() throws {
    try Fixture.with { fixture in
      let store = fixture.store()
      try store.install(plainPackage(fixture))
      try FileManager.default.moveItem(
        at: fixture.packages.appendingPathComponent("arcade-pack"),
        to: fixture.packages.appendingPathComponent("renamed")
      )
      let listed = store.list()
      #expect(listed.map(\.name) == ["renamed"])
      #expect(listed.first?.manifest == nil)
      #expect(listed.first?.problem?.contains("arcade-pack") == true)
    }
  }

  @Test
  func aStoreThatCannotBeWrittenIsE4007AndKeepsTheInstalledPackage() throws {
    try Fixture.with { fixture in
      let store = fixture.store()
      try store.install(plainPackage(fixture))
      let manager = FileManager.default
      try manager.setAttributes([.posixPermissions: 0o555], ofItemAtPath: fixture.packages.path)
      defer {
        try? manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fixture.packages.path)
      }
      #expect(code { try store.remove("arcade-pack") } == .packageStoreUnwritable)
      let replacement = try plainPackage(fixture, "arcade-pack")
      #expect(code { try store.install(replacement, replace: true) } == .packageStoreUnwritable)
      #expect(store.list().map(\.name) == ["arcade-pack"])
    }
  }

  @Test
  func aTrailingNewlineFailsEveryPattern() {
    func manifest(_ name: String, _ version: String, _ file: String) -> Data {
      let document: [String: Any] = [
        "apiVersion": OpenJoystickDriverAPI.version, "kind": ModPackageManifest.kind, "name": name,
        "version": version, "author": "Tester", "requires": ["minimum": "1.0.0"],
        "controllers": [file],
      ]
      return (try? PropertyListFixture.data(tree: document)) ?? Data()
    }
    #expect((try? ModPackageManifest.parse(manifest("a", "1.0.0", "1234-abcd.plist"))) != nil)
    for data in [
      manifest("a\n", "1.0.0", "1234-abcd.plist"), manifest("a", "1.0.0\n", "1234-abcd.plist"),
      manifest("a", "1.0.0", "1234-abcd.plist\n"),
    ] {
      #expect((try? ModPackageManifest.parse(data)) == nil)
    }
  }
}
