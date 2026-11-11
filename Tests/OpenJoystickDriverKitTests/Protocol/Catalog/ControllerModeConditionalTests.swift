import Foundation
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit

/// A record-level section that depends on a mode's protocol holds for every mode: the default
/// mode satisfies each rule here and a second mode breaks it.
struct ControllerModeConditionalTests {
  private static var hid: [String: Any] { ["family": "SonySixaxis"] }
  private static var gip: [String: Any] { ["family": "XboxGIP"] }
  private static var hidMatch: [String: Any] {
    ["probes": [["report": 239, "length": 64, "expect": "Answers"]]]
  }
  private static var usbMatch: [String: Any] { ["link": "USB"] }

  private static func record(
    default first: [String: Any],
    second: [String: Any],
    match: [String: Any],
    session: [String: Any]? = nil,
    fields: [String: Any]
  ) -> [String: Any] {
    var secondMode: [String: Any] = ["id": "second", "protocol": second, "match": match]
    if let session { secondMode["session"] = session }
    var document: [String: Any] = [
      "apiVersion": OpenJoystickDriverAPI.version, "kind": ControllerRecordDocument.kind,
      "vendorID": 0x1234, "productID": 0xABCD,
      "modes": [["id": "default", "protocol": first], secondMode],
    ]
    document.merge(fields) { _, new in new }
    return document
  }

  private static func problem(_ record: [String: Any]) -> String? {
    do {
      _ = try ControllerRecordSet.validate(PropertyListFixture.data(tree: record))
      return nil
    } catch { return ControllerRecordSet.problemDescription(error, document: "record") }
  }

  private static func expectRejected(
    _ record: [String: Any],
    _ message: String,
    sourceLocation: SourceLocation = #_sourceLocation
  ) {
    let problem = Self.problem(record)
    #expect(
      problem?.contains(message) == true,
      "\(problem ?? "accepted")",
      sourceLocation: sourceLocation
    )
  }

  @Test
  func usbNeedsEveryModeRawUSB() {
    Self.expectRejected(
      Self.record(
        default: Self.gip,
        second: Self.hid,
        match: Self.hidMatch,
        fields: ["usb": ["configuration": "SetConfiguration1BeforeClaim"]]
      ),
      "USB overrides require a raw-USB protocol family"
    )
  }

  @Test
  func serverNeedsEveryModeHID() {
    Self.expectRejected(
      Self.record(
        default: Self.hid,
        second: Self.gip,
        match: Self.usbMatch,
        fields: ["server": "OJD"]
      ),
      "server applies only to HID controllers"
    )
  }

  @Test
  func routeNeedsEveryModeRawUSB() {
    Self.expectRejected(
      Self.record(
        default: Self.gip,
        second: Self.hid,
        match: Self.hidMatch,
        fields: ["route": "ExtensionOwned"]
      ),
      "route ExtensionOwned applies only to raw-USB controllers"
    )
  }

  @Test
  func aSessionFollowsTheProtocolOfItsOwnMode() {
    Self.expectRejected(
      Self.record(
        default: Self.gip,
        second: Self.hid,
        match: Self.hidMatch,
        session: ["settleMilliseconds": 200],
        fields: [:]
      ),
      "session settleMilliseconds applies only to raw-USB modes"
    )
  }

  @Test
  func tuningKeysAreReadByEveryMode() {
    Self.expectRejected(
      Self.record(
        default: ["family": "SonyDualShock4"],
        second: ["family": "VendorPS3ThirdParty"],
        match: Self.hidMatch,
        fields: ["tuning": ["inputLivenessTimeoutMs": 500]]
      ),
      "inputLivenessTimeoutMs is not read by the VendorPS3ThirdParty driver"
    )
  }

  @Test
  func bluetoothLENeedsEveryModeSwitch2() {
    Self.expectRejected(
      Self.record(
        default: ["family": "NintendoSwitch2"],
        second: Self.hid,
        match: Self.hidMatch,
        fields: [
          "bluetoothLE": ["vibrationCharacteristic": "00000000-0000-0000-0000-000000000000"]
        ]
      ),
      "bluetoothLE requires a driver that reads it"
    )
  }

  @Test
  func usbEndpointsDifferFromTheDefaultOfSomeMode() {
    Self.expectRejected(
      Self.record(
        default: ["family": "XboxXUSB", "variant": "Receiver"],
        second: ["family": "XboxXUSB", "variant": "Wired"],
        match: Self.usbMatch,
        fields: ["usb": ["endpoints": ["in": 129, "out": 1]]]
      ),
      "protocol-default endpoints must be omitted"
    )
    #expect(
      Self.problem(
        Self.record(
          default: Self.gip,
          second: ["family": "XboxXUSB", "variant": "Wired"],
          match: Self.usbMatch,
          fields: ["usb": ["endpoints": ["in": 129, "out": 1]]]
        )
      ) == nil
    )
  }

  @Test
  func aHIDUsageMapNeedsEveryModeHIDDescriptor() {
    let usage: [String: Any] = ["kind": "Button", "page": 9, "usage": 1, "control": "South"]
    Self.expectRejected(
      Self.record(
        default: ["family": "HIDDescriptor"],
        second: Self.hid,
        match: Self.hidMatch,
        fields: ["input": ["hidUsageMap": ["usages": [usage]]]]
      ),
      "a HID usage map applies only to a driver that reads one, in every mode"
    )
  }

  @Test
  func presentControlsAreDeclaredByTheDriverOfSomeMode() {
    let present =
      (ProtocolDescription.bundled[.sonyDualSense]?.recordCapabilities.presentControls ?? [])
      .map(\.rawValue).sorted()
    let fields: [String: Any] = ["capabilities": ["present": present]]
    #expect(
      Self.problem(
        Self.record(
          default: ["family": "SonyDualSense"],
          second: Self.hid,
          match: Self.hidMatch,
          fields: fields
        )
      ) == nil
    )
    Self.expectRejected(
      Self.record(
        default: Self.gip,
        second: Self.hid,
        match: Self.hidMatch,
        fields: fields
      ),
      "capabilities must be deltas the driver of some mode declares"
    )
  }
}
