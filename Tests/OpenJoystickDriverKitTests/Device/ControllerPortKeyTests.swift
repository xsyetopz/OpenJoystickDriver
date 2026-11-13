import CryptoKit
import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct ControllerPortKeyTests {
  private let installationKey = SymmetricKey(data: Data(repeating: 7, count: 32))

  private func portKey(
    location: UInt32? = 0x0013_0000,
    interface: UInt8? = 0,
    serial: String? = nil,
    installationKey: SymmetricKey? = nil
  ) -> ControllerPortKey? {
    ControllerPortKey.of(
      LogicalControllerID(
        vendorID: 0x054C,
        productID: 0x0CE6,
        serialNumber: serial,
        locationID: location,
        interfaceNumber: interface
      ),
      installationKey: installationKey ?? self.installationKey
    )
  }

  @Test
  func sameUnitOnSamePortHasSameWellFormedKey() throws {
    let key = try #require(portKey())
    #expect(key == portKey())
    #expect(ControllerPortKey(rawValue: key.rawValue) == key)
  }

  @Test
  func portInterfaceAndInstallationKeySelectPortKeyButSerialNumberDoesNot() {
    #expect(portKey(location: 0x0014_0000) != portKey())
    #expect(portKey(interface: 1) != portKey())
    #expect(portKey(interface: nil) != portKey())
    #expect(
      portKey(installationKey: SymmetricKey(data: Data(repeating: 8, count: 32))) != portKey()
    )
    #expect(portKey(serial: "A") == portKey(serial: "B"))
  }

  @Test
  func everyPortOfOneModelHasItsOwnKey() {
    let keys = (0..<64).map { portKey(location: 0x0010_0000 + UInt32($0) << 12) }
    #expect(Set(keys).count == 64)
  }

  @Test
  func controllerWithoutLocationIDHasNoPortKey() {
    #expect(portKey(location: nil, interface: nil) == nil)
  }

  @Test(arguments: [
    ("U-AbCd_123-xyzW09q", true), ("U-AbCd_123-xyzW09", false), ("U-AbCd+123-xyzW09q", false),
    ("E-AbCd_123-xyzW09q", false), ("", false),
  ])
  func portKeysAreUAnd16Base64URLCharacters(text: String, valid: Bool) {
    #expect((ControllerPortKey(rawValue: text) != nil) == valid)
  }

  @Test
  func encodesAsItsTextAndRejectsOtherText() throws {
    let key = try #require(portKey())
    let data = try JSONEncoder().encode(key)
    #expect(String(bytes: data, encoding: .utf8) == "\"\(key.rawValue)\"")
    #expect(try JSONDecoder().decode(ControllerPortKey.self, from: data) == key)
    #expect(throws: DecodingError.self) {
      try JSONDecoder().decode(ControllerPortKey.self, from: Data("\"U-short\"".utf8))
    }
  }
}
