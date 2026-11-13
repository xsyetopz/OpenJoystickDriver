import Foundation
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit

/// Where the documented families come from: the user's `Protocols` folder and mod packages.
struct DocumentedFamilyLoadingTests {
  private static func description(
    _ name: String,
    edit: (inout [String: Any]) -> Void = { _ in }
  ) throws -> (name: String, data: Data) {
    var tree = try #require(
      try PropertyListFixture.tree(DocumentedFamilyTests.description(named: name))
        as? [String: Any]
    )
    edit(&tree)
    return ("\(name).plist", try PropertyListFixture.data(tree: tree))
  }

  private static func family(_ name: String) -> DocumentedProtocolFamily? {
    DocumentedProtocolFamilies.families.first { $0.name == name }
  }

  private func install(
    _ protocols: [(name: String, data: Data)],
    in fixture: ModPackageFixture
  ) throws -> ModPackage {
    let folder = try fixture.makePackage(protocols: protocols)
    return try fixture.store().install(folder)
  }

  @Test
  func bundledFlydigiRecordBindsDocumentedFamilyAndDecodesCapturedReport() throws {
    let model = ControllerModelID(vendorID: 0xD7D7, productID: 0x0041)
    let family = try #require(ControllerRecordSet.bundled.records[model]?.protocolID)
    #expect(family.rawValue == "VendorFlydigi")
    #expect(family.isDocumented)
    #expect(family.displayName == "Flydigi")
    let driver = ReportLayoutDriver(
      describedBy: family,
      variant: nil,
      rumbleTemplate: nil,
      outEndpoint: 0x02,
      tuning: nil
    )
    var report = Data([0x01, 0xFF, 0xFF, 0xFF, 0xFF, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
    _ = try driver.parseReport(report)
    report[9] = 0x10
    #expect(try driver.parseReport(report).contains(.press(.south)))
  }

  @Test
  func userDescriptionReplacesBundledFamilyOfTheSameNameWithNoRefusal() throws {
    try ModPackageFixture.with { fixture in
      defer { DocumentedProtocolFamilies.register([], owner: fixture.root) }
      #expect(Self.family("VendorFlydigi")?.isBundled == true)
      try fixture.write(
        [try Self.description("VendorFlydigi")],
        kind: "Protocols",
        in: fixture.root
      )
      let set = ControllerRecordSet.load(userDirectory: fixture.controllers)
      #expect(set.problems.isEmpty)
      let family = try #require(Self.family("VendorFlydigi"))
      #expect(family.displayName == "Acme Pad")
      #expect(!family.isBundled)
      #expect(family.file.lastPathComponent == "VendorFlydigi.plist")
      #expect(family.package == nil)
      let model = ControllerModelID(vendorID: 0xD7D7, productID: 0x0041)
      #expect(set.records[model]?.protocolID.displayName == "Acme Pad")
    }
  }

  @Test
  func flydigiIsNotABuiltInFamily() {
    #expect(!PhysicalProtocolID.allCases.map(\.rawValue).contains("VendorFlydigi"))
  }

  @Test
  func descriptionInUserProtocolsFolderLoadedWithItsDisplayName() throws {
    try ModPackageFixture.with { fixture in
      let file = try Self.description("VendorUserLoaded")
      try fixture.write([file], kind: "Protocols", in: fixture.root)
      let set = ControllerRecordSet.load(userDirectory: fixture.controllers)
      #expect(set.problems.isEmpty)
      let family = try #require(Self.family("VendorUserLoaded"))
      #expect(family.displayName == "Acme Pad")
      #expect(family.package == nil)
      #expect(family.file.lastPathComponent == "VendorUserLoaded.plist")
    }
  }

  @Test
  func userFileRefusedListedAndNotLoaded() throws {
    try ModPackageFixture.with { fixture in
      let builtIn = try Self.description("XboxGIP")
      let noLayouts = try Self.description("VendorUserNoLayouts") {
        $0["defaults"] = nil
      }
      let wrongStem = try Self.description("VendorUserWrongStem")
      try fixture.write(
        [builtIn, noLayouts, (name: "VendorOther.plist", data: wrongStem.data)],
        kind: "Protocols",
        in: fixture.root
      )
      let set = ControllerRecordSet.load(userDirectory: fixture.controllers)
      #expect(set.problems.count == 3)
      #expect(Self.family("VendorUserNoLayouts") == nil)
      #expect(Self.family("VendorUserWrongStem") == nil)
      #expect(set.problems.contains { $0.problem?.hasPrefix("E5003") == true })
    }
  }

  @Test
  func packageDescriptionLoadedWithPackageAsItsSource() throws {
    try ModPackageFixture.with { fixture in
      let package = try install([Self.description("VendorPackLoaded")], in: fixture)
      _ = ControllerRecordSet.load(userDirectory: fixture.controllers)
      let family = try #require(Self.family("VendorPackLoaded"))
      #expect(family.package == package.name)
      #expect(family.displayName == "Acme Pad")
      try fixture.store().remove(package.name)
      _ = ControllerRecordSet.load(userDirectory: fixture.controllers)
      #expect(Self.family("VendorPackLoaded") == nil)
    }
  }

  @Test
  func packageRefusesDescriptionNotDocumented() throws {
    try ModPackageFixture.with { fixture in
      let wrongStem = try Self.description("VendorPackWrongStem")
      let refused: [[(name: String, data: Data)]] = [
        [try Self.description("XboxGIP")],
        [try Self.description("VendorPackNoLayouts") { $0["defaults"] = nil }],
        [(name: "VendorOther.plist", data: wrongStem.data)],
      ]
      for protocols in refused {
        #expect(throws: ModPackageError.self) { try install(protocols, in: fixture) }
      }
    }
  }

  @Test
  func packageRecordMayUseFamilyOfItsOwnPackage() throws {
    try ModPackageFixture.with { fixture in
      let record = try ModPackageFixture.record(0x1234, 0xAC02)
      var data = try #require(try PropertyListFixture.tree(record.data) as? [String: Any])
      data["modes"] = [["id": "default", "protocol": ["family": "VendorPackOwn"]]]
      let package = try fixture.makePackage(
        controllers: [(record.name, try PropertyListFixture.data(tree: data))],
        protocols: [try Self.description("VendorPackOwn")]
      )
      try fixture.store().install(package)
      let set = ControllerRecordSet.load(userDirectory: fixture.controllers)
      #expect(set.problems.isEmpty)
      #expect(set.records[ControllerModelID(vendorID: 0x1234, productID: 0xAC02)] != nil)
    }
  }

  @Test
  func packageDescriptionUserAlsoHoldsClashes() throws {
    try ModPackageFixture.with { fixture in
      let file = try Self.description("VendorClash")
      try fixture.write([file], kind: "Protocols", in: fixture.root)
      #expect(throws: ModPackageError.self) { try install([file], in: fixture) }
    }
  }
}
