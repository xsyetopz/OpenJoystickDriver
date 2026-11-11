import Foundation

extension DeviceManager {
  /// How OJD discovered a controller: through HID, or as a raw USB service on a transport route.
  enum DiscoverySource {
    /// The controller was discovered through HID.
    case hid
    /// The controller was discovered as a raw USB service on `route`.
    case rawUSB(route: USBTransportRoute)

    /// Whether the route reads input through HID, which needs the Input Monitoring permission.
    var requiresInputRead: Bool {
      if case .hid = self { return true }
      return false
    }

    /// The public discovery route that this source reports.
    var kind: DeviceDiscoverySource {
      switch self {
      case .hid: .hid
      case .rawUSB: .rawUSB
      }
    }

    /// The ownership that the route implies: HID is visible to the system, raw USB is exclusive,
    /// and the USB extension owns its service.
    var ownershipObservation: ControllerOwnershipObservation {
      switch self {
      case .hid: .systemHIDVisible
      case .rawUSB(.rawUSB): .exclusiveRawUSB
      case .rawUSB(.usbExtension): .extensionOwnedUSB
      }
    }
  }

  /// What the manager knows about one bound controller: its name, link, protocol binding and the
  /// discovery details of its connection.
  struct DeviceInfo {
    /// The controller's display name.
    let name: String
    /// The connection label, such as "USB" or the HID transport property.
    let connection: String
    /// The serial number, or nil if the device does not report one.
    let serialNumber: String?
    /// The route that discovered the controller.
    let discoverySource: DiscoverySource
    /// The protocol binding that serves the controller.
    let binding: ProtocolBinding
    /// The result of the HID input acquisition; unknown for a raw-USB controller.
    var hidInputOwnership: HIDInputOwnership = .unknown
    /// The physical facts observed for the controller, if the route supplied them.
    let physicalDevice: PhysicalDevice?
    /// The ID of the HID connection that the controller was admitted on; nil for raw USB.
    let hidConnectionID: UUID?
    /// Exact enumerated service snapshot used for USB route ownership, not descriptor evidence.
    let usbTransportDevice: USBTransportDevice?
    /// This attachment's token.
    ///
    /// Every ``DeviceInfo`` issues its own, so a reconnect never reuses the token of an earlier
    /// attachment.
    let sessionToken = ControllerSessionToken.issue()

    /// Creates the information of a bound controller.
    init(
      name: String,
      connection: String,
      serialNumber: String?,
      discoverySource: DiscoverySource,
      binding: ProtocolBinding,
      hidInputOwnership: HIDInputOwnership = .unknown,
      physicalDevice: PhysicalDevice? = nil,
      hidConnectionID: UUID? = nil,
      usbTransportDevice: USBTransportDevice? = nil
    ) {
      self.name = name
      self.connection = connection
      self.serialNumber = serialNumber
      self.discoverySource = discoverySource
      self.binding = binding
      self.hidInputOwnership = hidInputOwnership
      self.physicalDevice = physicalDevice
      self.hidConnectionID = hidConnectionID
      self.usbTransportDevice = usbTransportDevice
    }

    /// The physical ownership observed for the controller.
    ///
    /// The system gamepad for a native pass-through device, exclusive HID when OJD holds the HID
    /// input exclusively, and otherwise what the discovery route implies.
    var ownershipObservation: ControllerOwnershipObservation {
      if physicalDevice?.nativePassThrough == true { return .systemGamepad }
      if case .hid = discoverySource, hidInputOwnership == .exclusive { return .exclusiveHID }
      return discoverySource.ownershipObservation
    }

    /// The risk that the system also exposes this controller beside OJD's virtual gamepad.
    var duplicateExposureRisk: DuplicateExposureRisk {
      let ownership = ownershipObservation
      if physicalDevice?.systemListsGameController == true, !ownership.isServedBySystem {
        return .systemGameController
      }
      return DuplicateExposureRisk(observation: ownership)
    }
  }
}
