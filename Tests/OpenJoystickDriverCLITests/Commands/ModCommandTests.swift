import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverCLI

struct ModCommandTests {
  /// An application-support folder for one test: the `Packages` store and a staging area.
  private final class Support {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "ojd-mod-\(UUID().uuidString)",
      isDirectory: true
    )

    var packages: URL { root.appendingPathComponent("Packages", isDirectory: true) }

    var installed: [String] {
      ((try? FileManager.default.contentsOfDirectory(atPath: packages.path)) ?? []).sorted()
    }

    /// A package folder that holds one Controller record for a model the catalog lacks.
    func makePackage(
      _ name: String = "arcade-pack",
      productID: Int = 1,
      requires: [String: Any] = ["minimum": "0.6.0"]
    ) throws -> String {
      let folder = root.appendingPathComponent("Staging/\(UUID().uuidString)/\(name)")
      let controllers = folder.appendingPathComponent("Controllers", isDirectory: true)
      try FileManager.default.createDirectory(at: controllers, withIntermediateDirectories: true)
      let file = unsafe String(format: "fff1-%04x.plist", productID)
      let record: [String: Any] = [
        "apiVersion": OpenJoystickDriverAPI.version, "kind": "Controller",
        "vendorID": 0xFFF1,
        "productID": productID, "modes": [["id": "default", "protocol": ["family": "XboxGIP"]]],
      ]
      try PropertyListFixture.data(tree: record).write(
        to: controllers.appendingPathComponent(file)
      )
      let manifest: [String: Any] = [
        "apiVersion": OpenJoystickDriverAPI.version, "kind": ModPackageManifest.kind, "name": name,
        "version": "1.2.3", "author": "Tester", "requires": requires, "controllers": [file],
      ]
      try PropertyListFixture.data(tree: manifest).write(
        to: folder.appendingPathComponent("mod.plist")
      )
      return folder.path
    }

    deinit { try? FileManager.default.removeItem(at: root) }
  }

  private func run(
    _ arguments: [String],
    in support: Support,
    version: String = "0.6.0"
  ) async -> CLIRun {
    await ModStore.$directory.withValue(support.packages) {
      await ModStore.$runningVersion.withValue(version) {
        await CLIRun.run(["mod"] + arguments)
      }
    }
  }

  @Test
  func validateReportsThePackageAndWritesNothing() async throws {
    let support = Support()
    let folder = try support.makePackage()

    let json = await run(["validate", folder, "--json"], in: support)
    let human = await run(["validate", folder], in: support)

    #expect(json.code == 0, "\(json.standardError)")
    let result = try json.json()
    #expect(result["valid"] as? Bool == true)
    #expect(result["name"] as? String == "arcade-pack")
    #expect(result["files"] as? [String] == ["Controllers/fff1-0001.plist"])
    #expect(human.code == 0)
    #expect(support.installed.isEmpty)
  }

  @Test
  func aRefusedPackageExitsOneWithItsCode() async throws {
    let support = Support()
    let empty = support.root.appendingPathComponent("empty").path
    try FileManager.default.createDirectory(atPath: empty, withIntermediateDirectories: true)
    let excluded = try support.makePackage(requires: ["minimum": "9.0.0"])

    let json = await run(["validate", empty, "--json"], in: support)
    let requires = await run(["validate", excluded, "--json"], in: support)

    #expect(json.code == 1)
    #expect(try json.json()["valid"] as? Bool == false)
    #expect((try json.json()["code"] as? String)?.hasPrefix("E40") == true)
    #expect(json.standardError.hasPrefix("error[E40"))
    #expect(requires.code == 1)
    #expect(try requires.json()["code"] as? String == "E4002")
    #expect(requires.standardError.hasPrefix("error[E4002]: "))
  }

  @Test
  func aManifestWithAnUnsupportedAPIVersionIsRefusedWithE5001() async throws {
    let support = Support()
    let folder = try support.makePackage()
    let manifestURL = URL(fileURLWithPath: folder).appendingPathComponent("mod.plist")
    var manifest = try PropertyListFixture.dictionary(at: manifestURL)
    manifest["apiVersion"] = "unsupported.example/v9"
    try PropertyListFixture.data(tree: manifest).write(to: manifestURL)

    let json = await run(["validate", folder, "--json"], in: support)
    let install = await run(["install", folder], in: support)

    #expect(json.code == 1)
    #expect(try json.json()["valid"] as? Bool == false)
    #expect(try json.json()["code"] as? String == "E5001")
    let problem = try #require(try json.json()["problem"] as? String)
    #expect(problem.contains("mod.plist"))
    #expect(problem.contains("unsupported.example/v9"))
    #expect(problem.contains(OpenJoystickDriverAPI.version))
    #expect(json.standardError.hasPrefix("error[E5001]: "))
    #expect(install.code == 1)
    #expect(install.standardError.hasPrefix("error[E5001]: "))
    #expect(support.installed.isEmpty)
  }

  @Test
  func installListAndRemoveRoundTrip() async throws {
    let support = Support()
    let folder = try support.makePackage()

    let install = await run(["install", folder, "--json"], in: support)
    let list = await run(["list", "--json"], in: support)
    let remove = await run(["remove", "arcade-pack", "--force", "--json"], in: support)

    #expect(install.code == 0, "\(install.standardError)")
    #expect(try install.json()["replaced"] as? Bool == false)
    #expect(try install.json()["dryRun"] as? Bool == false)
    let items = try #require(try list.json()["items"] as? [[String: Any]])
    #expect(items.count == 1)
    #expect(items.first?["name"] as? String == "arcade-pack")
    #expect(items.first?["version"] as? String == "1.2.3")
    #expect(items.first?["author"] as? String == "Tester")
    #expect(items.first?["files"] as? [String] == ["Controllers/fff1-0001.plist"])
    #expect(items.first?["problem"] == nil)
    #expect(remove.code == 0, "\(remove.standardError)")
    #expect(support.installed.isEmpty)
  }

  @Test
  func installRefusesAnExistingNameUnlessForced() async throws {
    let support = Support()
    let folder = try support.makePackage()
    _ = await run(["install", folder], in: support)

    let again = await run(["install", folder, "--json"], in: support)
    let forced = await run(["install", folder, "--force", "--json"], in: support)

    #expect(again.code == 1)
    #expect(again.standardError.hasPrefix("error[E4005]: "))
    #expect(forced.code == 0, "\(forced.standardError)")
    #expect(try forced.json()["replaced"] as? Bool == true)
    #expect(support.installed == ["arcade-pack"])
  }

  @Test
  func forceNeverOverridesRequiresOrAClash() async throws {
    let support = Support()
    let first = try support.makePackage("first-pack")
    let rival = try support.makePackage("rival-pack")
    let excluded = try support.makePackage(
      "future-pack",
      productID: 2,
      requires: ["minimum": "9.0.0"]
    )
    _ = await run(["install", first], in: support)

    let clash = await run(["install", rival, "--force"], in: support)
    let requires = await run(["install", excluded, "--force"], in: support)

    #expect(clash.code == 1)
    #expect(clash.standardError.hasPrefix("error[E4004]: "))
    #expect(requires.code == 1)
    #expect(requires.standardError.hasPrefix("error[E4002]: "))
    #expect(support.installed == ["first-pack"])
  }

  @Test
  func dryRunChangesNothing() async throws {
    let support = Support()
    let folder = try support.makePackage()

    let dry = await run(["install", folder, "--dry-run", "--json"], in: support)
    #expect(dry.code == 0, "\(dry.standardError)")
    #expect(try dry.json()["dryRun"] as? Bool == true)
    #expect(support.installed.isEmpty)

    _ = await run(["install", folder], in: support)
    let existing = await run(["install", folder, "--dry-run"], in: support)
    let remove = await run(["remove", "arcade-pack", "--dry-run", "--json"], in: support)

    #expect(existing.code == 1)
    #expect(remove.code == 0, "\(remove.standardError)")
    #expect(try remove.details()["dryRun"] as? Bool == true)
    #expect(support.installed == ["arcade-pack"])
  }

  @Test
  func removeOfAMissingPackageIsE4006AndTouchesOnlyItsFolder() async throws {
    let support = Support()
    _ = await run(["install", try support.makePackage()], in: support)

    let missing = await run(["remove", "other-pack", "--force"], in: support)
    let dryMissing = await run(["remove", "other-pack", "--dry-run"], in: support)
    let escaping = await run(["remove", "../Packages", "--force"], in: support)

    for result in [missing, dryMissing, escaping] {
      #expect(result.code == 1)
      #expect(result.standardError.hasPrefix("error[E4006]: "))
    }
    #expect(support.installed == ["arcade-pack"])
  }

  @Test
  func listNamesAPackageThatRequiresExcludesWithItsE4002Reason() async throws {
    let support = Support()
    _ = await run(["install", try support.makePackage()], in: support)

    let list = await run(["list", "--json"], in: support, version: "0.5.0")

    let items = try #require(try list.json()["items"] as? [[String: Any]])
    #expect((items.first?["problem"] as? String)?.contains("E4002") == true)
    #expect(items.first?["name"] as? String == "arcade-pack")
  }
}
