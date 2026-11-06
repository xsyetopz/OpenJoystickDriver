import Testing

@testable import OpenJoystickDriverKit

struct SDLGUIDTests {
  /// The pad of the tier tests: vendor 1, product 2, version 3, named "Pad".
  private static let pad = SDLGUID(
    vendorID: 1,
    productID: 2,
    version: 3,
    manufacturer: nil,
    product: "Pad"
  )

  private static func database(
    _ guids: [SDLGUID],
    names: [String]? = nil
  ) throws
    -> SDLGameControllerDatabase
  {
    try SDLGameControllerDatabase(
      text: guids.enumerated().map { index, guid in
        "\(guid),\(names?[index] ?? "line \(index)"),a:b0,platform:Mac OS X,"
      }.joined(separator: "\n")
    )
  }

  // MARK: - GUID

  @Test
  func crc16IsTheArcChecksum() {
    #expect(SDLGUID.crc16(Array("123456789".utf8)) == 0xBB3D)
  }

  @Test
  func guidHoldsBusNameCRCVendorProductAndVersion() {
    let guid = SDLGUID(
      vendorID: 0x2DC8,
      productID: 0x6001,
      version: 1,
      manufacturer: nil,
      product: "8BitDo SN30 Pro"
    )
    #expect(guid.description == "03007d80c82d00000160000001000000")
  }

  @Test
  func nameIsManufacturerThenProduct() {
    let named = SDLGUID(vendorID: 1, productID: 2, version: 3, manufacturer: "Sony", product: "Pad")
    let crc = SDLGUID.crc16(Array("Sony Pad".utf8))
    #expect(named.description.dropFirst(4).prefix(4) == String(crcBytes(crc)))
    let empty = SDLGUID(vendorID: 1, productID: 2, version: 3, manufacturer: "", product: "Pad")
    #expect(empty == Self.pad)
  }

  private func crcBytes(_ crc: UInt16) -> String {
    String(format: "%02x%02x", crc & 0xFF, crc >> 8)
  }

  @Test
  func textRoundTripsAndRejectsShortOrNonHexText() {
    #expect(SDLGUID(Self.pad.description) == Self.pad)
    #expect(SDLGUID("0300") == nil)
    #expect(SDLGUID(String(repeating: "zz", count: 16)) == nil)
  }

  // MARK: - Matching tiers

  @Test
  func tiersGoFromExactToNoVersionNoCRC() throws {
    let pad = Self.pad
    let tiers: [(SDLGUID, SDLMatchTier)] = [
      (pad, .exactGUID), (pad.withoutNameCRC, .guidWithoutNameCRC),
      (pad.withoutVersion, .guidWithoutVersion),
      (pad.withoutVersion.withoutNameCRC, .guidWithoutVersionAndNameCRC),
    ]
    for (index, (guid, tier)) in tiers.enumerated() {
      let database = try Self.database(tiers[index...].map(\.0))
      let match = try #require(database.match(pad))
      #expect(match.tier == tier)
      #expect(match.guid == guid)
      #expect(match.name == "line 0")
    }
  }

  @Test
  func aLineWithAnotherVersionMatchesOnlyWithoutTheVersion() throws {
    let other = SDLGUID(vendorID: 1, productID: 2, version: 9, manufacturer: nil, product: "Pad")
    let database = try Self.database([other.withoutVersion])
    #expect(database.match(other)?.tier == .guidWithoutVersion)
    #expect(try Self.database([other]).match(Self.pad) == nil)
  }

  @Test
  func aLineWithAnotherCRCAndVersionMatchesNothing() throws {
    let other = SDLGUID(vendorID: 1, productID: 2, version: 3, manufacturer: nil, product: "Other")
    #expect(try Self.database([other]).match(Self.pad) == nil)
  }

  @Test
  func aPadWithoutALineHasNoMatch() throws {
    #expect(try Self.database([]).match(Self.pad) == nil)
  }

  // MARK: - Duplicates and text

  @Test
  func theLastLineWithTheSameGUIDWins() throws {
    let database = try Self.database([Self.pad, Self.pad], names: ["first", "second"])
    #expect(database.match(Self.pad)?.name == "second")
  }

  @Test
  func commentsAndBlankLinesAreSkipped() throws {
    let database = try SDLGameControllerDatabase(
      text: "# header\n\n\(Self.pad),Pad,a:b0,platform:Mac OS X,\n"
    )
    #expect(database.match(Self.pad)?.fields == ["a:b0", "platform:Mac OS X"])
  }

  @Test
  func aMalformedLineNamesItsNumber() {
    #expect(throws: SDLDatabaseProblem.self) {
      try SDLGameControllerDatabase(text: "# header\nnot-a-guid,Pad,a:b0,\n")
    }
    do {
      _ = try SDLGameControllerDatabase(text: "# header\nnot-a-guid,Pad,a:b0,\n")
    } catch let problem as SDLDatabaseProblem {
      #expect(problem.lineNumber == 2)
    } catch {
      Issue.record("\(error)")
    }
  }

  @Test
  func theBundledDatabaseHoldsTheMacLines() throws {
    let sn30 = SDLGUID(
      vendorID: 0x2DC8,
      productID: 0x6001,
      version: 1,
      manufacturer: nil,
      product: "8BitDo SN30 Pro"
    )
    let match = try #require(SDLGameControllerDatabase.bundled.match(sn30))
    #expect(match.tier == .guidWithoutNameCRC)
    #expect(match.name == "8BitDo SN30 Pro")
  }

  @Test
  func indexingTheBundledFileTakesUnderASecond() throws {
    let text = SDLGameControllerDatabase.bundledText
    let elapsed = try ContinuousClock().measure { _ = try SDLGameControllerDatabase(text: text) }
    print("[SDLGUIDTests] indexed \(text.utf8.count) bytes in \(elapsed)")
    #expect(elapsed < .seconds(1))
  }
}
