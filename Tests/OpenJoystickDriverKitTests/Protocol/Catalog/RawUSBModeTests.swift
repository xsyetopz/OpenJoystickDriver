import Foundation
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit

/// Raw-USB records may list alternative modes, selected from the passive facts of the enumerated
/// device, and a raw-USB mode's session names USB packets.
///
/// Every mode obeys the record-level rules the same way in a record with one mode and a record with
/// several.
struct RawUSBModeTests {
  private static let model = ControllerModelID(vendorID: 0x1234, productID: 0xABCD)

  private static func record(
    modes: [[String: Any]],
    extras: [String: Any] = [:]
  ) -> [String: Any] {
    [
      "apiVersion": OpenJoystickDriverAPI.version, "kind": ControllerRecordDocument.kind,
      "vendorID": Int(model.vendorID), "productID": Int(model.productID), "modes": modes,
    ].merging(extras) { $1 }
  }

  private static func problem(_ record: [String: Any]) -> String? {
    do {
      _ = try ControllerRecordSet.validate(PropertyListFixture.data(tree: record))
      return nil
    } catch { return ControllerRecordSet.problemDescription(error, document: "record") }
  }

  private static func gip(
    _ id: String,
    match: [String: Any]? = nil,
    extras: [String: Any] = [:]
  ) -> [String: Any] {
    var mode: [String: Any] = ["id": id, "protocol": ["family": "XboxGIP"]]
    mode["match"] = match
    return mode.merging(extras) { $1 }
  }

  private static var usbWrite: [String: Any] { ["bytes": "01 02"] }

  @Test
  func rawUSBRecordSelectsAlternativeModeFromItsInterfaceSignature() async throws {
    let signature: [String: Any] = [
      "interfaceClass": 255, "interfaceSubclass": 71, "interfaceProtocol": 208,
      "endpoints": [["direction": "In", "transferType": "Interrupt"]],
    ]
    let document = Self.record(modes: [
      Self.gip("default"),
      Self.gip(
        "alternative",
        match: ["interfaceSignature": signature],
        extras: ["session": ["startup": [Self.usbWrite]]]
      ),
    ])
    let profile = try #require(
      try ControllerRecordSet.validate(PropertyListFixture.data(tree: document)).record
    ).profile
    let matching = PhysicalDevice(
      vendorID: Self.model.vendorID,
      productID: Self.model.productID,
      interfaces: [
        PhysicalInterfaceSignature(
          interfaceNumber: 0,
          interfaceClass: 255,
          interfaceSubclass: 71,
          interfaceProtocol: 208,
          hostTransport: .usb,
          endpoints: [PhysicalEndpointSignature(direction: .in, transferType: .interrupt)]
        )
      ]
    )
    let plain = PhysicalDevice(
      vendorID: Self.model.vendorID,
      productID: Self.model.productID,
      interfaces: [PhysicalInterfaceSignature(interfaceNumber: 0, hostTransport: .usb)]
    )
    for backend in [DeviceAccessBackend.rawUSB, .usbExtension] {
      let selected = await ControllerModeSelector.select(
        from: profile,
        model: Self.model,
        backend: backend,
        reader: UnreadableModeProbeReader(),
        device: matching
      ) { _ in }
      let unmatched = await ControllerModeSelector.select(
        from: profile,
        model: Self.model,
        backend: backend,
        reader: UnreadableModeProbeReader(),
        device: plain
      ) { _ in }
      #expect(selected == .matched("alternative"))
      #expect(unmatched == .noModeMatched)
    }
    let running = try #require(profile.applying(modeID: "alternative"))
    #expect(running.usbStartupWrites.map(\.bytes) == [[1, 2]])
    #expect(profile.applying(modeID: nil)?.usbStartupWrites.isEmpty == true)
  }

  /// A raw-USB route has no feature-report read, so a mode that needs a probe never holds.
  @Test
  func rawUSBRouteNeverRunsProbeMode() async throws {
    let probe: [String: Any] = ["report": 1, "length": 8, "expect": "Answers"]
    let document = Self.record(modes: [
      Self.gip("default"), Self.gip("probed", match: ["probes": [probe]]),
    ])
    let profile = try #require(
      try ControllerRecordSet.validate(PropertyListFixture.data(tree: document)).record
    ).profile
    let selection = await ControllerModeSelector.select(
      from: profile,
      model: Self.model,
      backend: .rawUSB,
      reader: UnreadableModeProbeReader(),
      device: PhysicalDevice(vendorID: Self.model.vendorID, productID: Self.model.productID)
    ) { _ in }
    #expect(selection == .noProbeRoute)
  }

  @Test
  func rawUSBModeKeepsInterfaceAndHIDSessionOut() {
    let hidWrite: [String: Any] = [
      "report": ["kind": "Feature", "id": 1, "length": 2], "bytes": "02",
    ]
    let link: [String: Any] = ["link": "USB"]
    let rejected: [(String, [String: Any], String)] = [
      (
        "interface",
        Self.record(modes: [
          Self.gip("default"),
          Self.gip("a", match: link, extras: ["interface": ["first": 0, "last": 1]]),
        ]),
        "interface selects among HID interfaces"
      ),
      (
        "HID session",
        Self.record(modes: [
          Self.gip("default"),
          Self.gip("a", match: link, extras: ["session": ["startup": [hidWrite]]]),
        ]),
        "HID startup writes apply only to HID controllers, so not to a raw-USB mode"
      ),
      (
        "interface on a lone default",
        Self.record(modes: [
          Self.gip("default", extras: ["interface": ["first": 0, "last": 1]])
        ]),
        "interface selects among HID interfaces"
      ),
      (
        "USB packets in a HID mode",
        Self.record(modes: [
          [
            "id": "default", "protocol": ["family": "SonySixaxis"],
            "session": ["startup": [Self.usbWrite]],
          ]
        ]),
        "startup"
      ),
      (
        "a session naming nothing",
        Self.record(modes: [Self.gip("default", extras: ["session": [String: Any]()])]),
        "session"
      ),
    ]
    for (name, document, expected) in rejected {
      let problem = Self.problem(document)
      #expect(
        problem?.contains(expected) == true,
        Comment(rawValue: "\(name): \(problem ?? "accepted")")
      )
    }
  }

  /// A record with one mode gets the same per-mode layout, template and capability checks as a
  /// record with several.
  @Test
  func singleModeRecordObeysSamePerModeChecks() {
    let layout: [String: Any] = [
      "layouts": [
        [
          "report": ["length": ["atLeast": 8]],
          "buttons": [["control": "South", "bitOffset": 0, "bitSize": 1]],
        ]
      ]
    ]
    let rumble: [String: Any] = [
      "rumble": [
        "report": ["kind": "Output", "id": 2, "length": 8],
        "lowFrequency": ["byte": 3],
      ]
    ]
    func single(
      _ family: String,
      _ extras: [String: Any] = [:],
      session: [String: Any]? = nil
    ) -> [String: Any] {
      var mode: [String: Any] = ["id": "default", "protocol": ["family": family]]
      mode["session"] = session
      return Self.record(modes: [mode], extras: extras)
    }
    let rejected: [(String, [String: Any])] = [
      ("report-layout without a layout", single("HIDReportLayout")),
      ("layout under HIDDescriptor", single("HIDDescriptor", ["input": layout])),
      ("template under a family that does not encode it", single("SonySixaxis", session: rumble)),
      ("template under a raw-USB family", single("XboxGIP", session: rumble)),
    ]
    for (name, document) in rejected {
      #expect(Self.problem(document) != nil, Comment(rawValue: name))
    }
    #expect(Self.problem(single("HIDReportLayout", ["input": layout])) == nil)
    #expect(
      Self.problem(single("HIDReportLayout", ["input": layout], session: rumble)) == nil
    )
  }
}
