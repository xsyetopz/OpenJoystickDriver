import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverPresentation

@MainActor
struct LibraryListingRowTests {
  private let model = ControllerModelID(vendorID: 0x05FD, productID: 0x1007)

  private func item(signed: Bool = false) -> LibraryRecordItem {
    LibraryRecordItem(
      model: model,
      family: .xboxXID,
      layer: .bundled,
      file: nil,
      appleSigned: signed
    )
  }

  @Test
  func aRowCaptionIsTheFamilyAndTheLayer() {
    #expect(item().caption == "Xbox (XID) · Built-in")
  }

  @Test
  func aClaimedRecordEndsItsCaptionWithAppleSigned() {
    #expect(item(signed: true).caption == "Xbox (XID) · Built-in · Apple-signed")
  }

  @Test
  func searchMatchesAppleSignedOnlyOnAClaimedRecord() {
    #expect(item(signed: true).matches("apple-signed"))
    #expect(!item(signed: false).matches("apple-signed"))
    #expect(item(signed: true).matches("05fd:1007"))
  }

  @Test
  func theStoreMarksOnlyTheRecordsTheExtensionClaims() throws {
    let raw = ControllerRecordSet.bundled.records.values.filter(\.usesRawUSB)
      .map(\.model).sorted()
    let claimed = try #require(raw.first)
    let unclaimed = try #require(raw.last)
    let hid = try #require(
      ControllerRecordSet.bundled.records.values.first { !$0.usesRawUSB }?.model
    )
    PlatformHosts.install(FakePlatformHost(entitlementCovers: [claimed]))
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
      isDirectory: true
    )

    let items = DirectoryLibraryStore(recordsDirectory: directory).records().builtIn

    #expect(items.filter(\.appleSigned).map(\.model) == [claimed])
    #expect(items.first { $0.model == unclaimed }?.caption.contains("Apple-signed") == false)
    #expect(items.first { $0.model == hid }?.caption.contains("Apple-signed") == false)
  }
}
