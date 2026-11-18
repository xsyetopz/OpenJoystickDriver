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

  /// A stored unit ID names the same port in every release.
  @Test
  func portKeyIsTheHMACOfModelLocationAndInterface() throws {
    let digest = HMAC<SHA256>.authenticationCode(
      for: Data("054C:0CE6:00130000:00".utf8),
      using: installationKey
    )

    let key = try #require(portKey())

    #expect(key.rawValue == PrefixedIdentifierText.make(prefix: "U-", bytes: digest))
  }

  private func peripheralKey(_ peripheral: UUID, productID: UInt16 = 0x2066) -> ControllerPortKey? {
    ControllerPortKey.of(
      LogicalControllerID(
        hardware: ControllerHardwareIdentity(
          model: ControllerModelID(vendorID: 0x057E, productID: productID),
          serialNumber: nil
        ),
        address: .gattPeripheral(peripheral)
      ),
      installationKey: installationKey
    )
  }

  /// A Bluetooth LE controller has no location; its unit ID comes from its peripheral identifier,
  /// so an override can name one of two identical pads.
  @Test
  func bluetoothLEPeripheralHasItsOwnPortKey() throws {
    let first = try #require(UUID(uuidString: "6F1B8C1E-0F7A-4C55-9E0B-3D2A1C4B5E6F"))
    let second = try #require(UUID(uuidString: "0A9E3D52-7B14-4F0C-8C61-5A2E9B7D1F30"))

    let key = try #require(peripheralKey(first))

    #expect(peripheralKey(first) == key)
    #expect(peripheralKey(second) != key)
    #expect(peripheralKey(first, productID: 0x2067) != key)
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
