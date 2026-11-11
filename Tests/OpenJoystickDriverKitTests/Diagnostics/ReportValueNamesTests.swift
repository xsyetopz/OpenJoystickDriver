import Foundation
import Testing

@testable import OpenJoystickDriverKit

/// Report values are UpperCamelCase with upper-case acronyms; any other spelling is an unknown
/// value like a random word.
struct ReportValueNamesTests {
  private func decodes<T: Decodable>(_: T.Type, _ word: String) -> Bool {
    (try? JSONDecoder().decode([T].self, from: Data("[\"\(word)\"]".utf8))) != nil
  }

  private func refuses<T: Decodable>(_ type: T.Type, _ words: [String]) {
    for word in words + ["notAWord"] {
      #expect(!decodes(type, word), "\(T.self) accepted \(word)")
    }
  }

  @Test
  func theCurrentNamesDecode() {
    #expect(decodes(PhysicalTransport.self, "BluetoothLE"))
    #expect(decodes(DeviceAccessBackend.self, "USBExtension"))
    #expect(decodes(ProtocolBindingResult.Outcome.self, "Bound"))
    #expect(decodes(ProtocolPredicate.self, "HIDDescriptorContract"))
    #expect(decodes(ProtocolBinding.Rule.self, "HIDDescriptor"))
    #expect(decodes(FrameStage.self, "DeliveryVirtualDevice"))
  }

  @Test
  func transportsRefuseOtherSpellings() {
    refuses(
      PhysicalTransport.self,
      ["usb", "bluetoothClassic", "bluetoothLE", "proprietaryRadioReceiver", "bluetooth-le"]
    )
  }

  @Test
  func accessBackendsRefuseOtherSpellings() {
    refuses(
      DeviceAccessBackend.self,
      ["hid", "rawUSB", "usbExtension", "gatt"]
    )
  }

  @Test
  func bindingValuesRefuseOtherSpellings() {
    refuses(ProtocolBindingResult.Outcome.self, ["bound", "unsupported"])
    refuses(ProtocolBinding.Rule.self, ["catalogRecord", "interfaceSignature", "hidDescriptor"])
    refuses(
      ProtocolPredicate.self,
      ["catalogIdentity", "catalogAccessPath", "hostTransport", "hidDescriptorContract"]
    )
    refuses(ProtocolBindingReason.self, ["noProtocolMatch", "virtualProfileUnavailable"])
  }

  @Test
  func stateValuesRefuseOtherSpellings() {
    refuses(ControllerSessionState.self, ["active", "suspended"])
    refuses(BuildIdentity.SourceState.self, ["clean", "dirty", "unknown"])
    refuses(
      ControllerInputHealthState.self,
      ["awaitingInput", "healthy", "stale", "waitingForNeutral"]
    )
    refuses(
      ControllerInputHealthFailureReason.self,
      ["missingReports", "freshnessNotAdvancing", "guideNotPressed"]
    )
    refuses(
      ControllerConnectionState.Charging.self,
      ["unknown", "discharging", "charging", "full", "notChargeable"]
    )
    refuses(ApplicationServiceSerialKind.self, ["none", "ojdUserSpace", "present"])
    refuses(SystemGamepadCatalogSource.self, ["downloadedMobileAsset", "unavailable"])
    refuses(
      FrameStage.self,
      ["read", "parse", "dispatch", "delivery-virtual-device", "delivery-endpoint"]
    )
  }
}
