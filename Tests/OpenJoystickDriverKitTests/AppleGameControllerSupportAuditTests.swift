import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct AppleGameControllerSupportAuditTests {
  @Test func parsesDeduplicatesAndPreservesMatchConstraints() throws {
    let first = try bundleInfo(
      version: "10.5.2",
      devices: [
        device(
          identifier: "example.usb",
          vendorID: 1_133,
          productID: 49_695,
          versionNumber: 773,
          transport: "USB"
        ),
        device(identifier: "missing.pid", vendorID: 1_133, productID: nil),
      ]
    )
    let second = try bundleInfo(
      version: "10.5.2",
      devices: [
        device(
          identifier: "example.bluetooth",
          vendorID: 1_133,
          productID: 49_695,
          versionNumber: 774,
          transport: "Bluetooth"
        ),
      ]
    )

    let snapshot = AppleGameControllerSupportAuditor.snapshot(
      bundleInfoData: [first, second],
      source: .downloadedMobileAsset
    )
    let entry = try #require(snapshot.entries.first)

    #expect(snapshot.bundleVersions == ["10.5.2"])
    #expect(snapshot.entries.count == 1)
    #expect(snapshot.skippedDeviceCount == 1)
    #expect(entry.vendorID == 1_133)
    #expect(entry.productID == 49_695)
    #expect(entry.identifiers == ["example.bluetooth", "example.usb"])
    #expect(entry.transports == ["Bluetooth", "USB"])
    #expect(entry.versionNumbers == [773, 774])
  }

  @Test func auditUsesExactPairsWithoutClaimingRuntimeSupport() {
    let snapshot = AppleGameControllerCatalogSnapshot(
      source: .preinstalledMobileAsset,
      bundleVersions: ["1.2.3"],
      entries: [AppleGameControllerCatalogEntry(vendorID: 1, productID: 2, identifiers: ["listed"])]
    )
    let audit = AppleGameControllerSupportAuditor.audit(
      snapshot: snapshot,
      records: [
        OJDControllerRecordIdentity(vendorID: 1, productID: 2, name: "Listed"),
        OJDControllerRecordIdentity(vendorID: 1, productID: 3, name: "Not listed"),
      ]
    )

    #expect(audit.appleExactDeviceCount == 1)
    #expect(audit.ojdRecordCount == 2)
    #expect(audit.catalogListedOJDRecordCount == 1)
    #expect(audit.records[0].catalogListed)
    #expect(!audit.records[1].catalogListed)
    #expect(audit.caveat.contains("does not prove"))
    #expect(audit.caveat.contains("supportsHIDDevice"))
  }

  @Test func compatibilityAuditRequiresAnExactListedSpoofIdentity() throws {
    let identity = CompatibilityIdentity.xoneHID
    let profile = CompatibilityOutputProfileCatalog.profile(for: identity)
    let snapshot = AppleGameControllerCatalogSnapshot(
      source: .downloadedMobileAsset,
      bundleVersions: ["1"],
      entries: [
        AppleGameControllerCatalogEntry(
          vendorID: UInt16(profile.deviceProfile.vendorID),
          productID: UInt16(profile.deviceProfile.productID),
          identifiers: ["exact.xbox.one"]
        ),
      ]
    )

    let audit = AppleGameControllerSupportAuditor.audit(snapshot: snapshot, records: [])
    let row = try #require(audit.compatibilityProfiles.first { $0.identity == identity.rawValue })
    let generic = try #require(
      audit.compatibilityProfiles.first { $0.identity == CompatibilityIdentity.genericHID.rawValue }
    )

    #expect(audit.hardwareSpoofCompatibilityProfileCount == 3)
    #expect(audit.appleBackedCompatibilityProfileCount == 1)
    #expect(row.catalogListed)
    #expect(row.appleBackedExactIdentity)
    #expect(row.appleIdentifiers == ["exact.xbox.one"])
    #expect(!generic.isHardwareSpoof)
    #expect(!generic.appleBackedExactIdentity)
  }

  @Test func malformedBundlesRemainExplicitEvidence() {
    let snapshot = AppleGameControllerSupportAuditor.snapshot(
      bundleInfoData: [Data("not a plist".utf8)],
      source: .downloadedMobileAsset
    )

    #expect(snapshot.entries.isEmpty)
    #expect(snapshot.warnings.contains { $0.contains("could not be parsed") })
  }

  private func bundleInfo(version: String, devices: [[String: Any]]) throws -> Data {
    try PropertyListSerialization.data(
      fromPropertyList: ["CFBundleVersion": version, "Devices": devices],
      format: .binary,
      options: 0
    )
  }

  private func device(
    identifier: String,
    vendorID: Int,
    productID: Int?,
    versionNumber: Int? = nil,
    transport: String? = nil
  ) -> [String: Any] {
    var match: [String: Any] = ["VendorID": vendorID]
    if let productID { match["ProductID"] = productID }
    if let versionNumber { match["VersionNumber"] = versionNumber }
    if let transport { match["Transport"] = transport }
    return ["Identifier": identifier, "IOPropertyMatch": match]
  }
}
