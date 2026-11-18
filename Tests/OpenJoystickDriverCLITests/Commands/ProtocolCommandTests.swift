import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverCLI

struct ProtocolCommandTests {
  /// An application-support folder for one test: `Controllers` locates `Protocols` and `Packages`.
  private final class Support {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "ojd-protocol-\(UUID().uuidString)",
      isDirectory: true
    )

    var controllers: URL { root.appendingPathComponent("Controllers", isDirectory: true) }
    var protocols: URL { root.appendingPathComponent("Protocols", isDirectory: true) }

    var installed: [String] {
      ((try? FileManager.default.contentsOfDirectory(atPath: protocols.path)) ?? []).sorted()
    }

    /// A description of the family `name`, written under `fileName` in a staging folder.
    func description(
      _ name: String,
      fileName: String? = nil,
      edit: (inout [String: Any]) -> Void = { _ in }
    ) throws -> String {
      let source = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent(
          "Resources/Protocols/VendorFlydigi.plist"
        )
      var tree = try #require(
        try PropertyListFixture.tree(Data(contentsOf: source)) as? [String: Any]
      )
      tree["family"] = name
      tree["displayName"] = "Acme Pad"
      tree["interfaceSignatures"] = nil
      edit(&tree)
      let folder = root.appendingPathComponent("Staging/\(UUID().uuidString)", isDirectory: true)
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      let file = folder.appendingPathComponent(fileName ?? "\(name).plist")
      try PropertyListFixture.data(tree: tree).write(to: file)
      return file.path
    }

    /// A package folder that lists the description `file`.
    func makePackage(_ file: String) throws -> String {
      let folder = root.appendingPathComponent("Staging/\(UUID().uuidString)/family-pack")
      let protocols = folder.appendingPathComponent("Protocols", isDirectory: true)
      try FileManager.default.createDirectory(at: protocols, withIntermediateDirectories: true)
      let name = URL(fileURLWithPath: file).lastPathComponent
      try FileManager.default.copyItem(
        atPath: file,
        toPath: protocols.appendingPathComponent(name).path
      )
      let manifest: [String: Any] = [
        "apiVersion": OpenJoystickDriverAPI.version, "kind": ModPackageManifest.kind,
        "name": "family-pack", "version": "1.0.0", "author": "Tester",
        "requires": ["minimum": "0.6.0"], "protocols": [name],
      ]
      try PropertyListFixture.data(tree: manifest).write(
        to: folder.appendingPathComponent("mod.plist")
      )
      return folder.path
    }

    deinit { try? FileManager.default.removeItem(at: root) }
  }

  private func run(_ arguments: [String], in support: Support) async -> CLIRun {
    await ProtocolStore.$controllers.withValue(support.controllers) {
      await ModStore.$directory.withValue(support.root.appendingPathComponent("Packages")) {
        await ModStore.$runningVersion.withValue("0.6.0") {
          await CLIRun.run(arguments)
        }
      }
    }
  }

  @Test
  func validateReportsFamilyAndWritesNothing() async throws {
    let support = Support()
    let file = try support.description("VendorCliValid")

    let json = await run(["protocol", "validate", file, "--json"], in: support)
    let human = await run(["protocol", "validate", file], in: support)

    #expect(json.code == 0, "\(json.standardError)")
    #expect(try json.json()["valid"] as? Bool == true)
    #expect(try json.json()["name"] as? String == "VendorCliValid")
    #expect(try json.json()["displayName"] as? String == "Acme Pad")
    #expect(human.code == 0)
    #expect(support.installed.isEmpty)
  }

  @Test
  func validateRefusesBuiltInNameMissingLayoutAndWrongStem() async throws {
    let support = Support()
    let builtIn = try support.description("XboxGIP")
    let noLayouts = try support.description("VendorCliBare") { $0["defaults"] = nil }
    let wrongStem = try support.description("VendorCliStem", fileName: "VendorOther.plist")

    for file in [builtIn, noLayouts, wrongStem] {
      let result = await run(["protocol", "validate", file, "--json"], in: support)
      #expect(result.code == 1)
      #expect(try result.json()["valid"] as? Bool == false)
      #expect((try result.json()["code"] as? String)?.hasPrefix("E50") == true)
      #expect(result.standardError.hasPrefix("error[E50"))
    }
    let wrong = await run(["protocol", "validate", wrongStem, "--json"], in: support)
    #expect(try wrong.json()["code"] as? String == "E5003")
  }

  @Test
  func installCopiesFileToProtocolsFolderAndReplacesInstalledOne() async throws {
    let support = Support()
    let file = try support.description("VendorCliInstall")

    let first = await run(["protocol", "install", file, "--json"], in: support)
    let second = await run(["protocol", "install", file, "--json"], in: support)

    #expect(first.code == 0, "\(first.standardError)")
    #expect(try first.json()["replaced"] as? Bool == false)
    #expect(try second.json()["replaced"] as? Bool == true)
    #expect(support.installed == ["VendorCliInstall.plist"])
    #expect(
      try Data(contentsOf: support.protocols.appendingPathComponent("VendorCliInstall.plist"))
        == Data(contentsOf: URL(fileURLWithPath: file))
    )
  }

  @Test
  func installWritesNothingForDryRunOrRefusedFile() async throws {
    let support = Support()
    let file = try support.description("VendorCliDry")
    let refused = try support.description("XboxGIP")

    let dry = await run(["protocol", "install", file, "--dry-run", "--json"], in: support)
    let bad = await run(["protocol", "install", refused], in: support)

    #expect(dry.code == 0, "\(dry.standardError)")
    #expect(try dry.json()["dryRun"] as? Bool == true)
    #expect(bad.code == 1)
    #expect(support.installed.isEmpty)
  }

  @Test
  func listShowsBuiltInUserAndPackageFamiliesWithTheirSource() async throws {
    let support = Support()
    let user = try support.description("VendorCliUser")
    let packaged = try support.description("VendorCliPack")
    #expect(await run(["protocol", "install", user], in: support).code == 0)
    let folder = try support.makePackage(packaged)
    let installed = await run(["mod", "install", folder], in: support)
    #expect(installed.code == 0, "\(installed.standardError)")

    let json = await run(["protocol", "list", "--json"], in: support)
    let human = await run(["protocol", "list"], in: support)

    let items = try #require(try json.json()["items"] as? [[String: Any]])
    func entry(_ name: String) -> [String: Any]? { items.first { $0["name"] as? String == name } }
    #expect(entry("XboxGIP")?["source"] as? String == "BuiltIn")
    #expect(entry("VendorFlydigi")?["source"] as? String == "Bundled")
    #expect(entry("VendorFlydigi")?["displayName"] as? String == "Flydigi")
    #expect(entry("VendorCliUser")?["source"] as? String == "User")
    #expect(entry("VendorCliPack")?["source"] as? String == "Package")
    #expect(entry("VendorCliPack")?["package"] as? String == "family-pack")
    #expect(entry("VendorCliUser")?["displayName"] as? String == "Acme Pad")
    #expect(human.standardOutput.contains("VendorCliUser"))
  }
}
