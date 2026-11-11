import Foundation
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit

extension ProtocolClassifierTests {
  // MARK: - Protocol description documents

  @Test
  func protocolDescriptionDecodesItsSignatures() throws {
    let signatures = try ProtocolDescription.decode(
      protocolDescription(signature: #""variant": "USB", "interfaceNumber": 0"#),
      fileName: "xbox-gip.plist"
    ).interfaceSignatures
    #expect(
      signatures == [
        ProtocolInterfaceSignature(
          protocolID: .xboxGIP,
          variant: .usb,
          interfaceClass: 0xFF,
          interfaceSubclass: 0x47,
          interfaceProtocol: 0xD0,
          requiredInterfaceNumber: 0
        )
      ]
    )
    #expect(ProtocolClassifier.signatures.count == 4)
  }

  @Test(
    arguments: [
      (
        #""variant": "USB", "endpoint": 129"#, "unknown field(s): endpoint",
        ErrorCode.invalidProtocolDescription
      ),
      (#""variant": "Wired""#, "XboxGIP has no variant Wired", ErrorCode.unknownProtocolVariant),
      (
        #""variant": "bluetooth""#, "XboxGIP has no variant bluetooth",
        ErrorCode.unknownProtocolVariant
      ),
    ]
  )
  func protocolDescriptionRejectsABadSignature(
    signature: String,
    problem: String,
    code: ErrorCode
  ) {
    let error = #expect(throws: ProtocolDescriptionProblem.self) {
      try ProtocolDescription.decode(
        protocolDescription(signature: signature),
        fileName: "xbox-gip.plist"
      )
    }
    #expect(error?.code == code)
    #expect(error?.detail.hasPrefix("xbox-gip.plist: ") == true)
    #expect(error?.description.contains(problem) == true)
  }

  @Test
  func protocolDescriptionRejectsABadHeader() {
    let cases: [(Data, String, ErrorCode)] = [
      (
        protocolDescription(signature: #""variant": "USB""#, extra: #""vendorID": 1118,"#),
        "unknown field(s): vendorID",
        .invalidProtocolDescription
      ),
      (
        protocolDescription(
          signature: #""variant": "USB""#,
          apiVersion: "unsupported.example/v9"
        ),
        "apiVersion unsupported.example/v9 is not supported; "
          + "the supported apiVersion is \(OpenJoystickDriverAPI.version)",
        .unsupportedAPIVersion
      ),
      (
        protocolDescription(signature: #""variant": "USB""#, kind: "Controller"),
        "expected \(ProtocolDescription.kind), found Controller",
        .invalidProtocolDescription
      ),
      (
        protocolDescription(signature: #""variant": "USB""#, family: "XboxXUSB"),
        "file name must be xbox-xusb.plist",
        .protocolDescriptionFamilyMismatch
      ),
    ]
    for (data, problem, code) in cases {
      let error = #expect(throws: ProtocolDescriptionProblem.self) {
        try ProtocolDescription.decode(
          data,
          fileName: "xbox-gip.plist"
        )
      }
      #expect(error?.code == code)
      #expect(error?.detail.contains(problem) == true)
    }
  }

  @Test
  func protocolDescriptionSchemaAdmitsEveryVariantName() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent()
    let url = root.appendingPathComponent(
      "Resources/Schemas/protocol-description.schema.json"
    )
    let schema = try #require(
      JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
    )
    let definitions = schema["$defs"] as? [String: Any]
    let variant = definitions?["variant"] as? [String: Any]
    #expect(variant?["enum"] as? [String] == PhysicalProtocolVariantID.allCases.map(\.rawValue))
  }

  // MARK: - Helpers

  func protocolDescription(
    signature: String,
    extra: String = "",
    apiVersion: String = OpenJoystickDriverAPI.version,
    kind: String = ProtocolDescription.kind,
    family: String = "XboxGIP"
  ) -> Data {
    let protocolID = PhysicalProtocolID(rawValue: family)
    let keys = protocolID.map(ProtocolDescriptionFixture.sessionKeyMembers) ?? ""
    let variants = protocolID.map(ProtocolDescriptionFixture.variantMembers) ?? ""
    return PropertyListFixture.bytes(
      json: """
        {
          \(extra)
          "apiVersion": "\(apiVersion)",
          "kind": "\(kind)",
          "family": "\(family)",
          \(variants)
          \(keys)
          "endpoints": {"in": 130, "out": 2},
          "defaults": {"session": {"handshakeAttempts": 3, "announceResendLimit": 8,
            "namedPackets": [
            {"id": "XboxGIP/power-on", "bytes": "05 20 00 01 00", "sessionByte": 2}
          ]}},
          "interfaceSignatures": [
            {\(signature), "interfaceClass": 255, "interfaceSubclass": 71, "interfaceProtocol": 208}
          ]
        }
        """
    )
  }
}
