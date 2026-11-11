import Foundation
import Testing

@testable import OpenJoystickDriverKit

/// A package holds documents only: loading it never evaluates a script.
@Suite
struct ModPackageScriptTests {
  private typealias Fixture = ModPackageFixture

  private func code(_ body: () throws -> Void) -> ErrorCode? {
    do {
      try body()
      return nil
    } catch let error as ModPackageError { return error.code } catch { return nil }
  }

  @Test(arguments: ["generate.js", "Controllers/generate.js"])
  func aScriptInAPackageIsSkippedAndNeverRun(path: String) throws {
    try Fixture.with { fixture in
      let store = fixture.store()
      let record = try Fixture.record(0x1234, 0xABCD)
      let folder = try fixture.makePackage(controllers: [record])
      let marker = fixture.root.appendingPathComponent("ran")
      try Data("throw new Error('evaluated');".utf8).write(
        to: folder.appendingPathComponent(path)
      )

      _ = try store.validate(folder)
      let installed = try store.install(folder)

      #expect(store.list().map(\.problem) == [nil])
      let names = FileManager.default.enumerator(atPath: installed.directory.path)?
        .compactMap { $0 as? String }.sorted()
      #expect(names == ["Controllers", "Controllers/1234-abcd.plist", "mod.plist"])
      #expect(!FileManager.default.fileExists(atPath: marker.path))
    }
  }

  @Test
  func aFileThatIsNotAScriptIsStillRefused() throws {
    try Fixture.with { fixture in
      let store = fixture.store()
      let folder = try fixture.makePackage(controllers: [try Fixture.record(0x1234, 0xABCD)])
      try Data("x".utf8).write(to: folder.appendingPathComponent("tool.py"))

      #expect(code { try store.validate(folder) } == .invalidPackageContent)
    }
  }

  @Test
  func aScriptBesideAnInstalledPackageDoesNotChangeItsLoading() throws {
    try Fixture.with { fixture in
      let store = fixture.store()
      let folder = try fixture.makePackage(controllers: [try Fixture.record(0x1234, 0xABCD)])
      let installed = try store.install(folder)
      let before = store.list()

      try Data("while (true) {}".utf8).write(
        to: installed.directory.appendingPathComponent("Controllers/loop.js")
      )

      #expect(store.list() == before)
      #expect(store.list().first?.problem == nil)
    }
  }

  @Test(arguments: ["Sources/OpenJoystickDriverKit", "Sources/OpenJoystickDriverService"])
  func noPackageLoadingSourceImportsAScriptEngine(folder: String) throws {
    var root = URL(fileURLWithPath: #filePath)
    for _ in 0..<4 { root.deleteLastPathComponent() }
    let enumerator = try #require(
      FileManager.default.enumerator(at: root.appendingPathComponent(folder), includingPropertiesForKeys: nil)
    )
    var importing: [String] = []
    for case let url as URL in enumerator where url.pathExtension == "swift" {
      if try String(contentsOf: url, encoding: .utf8).contains("JavaScriptCore") {
        importing.append(url.lastPathComponent)
      }
    }
    #expect(importing.isEmpty, "\(importing)")
  }
}
