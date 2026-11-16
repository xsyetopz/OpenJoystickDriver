import Foundation
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit

struct ModPackageStoreTests {
  private typealias Fixture = ModPackageFixture

  /// The error code that `body` throws, or nil when it does not throw a ``ModPackageError``.
  private func code(_ body: () throws -> Void) -> ErrorCode? {
    do {
      try body()
      return nil
    } catch let error as ModPackageError { return error.code } catch { return nil }
  }

  @Test
  func errorCodesBelongToModDomain() {
    let codes: [ErrorCode] = [
      .invalidManifest, .requiresExcludesVersion, .invalidPackageContent, .packageClash,
      .packageAlreadyInstalled, .packageNotInstalled,
    ]
    #expect(codes.allSatisfy { $0.domain == .mod && $0.rawValue.hasPrefix("E4") })
    #expect(codes.allSatisfy { !$0.localizedExplanation.isEmpty })
  }

  @Test
  func validPackageInstallsListsAndRemoves() throws {
    try Fixture.with { fixture in
      let folder = try fixture.makePackage(
        controllers: [try Fixture.record(0x1234, 0xABCD)],
        virtualDevices: [Fixture.persona(0x1234, 0xABCD)],
        profiles: [try Fixture.profile(name: "Arcade")]
      )
      let store = fixture.store()
      #expect(store.list().isEmpty)
      let installed = try store.install(folder)
      #expect(installed.directory.lastPathComponent == "arcade-pack")
      #expect(store.list().map(\.name) == ["arcade-pack"])
      #expect(store.list().first?.manifest?.version == "1.0.0")
      let installedRecord = installed.directory.appendingPathComponent(
        "Controllers/1234-abcd.plist"
      )
      #expect(FileManager.default.fileExists(atPath: installedRecord.path))
      try store.remove("arcade-pack")
      #expect(store.list().isEmpty)
      #expect(code { try store.remove("arcade-pack") } == .packageNotInstalled)
    }
  }

  @Test
  func installingNameThatIsInstalledNeedsReplace() throws {
    try Fixture.with { fixture in
      let store = fixture.store()
      try store.install(try fixture.makePackage(controllers: [try Fixture.record(0x1234, 0xABCD)]))
      let second = try fixture.makePackage(
        version: "2.0.0",
        controllers: [try Fixture.record(0x1234, 0xABCE)]
      )
      #expect(code { try store.install(second) } == .packageAlreadyInstalled)
      #expect(store.list().first?.manifest?.version == "1.0.0")
      try store.install(second, replace: true)
      let installed = try #require(store.list().first)
      #expect(installed.manifest?.version == "2.0.0")
      #expect(installed.manifest?.controllers == ["1234-abce.plist"])
      let entries = try FileManager.default.contentsOfDirectory(atPath: fixture.packages.path)
      #expect(entries == ["arcade-pack"])
    }
  }

  @Test
  func requiresIsCheckedWithPrereleaseOrderingAndForceNeverOverridesIt() throws {
    try Fixture.with { fixture in
      let folder = try fixture.makePackage(
        requires: ["minimum": "0.6.0-alpha.2", "below": "0.7.0"],
        controllers: [try Fixture.record(0x1234, 0xABCD)]
      )
      func refusal(_ version: String) -> ErrorCode? {
        code { try fixture.store(running: version).validate(folder) }
      }
      #expect(refusal("0.6.0-alpha.1") == .requiresExcludesVersion)
      #expect(refusal("0.6.0-alpha.2") == nil)
      #expect(refusal("0.6.0") == nil)
      #expect(refusal("0.7.0-rc.1") == nil)
      #expect(refusal("0.7.0") == .requiresExcludesVersion)
      #expect(refusal("unknown") == .requiresExcludesVersion)
      let refusing = fixture.store(running: "0.5.0")
      #expect(code { try refusing.install(folder, replace: true) } == .requiresExcludesVersion)
      #expect(refusing.list().isEmpty)
    }
  }

  @Test
  func badManifestIsRefused() throws {
    try Fixture.with { fixture in
      let record = try Fixture.record(0x1234, 0xABCD)
      let store = fixture.store()
      for overrides: [String: Any] in [
        ["name": "Arcade Pack"], ["version": "1.0"], ["version": "v1.0.0"], ["author": ""],
        ["requires": ["minimum": "latest"]], ["requires": ["below": "1.0.0"]],
        ["requires": ["minimum": "0.6.0", "extra": 1]], ["extra": true],
        ["kind": "Controller"],
        ["$schema": "https://example.com/mod-package.schema.json"],
        ["controllers": ["../1234-abcd.plist"]],
        ["controllers": ["1234-abcd.plist", "1234-abcd.plist"]],
        ["controllers": []],
      ] {
        let folder = try fixture.makePackage(controllers: [record], manifest: overrides)
        #expect(code { try store.validate(folder) } == .invalidManifest, "\(overrides)")
      }
      let unsupportedVersion = try fixture.makePackage(
        controllers: [record],
        manifest: ["apiVersion": "unsupported.example/v9"]
      )
      #expect(code { try store.validate(unsupportedVersion) } == .unsupportedAPIVersion)
      let noManifest = try fixture.makePackage(controllers: [record])
      try FileManager.default.removeItem(at: noManifest.appendingPathComponent("mod.plist"))
      #expect(code { try store.validate(noManifest) } == .invalidManifest)
      let empty = try fixture.makePackage()
      #expect(code { try store.validate(empty) } == .invalidManifest)
    }
  }

  @Test
  func missingUnlistedAndInvalidFilesAreRefused() throws {
    try Fixture.with { fixture in
      let store = fixture.store()
      let record = try Fixture.record(0x1234, 0xABCD)
      let missing = try fixture.makePackage(controllers: [record])
      try FileManager.default.removeItem(
        at: missing.appendingPathComponent("Controllers/\(record.name)")
      )
      #expect(code { try store.validate(missing) } == .invalidPackageContent)

      let unlisted = try fixture.makePackage(controllers: [record])
      try fixture.write([Fixture.persona(0x1234, 0xABCD)], kind: "VirtualDevices", in: unlisted)
      #expect(code { try store.validate(unlisted) } == .invalidPackageContent)

      let brokenRecord = try fixture.makePackage(controllers: [(record.name, Data("{".utf8))])
      #expect(code { try store.validate(brokenRecord) } == .invalidPackageContent)
      let bundled = try fixture.makePackage(controllers: [try Fixture.record(0x366C, 0x0005)])
      #expect(code { try store.validate(bundled) } == .invalidPackageContent)
      let misnamed = try fixture.makePackage(controllers: [("other.plist", record.data)])
      #expect(code { try store.validate(misnamed) } == .invalidManifest)

      let persona = Fixture.persona(0x1234, 0xABCD)
      let brokenPersona = try fixture.makePackage(virtualDevices: [(persona.name, Data("[]".utf8))])
      #expect(code { try store.validate(brokenPersona) } == .invalidPackageContent)
      let wrongPersona = try fixture.makePackage(virtualDevices: [("x.plist", persona.data)])
      #expect(code { try store.validate(wrongPersona) } == .invalidManifest)
      let brokenProfile = try fixture.makePackage(profiles: [
        ("p.plist", PropertyListFixture.bytes(json: "{}"))
      ])
      #expect(code { try store.validate(brokenProfile) } == .unsupportedAPIVersion)
      #expect(store.list().isEmpty)
    }
  }

  @Test
  func clashWithUserOrAnotherPackageIsRefusedAndForceDoesNotOverrideIt() throws {
    try Fixture.with { fixture in
      let store = fixture.store()
      let record = try Fixture.record(0x1234, 0xABCD)
      let persona = Fixture.persona(0x1234, 0xABCD)
      let profile = try Fixture.profile(name: "Arcade")
      let id = UUID()

      try fixture.write([record], kind: "Controllers", in: fixture.root)
      let clashing = try fixture.makePackage(controllers: [record])
      #expect(code { try store.install(clashing, replace: true) } == .packageClash)
      try FileManager.default.removeItem(at: fixture.controllers)

      try fixture.write([("renamed.plist", persona.data)], kind: "VirtualDevices", in: fixture.root)
      let samePersona = try fixture.makePackage(virtualDevices: [persona])
      #expect(code { try store.validate(samePersona) } == .packageClash)
      try FileManager.default.removeItem(at: fixture.virtualDevices)

      let mine = try Fixture.profile(id: id, name: "Mine")
      try fixture.write([mine], kind: "Profiles", in: fixture.root)
      let sameID = try Fixture.profile(id: id, name: "Theirs")
      let byID = try fixture.makePackage(profiles: [("a.plist", sameID.data)])
      #expect(code { try store.validate(byID) } == .packageClash)
      let sameName = try Fixture.profile(name: "mine")
      let byName = try fixture.makePackage(profiles: [("a.plist", sameName.data)])
      #expect(code { try store.validate(byName) } == .packageClash)
      let twice = try fixture.makePackage(profiles: [
        ("a.plist", profile.data), ("b.plist", profile.data),
      ])
      #expect(code { try store.validate(twice) } == .packageClash)
      try FileManager.default.removeItem(at: fixture.profiles)

      try store.install(
        try fixture.makePackage(
          "first",
          controllers: [record],
          virtualDevices: [persona],
          profiles: [profile]
        )
      )
      for other in [
        try fixture.makePackage("second", controllers: [record]),
        try fixture.makePackage("second", virtualDevices: [persona]),
        try fixture.makePackage("second", profiles: [profile]),
      ] {
        #expect(code { try store.install(other, replace: true) } == .packageClash)
      }
      #expect(store.list().map(\.name) == ["first"])
      // The package that is replaced is not a clash with itself.
      try store.install(try fixture.makePackage("first", controllers: [record]), replace: true)
    }
  }
}
