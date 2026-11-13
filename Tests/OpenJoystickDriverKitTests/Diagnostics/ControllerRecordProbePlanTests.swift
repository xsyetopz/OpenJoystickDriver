import Foundation
import OpenJoystickDriverTestSupport
import ProtocolPacketFixtures
import Testing

@testable import OpenJoystickDriverKit

struct ControllerRecordProbePlanTests {
  @Test
  func loadsGIPRecordWithDefaultStartupSequence() throws {
    let plan = try ControllerRecordProbePlan(data: try recordData())

    #expect(plan.name == "Controller 1532:0a43")
    #expect(plan.vendorID == 5_426)
    #expect(plan.productID == 2_627)
    #expect(plan.transportProfile.interfaceNumber == 0)
    #expect(plan.transportProfile.inputEndpoint == 130)
    #expect(plan.transportProfile.outputEndpoint == 2)
    #expect(!plan.transportProfile.needsSetConfiguration)
    #expect(plan.startupPackets.isEmpty)
    #expect(plan.keepAlivePolicy == .enabled)
    #expect(plan.makeUnobservedDriver() is GIPDriver)
  }

  @Test
  func probeBuildsItsDriverOnlyForClaimThatSatisfiesContract() throws {
    let plan = try ControllerRecordProbePlan(data: try recordData())
    let device = USBTransportDevice(
      route: .rawUSB,
      serviceID: 1,
      vendorID: plan.vendorID,
      productID: plan.productID,
      locationID: 1
    )
    func claim(subclass: UInt8) -> USBTransportResolution {
      let profile = plan.transportProfile
      let interface = PhysicalInterfaceSignature(
        interfaceNumber: profile.interfaceNumber,
        alternateSetting: profile.alternateSetting,
        interfaceClass: 0xFF,
        interfaceSubclass: subclass,
        interfaceProtocol: 0xD0,
        endpoints: [
          PhysicalEndpointSignature(
            address: profile.inputEndpoint,
            direction: .in,
            transferType: .interrupt
          ),
          PhysicalEndpointSignature(
            address: profile.outputEndpoint,
            direction: .out,
            transferType: .interrupt
          ),
        ]
      )
      return USBTransportResolution(
        profile: profile,
        physicalDevice: PhysicalDevice(interfaces: [interface])
      )
    }
    #expect(try plan.makeDriver(for: device, claimed: claim(subclass: 0x47)).get() is GIPDriver)
    #expect(
      plan.makeDriver(for: device, claimed: claim(subclass: 0x5D)).failureReason
        == .interfaceContractMismatch
    )
  }

  @Test
  func loadsRecordSelectedStartupAndTransportOptions() throws {
    let plan = try ControllerRecordProbePlan(
      data: try recordData(
        configuration: "SetConfiguration1BeforeClaim",
        settleMilliseconds: 200,
        initialization: [
          "XboxGIP/power-on", "XboxGIP/s-init", "XboxGIP/led-on", "XboxGIP/auth-done",
        ]
      )
    )

    #expect(plan.transportProfile.needsSetConfiguration)
    #expect(plan.transportProfile.postHandshakeSettleNanoseconds == 200_000_000)
    #expect(
      plan.startupPackets == [
        "XboxGIP/power-on", "XboxGIP/s-init", "XboxGIP/led-on", "XboxGIP/auth-done",
      ]
    )
  }

  @Test
  func loadsXbox360RecordWithoutGIPStartup() throws {
    let plan = try ControllerRecordProbePlan(
      data: try recordData(family: "XboxXUSB", variant: "Wired")
    )

    let parser = try #require(plan.makeUnobservedDriver() as? XUSBDriver)

    #expect(plan.protocolBinding == ProtocolBindingID(.xboxXUSB, variant: .wired))
    #expect(plan.startupPackets.isEmpty)
    #expect(parser.startupWrites().isEmpty)
  }

  @Test
  func loadsGIPRecordWithKeepAliveDisabled() throws {
    let plan = try ControllerRecordProbePlan(data: try recordData(keepAliveEnabled: false))
    let parser = try #require(plan.makeUnobservedDriver() as? GIPDriver)

    #expect(plan.keepAlivePolicy == .disabled)
    #expect(parser.keepAlivePolicy == .disabled)
  }

  @Test
  func loadsXbox360WirelessReceiverRecord() throws {
    let plan = try ControllerRecordProbePlan(
      data: try recordData(
        family: "XboxXUSB",
        variant: "Receiver",
        inputEndpoint: 129,
        outputEndpoint: 1
      )
    )
    let parser = try #require(plan.makeUnobservedDriver() as? XUSBDriver)

    #expect(plan.protocolBinding.variant == .receiver)
    #expect(parser.sessionPlan.requiresInputConnectionBeforeOutput)
    // The receiver's presence inquiry, on the record's output endpoint.
    #expect(parser.startupWrites().usbPackets.map(\.endpoint) == [0x01])
    #expect(
      parser.startupWrites().usbBytes == [
        [0x08, 0x00, 0x0F, 0xC0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
      ]
    )
  }

  @Test
  func rejectsInvalidEndpointDirections() {
    #expect(throws: ControllerRecordProbeError.self) {
      try ControllerRecordProbePlan(data: try recordData(inputEndpoint: 2, outputEndpoint: 130))
    }
  }

  @Test
  func rejectsUnknownGIPInitializationAction() {
    for action in ["XboxGIP/not-a-real-action", "notAnAction"] {
      #expect(throws: ControllerRecordProbeError.self) {
        try ControllerRecordProbePlan(data: try recordData(initialization: [action]))
      }
    }
  }

  @Test
  func rejectsUnsupportedProtocolBeforeHardwareAccess() {
    #expect(throws: ControllerRecordProbeError.self) {
      try ControllerRecordProbePlan(data: try recordData(family: "HIDDescriptor", variant: nil))
    }
  }

  @Test
  func validationAcceptsHIDReportLayoutRecordThatNoProbeCanDrive() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let data = try Data(
      contentsOf: root.appending(path: "Resources/Controllers/04b4/04b4-2412.plist")
    )
    let protocolID = try ControllerRecordProbePlan.validate(data: data)
    #expect(protocolID == .hidReportLayout)
    #expect(!ControllerRecordProbePlan.probeableProtocols.contains(protocolID))
    #expect(throws: ControllerRecordProbeError.unsupportedProtocol("HIDReportLayout")) {
      try ControllerRecordProbePlan(data: data)
    }
  }

  @Test
  func validationRejectsInvalidRecord() throws {
    let data = try mutatedRecord { $0["vendorID"] = "not a number" }
    #expect(throws: ControllerRecordProbeError.self) {
      try ControllerRecordProbePlan.validate(data: data)
    }
  }

  @Test(arguments: [0x3208, 0x5750])
  func rejectsBootloaderIdentityBeforeHardwareAccess(productID: Int) throws {
    let data = try mutatedRecord {
      $0["vendorID"] = 0x2DC8
      $0["productID"] = productID
    }
    #expect(throws: ControllerRecordProbeError.bootloaderIdentity) {
      try ControllerRecordProbePlan(data: data)
    }
  }

  @Test
  func rejectsHIDFamilyBeforeHardwareAccess() {
    #expect(throws: ControllerRecordProbeError.self) {
      try ControllerRecordProbePlan(data: try recordData(family: "SonyDualShock4", variant: nil))
    }
  }

  @Test
  func rejectsUnknownRecordField() {
    #expect(throws: ControllerRecordProbeError.self) {
      try ControllerRecordProbePlan(data: try mutatedRecord { $0["notAField"] = "usb" })
    }
  }

  @Test
  func appliesShareOffsetAndRumbleGatingLikeRuntime() throws {
    let plain = try #require(
      try ControllerRecordProbePlan(data: try recordData()).makeUnobservedDriver() as? GIPDriver
    )
    let gated = try #require(
      try ControllerRecordProbePlan(
        data: try mutatedRecord { record in
          var protocolConfig = Self.defaultProtocol(of: record)
          protocolConfig["parameters"] = ["shareButton": ["fromEnd": 26]]
          Self.setDefaultProtocol(protocolConfig, in: &record)
          record["capabilities"] = ["rumble": "Absent"]
        }
      ).makeUnobservedDriver() as? GIPDriver
    )
    // The 44-byte Series X firmware 5.5 payload carries Share at byte 18 (SDL, xpad).
    var payload = Data(repeating: 0, count: 44)
    payload[18] = 1
    let packet = ProtocolPacketFixtures.GIP.inputPacket(payload: payload)

    #expect(try gated.parseReport(packet).contains(.press(.capture)))
    #expect(try !plain.parseReport(packet).contains(.press(.capture)))
    #expect(gated.outputCapabilities.rumbleMotors.isEmpty)
    #expect(!plain.outputCapabilities.rumbleMotors.isEmpty)
  }

  @Test
  func rejectsMissingOrWrongCurrentSchemaIdentity() {
    #expect(throws: ControllerRecordProbeError.self) {
      try ControllerRecordProbePlan(data: try recordData(apiVersion: nil))
    }
    let unsupportedVersion = #expect(throws: ControllerRecordProbeError.self) {
      try ControllerRecordProbePlan(
        data: try recordData(apiVersion: "unsupported.example/v9")
      )
    }
    #expect(unsupportedVersion?.errorDescription?.hasPrefix("E5001: ") == true)
    let noKind = #expect(throws: ControllerRecordProbeError.self) {
      try ControllerRecordProbePlan(data: try recordData(kind: nil))
    }
    #expect(noKind?.errorDescription?.hasPrefix("E5007: ") == true)
    let wrongKind = #expect(throws: ControllerRecordProbeError.self) {
      try ControllerRecordProbePlan(data: try recordData(kind: "NotAKind"))
    }
    #expect(wrongKind?.errorDescription?.hasPrefix("E5007: ") == true)
  }

  @Test
  func bundledModelStillBuildsPlan() throws {
    let plan = try ControllerRecordProbePlan(data: try recordData())
    let model = ControllerModelID(vendorID: plan.vendorID, productID: plan.productID)
    #expect(ControllerRecordSet.bundled.records[model] != nil)
  }

  @Test
  func rejectsUnknownFields() {
    #expect(throws: ControllerRecordProbeError.self) {
      try ControllerRecordProbePlan(data: try recordData(extraRootField: "notAField"))
    }
    #expect(throws: ControllerRecordProbeError.self) {
      try ControllerRecordProbePlan(data: try recordData(extraProtocolField: "notAField"))
    }
  }

  @Test
  func rejectsSchemaInvalidOptionalValues() {
    for mutation in [
      { (record: inout [String: Any]) in record["usb"] = [:] },
      { (record: inout [String: Any]) in record["usb"] = ["interface": 0] },
      { (record: inout [String: Any]) in
        Self.setSession(["settleMilliseconds": 60_001], in: &record)
      },
      { (record: inout [String: Any]) in
        var protocolConfig = Self.defaultProtocol(of: record)
        protocolConfig["parameters"] = [String: Any]()
        Self.setDefaultProtocol(protocolConfig, in: &record)
      },
      { (record: inout [String: Any]) in
        var protocolConfig = Self.defaultProtocol(of: record)
        protocolConfig["initialization"] = ["XboxGIP/power-on", "XboxGIP/power-on"]
        Self.setDefaultProtocol(protocolConfig, in: &record)
      },
      { (record: inout [String: Any]) in
        var protocolConfig = Self.defaultProtocol(of: record)
        protocolConfig["parameters"] = ["gyro": true]
        Self.setDefaultProtocol(protocolConfig, in: &record)
      },
      { (record: inout [String: Any]) in
        var protocolConfig = Self.defaultProtocol(of: record)
        protocolConfig["startupPackets"] = ["XboxGIP/power-on"]
        Self.setDefaultProtocol(protocolConfig, in: &record)
      }, { (record: inout [String: Any]) in record["usb"] = ["endpoints": ["in": 130, "out": 2]] },
    ] {
      #expect(throws: ControllerRecordProbeError.self) {
        try ControllerRecordProbePlan(data: try mutatedRecord(mutation))
      }
    }
  }

  private static func defaultProtocol(of record: [String: Any]) -> [String: Any] {
    let modes = record["modes"] as? [[String: Any]]
    return modes?.first?["protocol"] as? [String: Any] ?? [:]
  }

  private static func setSession(_ session: [String: Any], in record: inout [String: Any]) {
    var modes = record["modes"] as? [[String: Any]] ?? []
    modes[0]["session"] = session
    record["modes"] = modes
  }

  private static func setDefaultProtocol(_ info: [String: Any], in record: inout [String: Any]) {
    record["modes"] = [["id": "default", "protocol": info]]
  }

  private func recordData(
    family: String = "XboxGIP",
    variant: String? = nil,
    inputEndpoint: Int = 130,
    outputEndpoint: Int = 2,
    configuration: String? = nil,
    settleMilliseconds: Int? = nil,
    initialization: [String]? = nil,
    keepAliveEnabled: Bool? = nil,
    apiVersion: String? = OpenJoystickDriverAPI.version,
    kind: String? = ControllerRecordDocument.kind,
    extraRootField: String? = nil,
    extraProtocolField: String? = nil
  ) throws -> Data {
    let defaults = family == "XboxXUSB" ? (129, 1) : (130, 2)
    var usb: [String: Any] = [:]
    if (inputEndpoint, outputEndpoint) != defaults {
      usb["endpoints"] = ["in": inputEndpoint, "out": outputEndpoint]
    }
    if let configuration { usb["configuration"] = configuration }

    var protocolConfig: [String: Any] = ["family": family]
    if let variant { protocolConfig["variant"] = variant }
    if let initialization { protocolConfig["initialization"] = initialization }
    if let keepAliveEnabled { protocolConfig["keepAlive"] = keepAliveEnabled }
    if let extraProtocolField { protocolConfig[extraProtocolField] = true }

    var record: [String: Any] = ["vendorID": 5_426, "productID": 2_627]
    Self.setDefaultProtocol(protocolConfig, in: &record)
    if let settleMilliseconds {
      Self.setSession(["settleMilliseconds": settleMilliseconds], in: &record)
    }
    if let apiVersion { record["apiVersion"] = apiVersion }
    if let kind { record["kind"] = kind }
    if let extraRootField { record[extraRootField] = ["source": "unknown"] }
    if !usb.isEmpty { record["usb"] = usb }
    return try PropertyListFixture.data(tree: record)
  }

  private func mutatedRecord(_ mutation: (inout [String: Any]) -> Void) throws -> Data {
    let data = try recordData()
    var record = try #require(PropertyListFixture.tree(data) as? [String: Any])
    mutation(&record)
    return try PropertyListFixture.data(tree: record)
  }
}
