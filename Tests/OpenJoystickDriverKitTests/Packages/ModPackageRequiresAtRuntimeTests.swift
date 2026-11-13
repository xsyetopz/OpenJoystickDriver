import Foundation
import Testing

@testable import OpenJoystickDriverKit

/// An installed package whose `requires` leaves out the running version is skipped and listed.
struct ModPackageRequiresAtRuntimeTests {
  private typealias Fixture = ModPackageFixture

  private static let identity = ControllerModelID(vendorID: 0x1234, productID: 0xABCD)
  private static let range: [String: String] = ["minimum": "0.6.0", "below": "0.7.0"]
  private static let outOfRange = "9.0.0"

  /// Whether `problem` is the `requires` problem, by its error code.
  private static func isRequiresProblem(_ problem: String?) -> Bool {
    problem?.hasPrefix("E4002") == true
  }

  /// Installs `arcade-pack` for 0.6.0 up to 0.7.0 while the running version is 0.6.0.
  private func installOldPackage(
    in fixture: Fixture,
    controllers: [(name: String, data: Data)] = [],
    virtualDevices: [(name: String, data: Data)] = []
  ) throws {
    try fixture.store().install(
      try fixture.makePackage(
        requires: Self.range,
        controllers: controllers,
        virtualDevices: virtualDevices
      )
    )
  }

  @Test
  func listGivesRequiresProblemAndKeepsManifest() throws {
    try Fixture.with { fixture in
      try installOldPackage(in: fixture, controllers: [try Fixture.record(0x1234, 0xABCD)])

      let package = try #require(fixture.store(running: Self.outOfRange).list().first)
      #expect(Self.isRequiresProblem(package.problem))
      #expect(package.manifest?.name == "arcade-pack")
      #expect(package.manifest?.version == "1.0.0")
      #expect(fixture.store().list().first?.problem == nil)
    }
  }

  @Test
  func listAdmitsEveryPackageOnDevelopmentBuild() throws {
    try Fixture.with { fixture in
      try installOldPackage(in: fixture, controllers: [try Fixture.record(0x1234, 0xABCD)])

      let package = try #require(fixture.store(running: "unknown").list().first)
      #expect(package.problem == nil)
      #expect(package.manifest != nil)
    }
  }

  @Test
  func recordLayerSkipsAndListsOutOfRangePackage() throws {
    try Fixture.with { fixture in
      try installOldPackage(in: fixture, controllers: [try Fixture.record(0x1234, 0xABCD)])

      let packaged = ControllerRecordSet.packageRecords(
        in: fixture.packages,
        runningVersion: Self.outOfRange
      )
      #expect(packaged.records[Self.identity] == nil)
      #expect(packaged.files.map(\.url.lastPathComponent) == [ModPackageManifest.fileName])
      #expect(packaged.files.map { Self.isRequiresProblem($0.problem) } == [true])
    }
  }

  @Test
  func personaLayerSkipsAndListsOutOfRangePackage() throws {
    try Fixture.with { fixture in
      try installOldPackage(in: fixture, virtualDevices: [Fixture.persona(0x1234, 0xABCD)])

      let store = VirtualHIDProfileOverrideStore(
        directory: fixture.virtualDevices,
        runningVersion: Self.outOfRange
      )
      #expect(store.override(vendorID: 0x1234, productID: 0xABCD) == nil)
      #expect(store.problems.map(\.url.lastPathComponent) == [ModPackageManifest.fileName])
      #expect(store.problems.map { Self.isRequiresProblem($0.problem) } == [true])
    }
  }

  @Test
  func outOfRangePackageDoesNotBlockAnotherWithSameIdentity() throws {
    try Fixture.with { fixture in
      let record = try Fixture.record(0x1234, 0xABCD)
      try installOldPackage(in: fixture, controllers: [record])

      let replacement = try fixture.makePackage("arcade-pack-next", controllers: [record])
      let installed = try fixture.store(running: Self.outOfRange).install(replacement)
      #expect(installed.name == "arcade-pack-next")

      let packaged = ControllerRecordSet.packageRecords(
        in: fixture.packages,
        runningVersion: Self.outOfRange
      )
      #expect(packaged.records[Self.identity]?.file?.path.contains("arcade-pack-next") == true)
    }
  }
}
