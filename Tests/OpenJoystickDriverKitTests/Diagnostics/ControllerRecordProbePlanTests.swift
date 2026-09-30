import Foundation
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
    #expect(plan.startupPackets == GIPStartupPacket.defaultSequence)
    #expect(plan.keepAlivePolicy == .enabled)
    #expect(plan.makeUnobservedDriver() is GIPDriver)
  }

  @Test
  func probeBuildsItsDriverOnlyForAClaimThatSatisfiesTheContract() throws {
    let plan = try ControllerRecordProbePlan(data: try recordData())
    let device = USBTransportDevice(
      route: .ioUSBHost,
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
        configuration: "set1-before-claim",
        settleMilliseconds: 200,
        initialization: [
          "xbox.gip/power-on", "xbox.gip/s-init", "xbox.gip/led-on", "xbox.gip/auth-done",
        ]
      )
    )

    #expect(plan.transportProfile.needsSetConfiguration)
    #expect(plan.transportProfile.postHandshakeSettleNanoseconds == 200_000_000)
    #expect(plan.startupPackets == [.powerOn, .xboxOneSInit, .ledOn, .authDone])
  }

  @Test
  func loadsXbox360RecordWithoutGIPStartup() throws {
    let plan = try ControllerRecordProbePlan(
      data: try recordData(family: "xbox.xusb", variant: "wired")
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
        family: "xbox.xusb",
        variant: "receiver",
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
  func rejectsUnknownOrRemovedGIPInitializationAction() {
    for action in ["xbox.gip/not-a-real-action", "powerOn"] {
      #expect(throws: ControllerRecordProbeError.self) {
        try ControllerRecordProbePlan(data: try recordData(initialization: [action]))
      }
    }
  }

  @Test
  func rejectsUnsupportedProtocolBeforeHardwareAccess() {
    #expect(throws: ControllerRecordProbeError.self) {
      try ControllerRecordProbePlan(data: try recordData(family: "hid.descriptor", variant: nil))
    }
  }

  @Test
  func rejectsHIDFamilyBeforeHardwareAccess() {
    #expect(throws: ControllerRecordProbeError.self) {
      try ControllerRecordProbePlan(data: try recordData(family: "sony.dualshock4", variant: nil))
    }
  }

  @Test
  func rejectsRemovedTransportField() {
    #expect(throws: ControllerRecordProbeError.self) {
      try ControllerRecordProbePlan(data: try mutatedRecord { $0["transport"] = "usb" })
    }
  }

  @Test
  func appliesShareOffsetAndRumbleGatingLikeTheRuntime() throws {
    let plain = try #require(
      try ControllerRecordProbePlan(data: try recordData()).makeUnobservedDriver() as? GIPDriver
    )
    let gated = try #require(
      try ControllerRecordProbePlan(
        data: try mutatedRecord { record in
          var protocolConfig = record["protocol"] as? [String: Any] ?? [:]
          protocolConfig["quirks"] = ["share-offset"]
          record["protocol"] = protocolConfig
          record["capabilities"] = ["rumble": "absent"]
        }
      ).makeUnobservedDriver() as? GIPDriver
    )
    // The 44-byte Series X firmware 5.5 payload carries Share at byte 18 (SDL, xpad).
    var payload = Data(repeating: 0, count: 44)
    payload[18] = 1
    let packet = ProtocolPacketFixtures.GIP.inputPacket(payload: payload)

    #expect(try gated.parseReport(packet).contains(.press(.share)))
    #expect(try !plain.parseReport(packet).contains(.press(.share)))
    #expect(gated.outputCapabilities.rumbleMotors.isEmpty)
    #expect(!plain.outputCapabilities.rumbleMotors.isEmpty)
  }

  @Test
  func rejectsMissingOrWrongCurrentSchemaIdentity() {
    #expect(throws: ControllerRecordProbeError.self) {
      try ControllerRecordProbePlan(data: try recordData(schemaID: nil))
    }
    #expect(throws: ControllerRecordProbeError.self) {
      try ControllerRecordProbePlan(data: try recordData(schemaID: "controller-v1"))
    }
  }

  @Test
  func rejectsRemovedOrUnknownFields() {
    #expect(throws: ControllerRecordProbeError.self) {
      try ControllerRecordProbePlan(data: try recordData(extraRootField: "provenance"))
    }
    #expect(throws: ControllerRecordProbeError.self) {
      try ControllerRecordProbePlan(data: try recordData(extraProtocolField: "confidence"))
    }
  }

  @Test
  func rejectsSchemaInvalidOptionalValues() {
    for mutation in [
      { (record: inout [String: Any]) in record["usb"] = [:] },
      { (record: inout [String: Any]) in record["usb"] = ["interface": 0] },
      { (record: inout [String: Any]) in record["usb"] = ["postHandshakeSettleMs": 60_001] },
      { (record: inout [String: Any]) in record["usb"] = NSNull() },
      { (record: inout [String: Any]) in
        var protocolConfig = record["protocol"] as? [String: Any] ?? [:]
        protocolConfig["quirks"] = []
        record["protocol"] = protocolConfig
      },
      { (record: inout [String: Any]) in
        var protocolConfig = record["protocol"] as? [String: Any] ?? [:]
        protocolConfig["initialization"] = ["xbox.gip/power-on", "xbox.gip/power-on"]
        record["protocol"] = protocolConfig
      },
      { (record: inout [String: Any]) in
        var protocolConfig = record["protocol"] as? [String: Any] ?? [:]
        protocolConfig["quirks"] = ["gyro"]
        record["protocol"] = protocolConfig
      },
      { (record: inout [String: Any]) in
        var protocolConfig = record["protocol"] as? [String: Any] ?? [:]
        protocolConfig["startupPackets"] = ["xbox.gip/power-on"]
        record["protocol"] = protocolConfig
      }, { (record: inout [String: Any]) in record["usb"] = ["endpoints": ["in": 130, "out": 2]] },
    ] {
      #expect(throws: ControllerRecordProbeError.self) {
        try ControllerRecordProbePlan(data: try mutatedRecord(mutation))
      }
    }
  }

  private func recordData(
    family: String = "xbox.gip",
    variant: String? = nil,
    inputEndpoint: Int = 130,
    outputEndpoint: Int = 2,
    configuration: String? = nil,
    settleMilliseconds: Int? = nil,
    initialization: [String]? = nil,
    keepAliveEnabled: Bool? = nil,
    schemaID: String? = ControllerRecordDocument.schemaID,
    extraRootField: String? = nil,
    extraProtocolField: String? = nil
  ) throws -> Data {
    let defaults = family == "xbox.xusb" ? (129, 1) : (130, 2)
    var usb: [String: Any] = [:]
    if (inputEndpoint, outputEndpoint) != defaults {
      usb["endpoints"] = ["in": inputEndpoint, "out": outputEndpoint]
    }
    if let configuration { usb["configuration"] = configuration }
    if let settleMilliseconds { usb["postHandshakeSettleMs"] = settleMilliseconds }

    var protocolConfig: [String: Any] = ["family": family]
    if let variant { protocolConfig["variant"] = variant }
    if let initialization { protocolConfig["initialization"] = initialization }
    if let keepAliveEnabled { protocolConfig["keepAlive"] = keepAliveEnabled }
    if let extraProtocolField { protocolConfig[extraProtocolField] = true }

    var record: [String: Any] = ["vendorID": 5_426, "productID": 2_627, "protocol": protocolConfig]
    if let schemaID { record["$schema"] = schemaID }
    if let extraRootField { record[extraRootField] = ["source": "legacy"] }
    if !usb.isEmpty { record["usb"] = usb }
    return try JSONSerialization.data(withJSONObject: record)
  }

  private func mutatedRecord(_ mutation: (inout [String: Any]) -> Void) throws -> Data {
    let data = try recordData()
    var record = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    mutation(&record)
    return try JSONSerialization.data(withJSONObject: record)
  }
}
