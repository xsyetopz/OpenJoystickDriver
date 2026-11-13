import Foundation
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit

/// `controllers`, `patches`, and `virtualDevices` each list files of one document kind, and
/// `records` and `personas` are unknown keys.
struct ModPackageListKindTests {
  private typealias Fixture = ModPackageFixture

  private func refusal(_ body: () throws -> Void) -> ModPackageError? {
    do {
      try body()
      return nil
    } catch { return error as? ModPackageError }
  }

  private func manifest(_ changes: [String: Any?]) throws -> Data {
    var document: [String: Any] = [
      "apiVersion": OpenJoystickDriverAPI.version, "kind": ModPackageManifest.kind,
      "name": "arcade-pack", "version": "1.0.0", "author": "Tester",
      "requires": ["minimum": "0.6.0"], "controllers": ["1234-abcd.plist"],
    ]
    for (key, value) in changes { document[key] = value }
    return try PropertyListFixture.data(tree: document)
  }

  @Test(arguments: ["records", "personas"])
  func recordsAndPersonasUnknownKeys(key: String) {
    let alone = refusal {
      _ = try ModPackageManifest.parse(manifest(["controllers": nil, key: ["1234-abcd.plist"]]))
    }
    #expect(alone?.code == .invalidManifest)
    #expect(alone?.code.rawValue == "E4001")
    #expect(alone?.detail.contains(key) == true, "\(alone?.detail ?? "")")
    let beside = refusal { _ = try ModPackageManifest.parse(manifest([key: ["1234-abcd.plist"]])) }
    #expect(beside?.code == .invalidManifest)
  }

  @Test
  func eachListLoadsItsDocumentKind() throws {
    try Fixture.with { fixture in
      let record = try Fixture.record(0x1234, 0xABCD)
      let patch = try Fixture.patch(0x1234, 0xABCD, ["tuning": ["stickDeadzone": 0.3]])
      let device = Fixture.persona(0x1234, 0xABCD)
      let folder = try fixture.makePackage(
        controllers: [record],
        patches: [patch],
        virtualDevices: [device]
      )
      let manifest = try fixture.store().validate(folder)
      #expect(manifest.controllers == [record.name])
      #expect(manifest.patches == [patch.name])
      #expect(manifest.virtualDevices == [device.name])
      #expect(
        manifest.listedFiles == [
          "Controllers/\(record.name)", "Controllers/\(patch.name)",
          "VirtualDevices/\(device.name)",
        ]
      )
    }
  }

  @Test
  func aPatchIsAppliedOverTheControllerOfItsPackage() throws {
    try Fixture.with { fixture in
      let record = try Fixture.record(0x1234, 0xABCD)
      let patch = try Fixture.patch(0x1234, 0xABCD, ["tuning": ["stickDeadzone": 0.3]])
      let folder = try fixture.makePackage(controllers: [record], patches: [patch])
      try fixture.store().install(folder)
      let loaded = ControllerRecordSet.packageRecords(
        in: fixture.packages,
        runningVersion: "0.6.0"
      )
      let identity = ControllerModelID(vendorID: 0x1234, productID: 0xABCD)
      #expect(loaded.records[identity]?.tuning.stickDeadzone == 0.3)
      #expect(loaded.files.allSatisfy { $0.problem == nil })
    }
  }

  @Test
  func aControllerFileUnderPatchesIsRefused() throws {
    try Fixture.with { fixture in
      let store = fixture.store()
      let record = try Fixture.record(0x1234, 0xABCD)

      let byName = try fixture.makePackage(patches: [record])
      #expect(refusal { try store.validate(byName) }?.code == .invalidManifest)

      // The name fits a patch, but the file holds a Controller.
      let renamed = ("1234-abcd.patch.plist", record.data)
      let byKind = try fixture.makePackage(patches: [renamed])
      let error = refusal { try store.validate(byKind) }
      #expect(error?.code == .invalidPackageContent, "\(String(describing: error))")
    }
  }

  @Test
  func aPatchFileUnderControllersIsRefused() throws {
    try Fixture.with { fixture in
      let store = fixture.store()
      let patch = try Fixture.patch(0x1234, 0xABCD, ["tuning": ["stickDeadzone": 0.3]])

      let byName = try fixture.makePackage(controllers: [patch])
      #expect(refusal { try store.validate(byName) }?.code == .invalidManifest)

      // The name fits a Controller, but the file holds a ControllerPatch.
      let renamed = ("1234-abcd.plist", patch.data)
      let byKind = try fixture.makePackage(controllers: [renamed])
      let error = refusal { try store.validate(byKind) }
      #expect(error?.code == .invalidPackageContent, "\(String(describing: error))")
      #expect(error?.detail.contains("ControllerPatch") == true, "\(String(describing: error))")
      #expect(error?.detail.contains("controllers") == true, "\(String(describing: error))")
    }
  }

  @Test
  func aFolderNamedPersonasIsNotPartOfAPackage() throws {
    try Fixture.with { fixture in
      let device = Fixture.persona(0x1234, 0xABCD)
      let folder = try fixture.makePackage(virtualDevices: [device])
      try FileManager.default.moveItem(
        at: folder.appendingPathComponent("VirtualDevices"),
        to: folder.appendingPathComponent("Personas")
      )
      #expect(refusal { try fixture.store().validate(folder) }?.code == .invalidPackageContent)
    }
  }
}
