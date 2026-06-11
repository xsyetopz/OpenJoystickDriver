import Foundation

public enum SDL3GamepadButton: Int, CaseIterable, Sendable {
  case south = 0
  case east = 1
  case west = 2
  case north = 3
  case back = 4
  case guide = 5
  case start = 6
  case leftStick = 7
  case rightStick = 8
  case leftShoulder = 9
  case rightShoulder = 10
  case dpadUp = 11
  case dpadDown = 12
  case dpadLeft = 13
  case dpadRight = 14
  case misc1 = 15
  case rightPaddle1 = 16
  case leftPaddle1 = 17
  case rightPaddle2 = 18
  case leftPaddle2 = 19
  case touchpad = 20
  case misc2 = 21
  case misc3 = 22
  case misc4 = 23
  case misc5 = 24
  case misc6 = 25
}

public enum SDL3GamepadAxis: Int, CaseIterable, Sendable {
  case leftX = 0
  case leftY = 1
  case rightX = 2
  case rightY = 3
  case leftTrigger = 4
  case rightTrigger = 5
}

public struct SDL3DeviceIdentity: Equatable, Sendable {
  public let instanceID: Int32?
  public let vendorID: UInt16
  public let productID: UInt16
  public let version: UInt16
  public let name: String
  public let serial: String?
  public let guid: String?
  public let locationID: UInt32?

  public init(
    instanceID: Int32? = nil,
    vendorID: UInt16,
    productID: UInt16,
    version: UInt16 = 0,
    name: String,
    serial: String?,
    guid: String?,
    locationID: UInt32?
  ) {
    self.instanceID = instanceID
    self.vendorID = vendorID
    self.productID = productID
    self.version = version
    self.name = name
    self.serial = serial
    self.guid = guid
    self.locationID = locationID
  }

  public var deviceIdentifier: DeviceIdentifier {
    DeviceIdentifier(
      vendorID: vendorID,
      productID: productID,
      serialNumber: serial?.isEmpty == false ? serial : nil,
      locationID: locationID ?? instanceID.map { UInt32(bitPattern: $0) }
    )
  }

  public var isOpenJoystickDriverVirtualDevice: Bool {
    if UserSpaceVirtualDeviceConstants.isOJDUserSpaceSerial(serial) { return true }
    if serial == VirtualDeviceIdentityConstants.driverKitSerialNumber { return true }
    if let locationID {
      if locationID == VirtualDeviceIdentityConstants.driverKitLocationID { return true }
      if (locationID & 0xFFFF_0000) == VirtualDeviceIdentityConstants.userSpaceLocationIDNamespace {
        return true
      }
    }
    let ojdVID = UInt16(VirtualDeviceProfile.openJoystickDriver.vendorID)
    if vendorID == ojdVID { return true }
    if name.localizedCaseInsensitiveContains("OpenJoystickDriver") { return true }
    if guid == "0300f88c4a4f00004844000008040000" { return true }
    return false
  }
}

public struct SDL3GamepadSnapshot: Equatable, Sendable {
  public let vendorID: UInt16
  public let productID: UInt16
  public var buttons: Set<SDL3GamepadButton>
  public var axes: [SDL3GamepadAxis: Int16]

  public init(
    vendorID: UInt16,
    productID: UInt16,
    buttons: Set<SDL3GamepadButton> = [],
    axes: [SDL3GamepadAxis: Int16] = [:]
  ) {
    self.vendorID = vendorID
    self.productID = productID
    self.buttons = buttons
    var allAxes: [SDL3GamepadAxis: Int16] = [:]
    for axis in SDL3GamepadAxis.allCases { allAxes[axis] = axes[axis] ?? 0 }
    self.axes = allAxes
  }

  public static func neutral(vendorID: UInt16, productID: UInt16) -> Self {
    Self(vendorID: vendorID, productID: productID)
  }
}
