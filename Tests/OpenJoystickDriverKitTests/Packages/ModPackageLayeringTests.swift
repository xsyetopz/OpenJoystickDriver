import Foundation
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit

struct ModPackageLayeringTests {
  private typealias Fixture = ModPackageFixture

  private static let identity = ControllerModelID(vendorID: 0x1234, productID: 0xABCD)

  /// Installs the package by copying it, so the test does not depend on the version check.
  private func install(_ folder: URL, in fixture: Fixture) throws {
    try fixture.store().install(folder, replace: true)
  }

  @Test
  func aPackageRecordLayersBetweenBundledAndUser() throws {
    try Fixture.with { fixture in
      let record = try Fixture.record(0x1234, 0xABCD)
      try install(try fixture.makePackage(controllers: [record]), in: fixture)

      let set = ControllerRecordSet.load(userDirectory: fixture.controllers)
      let loaded = try #require(set.records[Self.identity])
      #expect(loaded.layer == .package)
      #expect(loaded.fieldLayers == ["modes": .package])
      #expect(loaded.file?.lastPathComponent == record.name)
      #expect(set.records.count == ControllerRecordSet.bundled.records.count + 1)
      #expect(set.problems.isEmpty)
      #expect(set.userFiles.map(\.url.lastPathComponent) == [record.name])

      try fixture.store().remove("arcade-pack")
      let removed = ControllerRecordSet.load(userDirectory: fixture.controllers)
      #expect(removed.records[Self.identity] == nil)

      try fixture.write([record], kind: "Controllers", in: fixture.root)
      let user = ControllerRecordSet.load(userDirectory: fixture.controllers)
      #expect(user.records[Self.identity]?.layer == .user)
    }
  }

  @Test
  func aUserRecordBeatsAPackageRecordAndTheLoserIsListed() throws {
    try Fixture.with { fixture in
      let record = try Fixture.record(0x1234, 0xABCD)
      try install(try fixture.makePackage(controllers: [record]), in: fixture)
      try fixture.write([record], kind: "Controllers", in: fixture.root)

      let set = ControllerRecordSet.load(userDirectory: fixture.controllers)
      #expect(set.records[Self.identity]?.layer == .user)
      let skipped = try #require(set.problems.first)
      #expect(set.problems.count == 1)
      #expect(skipped.url.path.contains("Packages/arcade-pack/Controllers"))
      #expect(skipped.problem == "replaced by your file \(record.name)")
    }
  }

  @Test
  func amongPackagesTheFirstByNameWinsAndTheLoserIsListed() throws {
    try Fixture.with { fixture in
      let record = try Fixture.record(0x1234, 0xABCD)
      // Packages may not clash when installed, so a clash made by hand stands for one that
      // appeared later, such as a package copied into the store.
      try FileManager.default.createDirectory(
        at: fixture.packages,
        withIntermediateDirectories: true
      )
      for name in ["beta-pack", "alpha-pack"] {
        let folder = try fixture.makePackage(name, controllers: [record])
        let target = fixture.packages.appendingPathComponent(name)
        try FileManager.default.copyItem(at: folder, to: target)
      }
      let set = ControllerRecordSet.load(
        userDirectory: fixture.controllers,
        localization: Localization(preferredLanguages: ["en-US"])
      )
      #expect(set.records[Self.identity]?.file?.path.contains("alpha-pack") == true)
      let skipped = try #require(set.problems.first)
      #expect(set.problems.count == 1)
      #expect(skipped.url.path.contains("beta-pack"))
      #expect(
        skipped.problem?.hasSuffix(
          "vendorID, productID: The package alpha-pack already gives this controller. "
            + "Fix: Remove one of the two packages, or change the IDs of this record."
        ) == true
      )
    }
  }

  @Test
  func aUserPatchLayersOverAPackageRecord() throws {
    try Fixture.with { fixture in
      let record = try Fixture.record(0x1234, 0xABCD)
      try install(try fixture.makePackage(controllers: [record]), in: fixture)
      let patch = try Fixture.patch(0x1234, 0xABCD, ["tuning": ["stickDeadzone": 0.3]])
      try fixture.write([patch], kind: "Controllers", in: fixture.root)

      let set = ControllerRecordSet.load(userDirectory: fixture.controllers)
      let loaded = try #require(set.records[Self.identity])
      #expect(loaded.fieldLayers == ["modes": .package, "tuning": .user])
      #expect(loaded.tuning.stickDeadzone == 0.3)
      #expect(set.problems.isEmpty)
    }
  }

  @Test
  func userPatchBeatsPackagePatchAndRemoveDeletesKey() throws {
    try Fixture.with { fixture in
      let record = try Fixture.record(0x1234, 0xABCD)
      let packaged = try Fixture.patch(0x1234, 0xABCD, ["tuning": ["stickDeadzone": 0.1]])
      try install(try fixture.makePackage(controllers: [record], patches: [packaged]), in: fixture)
      let packagedSet = ControllerRecordSet.load(userDirectory: fixture.controllers)
      #expect(packagedSet.records[Self.identity]?.tuning.stickDeadzone == 0.1)
      #expect(packagedSet.records[Self.identity]?.tuningLayers["stickDeadzone"] == .package)

      let user = try Fixture.patch(0x1234, 0xABCD, ["tuning": ["stickDeadzone": 0.3]])
      try fixture.write([user], kind: "Controllers", in: fixture.root)
      let beaten = ControllerRecordSet.load(userDirectory: fixture.controllers)
      #expect(beaten.records[Self.identity]?.tuning.stickDeadzone == 0.3)
      #expect(beaten.records[Self.identity]?.tuningLayers["stickDeadzone"] == .user)

      let deleting = try Fixture.patch(0x1234, 0xABCD, [:], remove: ["tuning"])
      try fixture.write([deleting], kind: "Controllers", in: fixture.root)
      let set = ControllerRecordSet.load(userDirectory: fixture.controllers)
      let loaded = try #require(set.records[Self.identity])
      #expect(loaded.tuning.stickDeadzone == nil)
      #expect(loaded.tuningLayers["stickDeadzone"] == nil)
      #expect(set.problems.isEmpty)
    }
  }

  @Test
  func aPackageWithAnInvalidManifestIsListedAndAppliesNothing() throws {
    try Fixture.with { fixture in
      let broken = fixture.packages.appendingPathComponent("broken-pack", isDirectory: true)
      try FileManager.default.createDirectory(at: broken, withIntermediateDirectories: true)
      try PropertyListFixture.data(json: "{}").write(
        to: broken.appendingPathComponent("mod.plist")
      )
      let set = ControllerRecordSet.load(userDirectory: fixture.controllers)
      #expect(set.records.count == ControllerRecordSet.bundled.records.count)
      #expect(set.problems.map(\.url.lastPathComponent) == ["mod.plist"])
      #expect(set.problems.first?.problem?.hasPrefix("E5001") == true)
    }
  }

  @Test
  func aPackagePersonaLayersUnderTheUserPersona() throws {
    try Fixture.with { fixture in
      let fromPackage = Fixture.persona(0x1234, 0xABCD, descriptor: "Generic")
      try install(try fixture.makePackage(virtualDevices: [fromPackage]), in: fixture)
      let store = VirtualHIDProfileOverrideStore(directory: fixture.virtualDevices)
      #expect(store.override(vendorID: 0x1234, productID: 0xABCD) == .generic)
      #expect(store.problems.isEmpty)

      let user = Fixture.persona(0x1234, 0xABCD, descriptor: "SDLCompatible")
      try fixture.write([user], kind: "VirtualDevices", in: fixture.root)
      #expect(store.override(vendorID: 0x1234, productID: 0xABCD) == .sdlCompatible)
      let skipped = try #require(store.problems.first)
      #expect(store.problems.count == 1)
      #expect(skipped.url.path.contains("Packages/arcade-pack/VirtualDevices"))
      #expect(skipped.problem == "same match as user file \(user.name)")
    }
  }

  @Test
  func amongPackagesTheFirstPersonaByNameWins() throws {
    try Fixture.with { fixture in
      try FileManager.default.createDirectory(
        at: fixture.packages,
        withIntermediateDirectories: true
      )
      let descriptors = [("beta-pack", "SDLCompatible"), ("alpha-pack", "Generic")]
      for (name, descriptor) in descriptors {
        let folder = try fixture.makePackage(
          name,
          virtualDevices: [Fixture.persona(0x1234, 0xABCD, descriptor: descriptor)]
        )
        let target = fixture.packages.appendingPathComponent(name)
        try FileManager.default.copyItem(at: folder, to: target)
      }
      let store = VirtualHIDProfileOverrideStore(directory: fixture.virtualDevices)
      #expect(store.override(vendorID: 0x1234, productID: 0xABCD) == .generic)
      let skipped = try #require(store.problems.first)
      #expect(store.problems.count == 1)
      #expect(skipped.url.path.contains("beta-pack"))
      #expect(skipped.problem == "same match as package file 1234-abcd.plist")
    }
  }

  @Test
  func settingAPackagePersonaWritesAUserFileAndLeavesThePackageFile() throws {
    try Fixture.with { fixture in
      let fromPackage = Fixture.persona(0x1234, 0xABCD, descriptor: "Generic")
      try install(try fixture.makePackage(virtualDevices: [fromPackage]), in: fixture)
      let store = VirtualHIDProfileOverrideStore(directory: fixture.virtualDevices)
      try store.set(.sdlCompatible, vendorID: 0x1234, productID: 0xABCD)
      let written = fixture.virtualDevices.appendingPathComponent(fromPackage.name)
      #expect(FileManager.default.fileExists(atPath: written.path))
      let packaged = fixture.packages.appendingPathComponent(
        "arcade-pack/VirtualDevices/\(fromPackage.name)"
      )
      #expect(try Data(contentsOf: packaged) == fromPackage.data)
      #expect(store.override(vendorID: 0x1234, productID: 0xABCD) == .sdlCompatible)

      try store.reset(vendorID: 0x1234, productID: 0xABCD)
      #expect(store.override(vendorID: 0x1234, productID: 0xABCD) == .generic)
      #expect(
        throws: VirtualHIDProfileOverrideError.keptFile(packaged.realPath)
      ) {
        try store.reset(vendorID: 0x1234, productID: 0xABCD)
      }
      #expect(try store.resetAll().isEmpty)
      #expect(FileManager.default.fileExists(atPath: packaged.path))
    }
  }
}
