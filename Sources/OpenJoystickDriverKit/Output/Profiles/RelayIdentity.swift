/// Stable identity shared by DriverKit relay configuration, discovery, and diagnostics.
package enum DriverKitRelayIdentity {
  package static let runtimeServiceClass = "SwifterKitRuntimeService"
  package static let bundleIdentifier = "com.openjoystickdriver.VirtualHIDDevice"
  package static let transport = "USB"
  package static let vendorID: UInt32 = 0x4F4A
  package static let productID: UInt32 = 0x4447
  package static let versionNumber: UInt32 = 0x0408
  package static let locationID: UInt32 = 0x4F4A_4401
  package static let manufacturer = "OpenJoystickDriver"
  package static let product = "OpenJoystickDriver DriverKit Relay"
  package static let serialNumber = "OpenJoystickDriver-DriverKit"
  package static let primaryUsagePage: UInt32 = 0xFF00
  package static let primaryUsage: UInt32 = 1
  package static let reportSize = 15

  package static let reportDescriptor: [UInt8] = [
    0x06, 0x00, 0xFF, 0x09, 0x01, 0xA1, 0x01, 0x15, 0x00, 0x26, 0xFF, 0x00, 0x75, 0x08, 0x95, 0x0F,
    0x09, 0x02, 0x91, 0x02, 0x09, 0x03, 0x81, 0x02, 0xC0,
  ]

  package static func matches(
    runtimeClass: String?,
    transport: String?,
    vendorID: UInt32,
    productID: UInt32,
    versionNumber: UInt32,
    locationID: UInt32,
    manufacturer: String?,
    product: String?,
    serialNumber: String?,
    primaryUsagePage: UInt32,
    primaryUsage: UInt32
  ) -> Bool {
    runtimeClass == Self.runtimeServiceClass && transport == Self.transport
      && vendorID == Self.vendorID && productID == Self.productID
      && versionNumber == Self.versionNumber && locationID == Self.locationID
      && manufacturer == Self.manufacturer && product == Self.product
      && serialNumber == Self.serialNumber && primaryUsagePage == Self.primaryUsagePage
      && primaryUsage == Self.primaryUsage
  }
}
