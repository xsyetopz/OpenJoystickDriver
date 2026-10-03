import CryptoKit
import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct UnitIdentityTests {
  private let key = SymmetricKey(data: Data(repeating: 7, count: 32))

  private func unit(
    location: UInt32? = 0x0013_0000,
    interface: UInt8? = 0,
    serial: String? = nil,
    key: SymmetricKey? = nil
  ) -> String? {
    UnitIdentity.identifier(
      for: DeviceIdentifier(
        vendorID: 0x054C,
        productID: 0x0CE6,
        serialNumber: serial,
        locationID: location,
        interfaceNumber: interface
      ),
      key: key ?? self.key
    )
  }

  @Test
  func theSameUnitOnTheSamePortHasTheSameWellFormedID() throws {
    let id = try #require(unit())
    #expect(id == unit())
    #expect(UnitIdentity.isWellFormed(id))
  }

  @Test
  func thePortInterfaceAndKeySelectTheIDButTheSerialNumberDoesNot() {
    #expect(unit(location: 0x0014_0000) != unit())
    #expect(unit(interface: 1) != unit())
    #expect(unit(interface: nil) != unit())
    #expect(unit(key: SymmetricKey(data: Data(repeating: 8, count: 32))) != unit())
    #expect(unit(serial: "A") == unit(serial: "B"))
  }

  @Test
  func aControllerWithoutALocationIDHasNoUnitID() {
    #expect(unit(location: nil) == nil)
  }

  @Test
  func theKeyIsCreatedOnceAndKeptInDefaults() throws {
    let suite = "UnitIdentityTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }

    let first = UnitIdentity.key(in: defaults)
    #expect(defaults.data(forKey: UnitIdentity.defaultsKey)?.count == 32)
    #expect(unit(key: UnitIdentity.key(in: defaults)) == unit(key: first))
  }

  @Test(arguments: [
    ("U-AbCd_123-xyzW09q", true), ("U-AbCd_123-xyzW09", false), ("U-AbCd+123-xyzW09q", false),
    ("X-AbCd_123-xyzW09q", false), ("", false),
  ])
  func wellFormedIDsAreUAnd16Base64URLCharacters(text: String, valid: Bool) {
    #expect(UnitIdentity.isWellFormed(text) == valid)
  }
}
