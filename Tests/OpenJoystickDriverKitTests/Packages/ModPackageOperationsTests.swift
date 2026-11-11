import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct ModPackageOperationsTests {
  private typealias Fixture = ModPackageFixture

  @Test
  func installListAndRemoveRunTheCodeOfOjdMod() throws {
    try Fixture.with { fixture in
      let store = fixture.store()
      let folder = try fixture.makePackage(controllers: [try Fixture.record(0x1234, 0xABCD)])

      let dry = try store.installPackage(from: folder, dryRun: true)
      #expect(dry.manifest.name == "arcade-pack")
      #expect(!dry.replaced)
      #expect(store.entries().isEmpty)

      let installed = try store.installPackage(from: folder)
      #expect(installed.destination.lastPathComponent == "arcade-pack")
      let entry = try #require(store.entries().first)
      #expect(entry.name == "arcade-pack")
      #expect(entry.version == "1.0.0")
      #expect(entry.files == ["Controllers/1234-abcd.plist"])
      #expect(entry.problem == nil)

      try store.removePackage(named: "arcade-pack", dryRun: true)
      #expect(store.entries().count == 1)
      try store.removePackage(named: "arcade-pack")
      #expect(store.entries().isEmpty)
    }
  }

  @Test
  func anInstalledNameNeedsReplaceAndTheRefusalCarriesTheCodeOfOjd() throws {
    try Fixture.with { fixture in
      let store = fixture.store()
      let folder = try fixture.makePackage(controllers: [try Fixture.record(0x1234, 0xABCD)])
      try store.installPackage(from: folder)

      let refused = #expect(throws: CodedFailure.self) { try store.installPackage(from: folder) }
      #expect(refused?.id == .packageAlreadyInstalled)
      let replaced = try store.installPackage(from: folder, replace: true)
      #expect(replaced.replaced)
    }
  }

  @Test
  func aRefusedPackageAndAMissingNameReportTheirCodes() throws {
    try Fixture.with { fixture in
      let store = fixture.store(running: "0.5.0")
      let folder = try fixture.makePackage(controllers: [try Fixture.record(0x1234, 0xABCD)])
      let refused = #expect(throws: CodedFailure.self) { try store.installPackage(from: folder) }
      #expect(refused?.id == .requiresExcludesVersion)
      #expect(refused?.message.contains(folder.path) == true)

      for name in ["", ".hidden", "a/b", "absent"] {
        let missing = #expect(throws: CodedFailure.self) {
          try store.removePackage(named: name)
        }
        #expect(missing?.id == .packageNotInstalled, "\(name)")
      }
    }
  }
}
