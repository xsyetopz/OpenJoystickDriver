import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverPresentation

@Suite
struct StatusItemModelTests {
  @Test
  func entryIDsAreUniqueBecauseTheyAreTheAccessibilityIdentifiers() {
    func controller(_ id: String) -> StatusItemState.Controller {
      var controller = StatusItemState.Controller(
        id: id,
        name: "Pad",
        isSuspended: false,
        isWireless: true
      )
      controller.profiles = [StatusItemState.Profile(id: UUID(), name: "A", isActive: true)]
      return controller
    }
    let entries = StatusItemModel.entries(
      for: StatusItemState(
        problems: [.missingPermission(.inputRead), .serviceNotRunning],
        controllers: [controller("pad-a"), controller("pad-b")],
        profileListRead: true
      )
    )
    func allIDs(_ entries: [StatusItemEntry]) -> [String] {
      entries.flatMap { [$0.id] + allIDs($0.submenu ?? []) }
    }
    let ids = allIDs(entries)
    #expect(Set(ids).count == ids.count)
  }

  @Test
  func typedBluetoothTransportDecidesWireless() {
    func device(
      _ transport: PhysicalTransport?,
      connection: String
    )
      -> ApplicationServiceDeviceDescription
    {
      ApplicationServiceDeviceDescription(
        name: "Pad",
        vendorID: 1,
        productID: 2,
        protocolBinding: ProtocolBindingID(.hidDescriptor),
        connection: connection,
        discoverySource: .rawUSB,
        serialNumber: nil,
        bindingResult: .hidDescriptorFixture,
        recordServer: .system,
        recordAccessRoute: .system,
        connectionState: ControllerConnectionState(
          transport: transport,
          backend: .hid,
          isConnected: true,
          power: .unknown
        )
      )
    }
    #expect(device(.bluetoothClassic, connection: "HID").supportsWirelessDisconnect)
    #expect(!device(.bluetoothLE, connection: "HID").supportsWirelessDisconnect)
    #expect(!device(.usb, connection: "Bluetooth").supportsWirelessDisconnect)
    #expect(!device(nil, connection: "Bluetooth").supportsWirelessDisconnect)
  }
}
