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
    #expect(!plan.transportProfile.needsSetConfiguration)
    #expect(plan.startupPackets == GIPStartupPacket.defaultSequence)
    #expect(plan.keepAlivePolicy == .enabled)
    #expect(plan.makeParser() is GIPParser)
  }

  @Test func loadsRecordSelectedStartupAndTransportOptions() throws {
    let plan = try ControllerRecordProbePlan(
      data: try recordData(
        configuration: "set1-before-claim",
        settleMilliseconds: 200,
        startupPackets: ["powerOn", "xboxOneSInit", "ledOn", "authDone"]
      )
    )

    #expect(plan.transportProfile.needsSetConfiguration)
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

  private func recordData(
    driver: String = "GIP",
    variant: String = "xboxOne",
    transport: String = "usb",
    inputEndpoint: Int = 130,
    outputEndpoint: Int = 2,
    configuration: String? = nil,
    settleMilliseconds: Int? = nil,
    startupPackets: [String]? = nil,
    keepAliveEnabled: Bool? = nil
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

    var record: [String: Any] = [
      "$schema": "https://raw.githubusercontent.com/xsyetopz/OpenJoystickDriver/main/"
        + "Resources/Schemas/controller.schema.json",
      "vendor_id": 5_426, "product_id": 2_627,
      "transport": transport, "protocol": protocolConfig,
      "provenance": ["source": "local-hardware", "verified": false],
    ]
    if !usb.isEmpty { record["usb"] = usb }
    return try JSONSerialization.data(withJSONObject: record)
  }
}
