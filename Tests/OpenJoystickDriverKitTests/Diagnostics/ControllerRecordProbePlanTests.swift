import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct ControllerRecordProbePlanTests {
  @Test func loadsGIPRecordWithDefaultStartupSequence() throws {
    let plan = try ControllerRecordProbePlan(data: try recordData())

    #expect(plan.name == "Controller 1532:0a43")
    #expect(plan.vendorID == 5_426)
    #expect(plan.productID == 2_627)
    #expect(plan.interfaceNumber == 0)
    #expect(plan.transportProfile.inputEndpoint == 130)
    #expect(plan.transportProfile.outputEndpoint == 2)
    #expect(!plan.transportProfile.hasInterfaceOverride)
    #expect(!plan.transportProfile.hasEndpointOverride)
    #expect(!plan.transportProfile.needsSetConfiguration)
    #expect(plan.startupPackets == GIPStartupPacket.defaultSequence)
    #expect(plan.keepAlivePolicy == .enabled)
    #expect(plan.makeParser() is GIPParser)
  }

  @Test func loadsRecordSelectedStartupAndTransportOptions() throws {
    let plan = try ControllerRecordProbePlan(
      data: try recordData(
        inputEndpoint: 132,
        outputEndpoint: 5,
        configuration: "set1-before-claim",
        settleMilliseconds: 200,
        startupPackets: ["powerOn", "xboxOneSInit", "ledOn", "authDone"]
      )
    )

    #expect(plan.transportProfile.needsSetConfiguration)
    #expect(plan.transportProfile.hasEndpointOverride)
    #expect(plan.transportProfile.postHandshakeSettleNanoseconds == 200_000_000)
    #expect(plan.startupPackets == [.powerOn, .xboxOneSInit, .ledOn, .authDone])
  }

  @Test func loadsXbox360RecordWithoutGIPStartup() throws {
    let plan = try ControllerRecordProbePlan(
      data: try recordData(driver: "Xbox360", variant: "xbox360")
    )

    let parser = try #require(plan.makeParser() as? Xbox360Parser)

    #expect(plan.driver == .xbox360)
    #expect(plan.startupPackets.isEmpty)
    #expect(parser.usbStartupOutputPackets() == [[0x01, 0x03, 0x06]])
  }

  @Test func loadsGIPRecordWithKeepAliveDisabled() throws {
    let plan = try ControllerRecordProbePlan(data: try recordData(keepAliveEnabled: false))
    let parser = try #require(plan.makeParser() as? GIPParser)

    #expect(plan.keepAlivePolicy == .disabled)
    #expect(parser.keepAlivePolicy == .disabled)
  }

  @Test func loadsXbox360WirelessReceiverRecord() throws {
    let plan = try ControllerRecordProbePlan(
      data: try recordData(
        driver: "Xbox360",
        variant: "xbox360Wireless",
        inputEndpoint: 129,
        outputEndpoint: 1
      )
    )
    let parser = try #require(plan.makeParser() as? Xbox360Parser)

    #expect(plan.isWirelessReceiver)
    #expect(parser.requiresInputConnectionBeforeOutput)
    #expect(parser.usbStartupOutputPackets().isEmpty)
  }

  @Test func rejectsInvalidEndpointDirections() {
    #expect(throws: ControllerRecordProbeError.self) {
      try ControllerRecordProbePlan(data: try recordData(inputEndpoint: 2, outputEndpoint: 130))
    }
  }

  @Test func rejectsUnknownGIPStartupPacket() {
    #expect(throws: ControllerRecordProbeError.self) {
      try ControllerRecordProbePlan(data: try recordData(startupPackets: ["notARealPacket"]))
    }
  }

  @Test func rejectsUnsupportedProtocolBeforeHardwareAccess() {
    #expect(throws: ControllerRecordProbeError.self) {
      try ControllerRecordProbePlan(
        data: try recordData(driver: "GenericHID", variant: "genericHID")
      )
    }
  }

  @Test func rejectsHIDTransportBeforeHardwareAccess() {
    #expect(throws: ControllerRecordProbeError.self) {
      try ControllerRecordProbePlan(data: try recordData(transport: "hid"))
    }
  }

  @Test func rejectsMissingOrWrongCurrentSchemaIdentity() {
    #expect(throws: ControllerRecordProbeError.self) {
      try ControllerRecordProbePlan(data: try recordData(schemaID: nil))
    }
    #expect(throws: ControllerRecordProbeError.self) {
      try ControllerRecordProbePlan(data: try recordData(schemaID: "controller-v1"))
    }
  }

  @Test func rejectsRemovedOrUnknownFields() {
    #expect(throws: ControllerRecordProbeError.self) {
      try ControllerRecordProbePlan(data: try recordData(extraRootField: "provenance"))
    }
    #expect(throws: ControllerRecordProbeError.self) {
      try ControllerRecordProbePlan(data: try recordData(extraProtocolField: "confidence"))
    }
  }

  @Test func rejectsSchemaInvalidOptionalValues() {
    for mutation in [
      { (record: inout [String: Any]) in record["usb"] = [:] },
      { (record: inout [String: Any]) in record["usb"] = ["interface": 0] },
      { (record: inout [String: Any]) in record["usb"] = ["post_handshake_settle_ms": 60_001] },
      { (record: inout [String: Any]) in record["usb"] = NSNull() },
      { (record: inout [String: Any]) in
        var protocolConfig = record["protocol"] as? [String: Any] ?? [:]
        protocolConfig["flags"] = []
        record["protocol"] = protocolConfig
      },
      { (record: inout [String: Any]) in
        var protocolConfig = record["protocol"] as? [String: Any] ?? [:]
        protocolConfig["startup_packets"] = ["powerOn", "powerOn"]
        record["protocol"] = protocolConfig
      },
      { (record: inout [String: Any]) in
        var protocolConfig = record["protocol"] as? [String: Any] ?? [:]
        protocolConfig["flags"] = ["gyro"]
        record["protocol"] = protocolConfig
      }, { (record: inout [String: Any]) in record["usb"] = ["endpoints": ["in": 130, "out": 2]] }
    ] {
      #expect(throws: ControllerRecordProbeError.self) {
        try ControllerRecordProbePlan(data: try mutatedRecord(mutation))
      }
    }
  }

  private func recordData(
    driver: String = "GIP",
    variant: String = "xboxOne",
    transport: String = "usb",
    inputEndpoint: Int = 130,
    outputEndpoint: Int = 2,
    configuration: String? = nil,
    settleMilliseconds: Int? = nil,
    startupPackets: [String]? = nil,
    keepAliveEnabled: Bool? = nil,
    schemaID: String? = ControllerRecordDocument.schemaID,
    extraRootField: String? = nil,
    extraProtocolField: String? = nil
  ) throws -> Data {
    let defaults = driver == "Xbox360" ? (129, 1) : (130, 2)
    var usb: [String: Any] = [:]
    if (inputEndpoint, outputEndpoint) != defaults {
      usb["endpoints"] = ["in": inputEndpoint, "out": outputEndpoint]
    }
    if let configuration { usb["configuration"] = configuration }
    if let settleMilliseconds { usb["post_handshake_settle_ms"] = settleMilliseconds }

    var protocolConfig: [String: Any] = ["driver": driver, "variant": variant]
    if let startupPackets { protocolConfig["startup_packets"] = startupPackets }
    if let keepAliveEnabled { protocolConfig["keep_alive"] = keepAliveEnabled }
    if let extraProtocolField { protocolConfig[extraProtocolField] = true }

    var record: [String: Any] = [
      "vendor_id": 5_426, "product_id": 2_627, "transport": transport, "protocol": protocolConfig
    ]
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
