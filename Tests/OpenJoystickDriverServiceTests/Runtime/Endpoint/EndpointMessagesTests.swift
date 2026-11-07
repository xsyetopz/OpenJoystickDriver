import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverService

/// Round trips of the endpoint messages on `openjoystickdriver/v1alpha2` against
/// `endpoint.schema.json`: what Swift encodes the schema accepts, and what the schema accepts from
/// a client Swift decodes.
struct EndpointMessagesTests {
  private static let schema = "endpoint.schema.json"
  private static let nonce = String(repeating: "A", count: 43)

  private static func encoded(_ value: some Encodable) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return try #require(String(bytes: try encoder.encode(value), encoding: .utf8))
  }

  private static func issues(_ line: String) throws -> [String] {
    try JSONSchemaFiles.issues(in: line, against: schema)
  }

  @Test
  func theServiceLinesEncodeToLinesTheSchemaAccepts() throws {
    let lines = [
      try Self.encoded(EndpointChallenge(nonce: Self.nonce)),
      try Self.encoded(EndpointWelcome(version: "0.6.0", scopes: [.read, .control])),
      try Self.encoded(EndpointFeedSession(as: .generic)),
      try Self.encoded(EndpointFeedSession(as: .sdlCompatible)),
      try Self.encoded(EndpointError(code: .endpointDisabled, message: "off")),
      try Self.encoded(EndpointError(header: .unsupportedEndpointVersion, message: "version")),
      try Self.encoded(EndpointError(header: .unexpectedKind, message: "kind")),
      try Self.encoded(EndpointError(header: .missingHeader, message: "header")),
    ]
    for line in lines { #expect(try Self.issues(line).isEmpty, "\(line)") }
  }

  @Test
  func everyServiceLineCarriesTheVersionAndItsKind() throws {
    let expected: [(any Encodable, String)] = [
      (EndpointChallenge(nonce: Self.nonce), "Challenge"),
      (EndpointWelcome(version: "0.6.0", scopes: [.read]), "Welcome"),
      (EndpointFeedSession(as: .generic), "FeedSession"),
      (EndpointError(code: .feedClosed, message: "closed"), "Status"),
    ]
    for (message, kind) in expected {
      let object = try #require(
        try JSONSerialization.jsonObject(with: Data(Self.encoded(message).utf8))
          as? [String: Any]
      )
      #expect(object["apiVersion"] as? String == "openjoystickdriver/v1alpha2")
      #expect(object["kind"] as? String == kind)
    }
  }

  @Test
  func aFeedSessionNamesItsPersona() throws {
    let object = try #require(
      try JSONSerialization.jsonObject(
        with: Data(Self.encoded(EndpointFeedSession(as: .sdlCompatible)).utf8)
      ) as? [String: String]
    )
    #expect(object["as"] == "SDLCompatible")
    #expect(
      VirtualHIDProfileID.allCases.map(\.rawValue).sorted() == [
        "GameControllerCompatible", "Generic", "SDLCompatible",
      ]
    )
  }

  @Test
  func aFrameEncodesToALineTheSchemaAccepts() throws {
    let frame = VirtualFeedFrame(
      buttons: [.south],
      dpad: [.up],
      axes: [.leftStickX: 0.5],
      holdMilliseconds: 40
    )
    // The frame alone is the body that `ojd virtual feed` takes; the endpoint line adds the header.
    #expect(!(try Self.issues(Self.encoded(frame)).isEmpty))
    let line = try Self.encoded(EndpointFrame(frame))
    #expect(try Self.issues(line).isEmpty, "\(line)")
    #expect(EndpointHeader.refusal(of: Data(line.utf8), accepting: ["Frame"]) == nil)
    #expect(try JSONDecoder().decode(VirtualFeedFrame.self, from: Data(line.utf8)) == frame)
  }

  @Test(arguments: [
    (#"{"apiVersion":null,"kind":"Hello"}"#, ErrorCode.missingHeader),
    (#"{"apiVersion":"openjoystickdriver/v1alpha2","kind":null}"#, .missingHeader),
    (#"{"apiVersion":7,"kind":"Hello"}"#, .missingHeader),
    (#"{"apiVersion":"openjoystickdriver/v1alpha2","kind":{}}"#, .missingHeader),
    (#"{"kind":"Hello"}"#, .missingHeader),
    (#"{"apiVersion":"openjoystickdriver/v2","kind":null}"#, .missingHeader),
    (#"["Hello"]"#, .invalidMessage),
  ])
  func aHeaderThatIsMissingOrNotStringsIsRefused(line: String, code: ErrorCode) {
    #expect(EndpointHeader.refusal(of: Data(line.utf8), accepting: ["Hello"])?.code == code)
  }

  @Test(arguments: [
    clientLine("Hello", #","scopes":["Read","Control"]"#),
    clientLine("Subscription", #","stream":"Controllers","output":true"#),
    clientLine("FeedRequest", #","as":"Generic""#),
    clientLine("FeedRequest", #","as":"SDLCompatible""#),
  ])
  func aClientLineTheSchemaAcceptsDecodesInSwift(line: String) throws {
    #expect(try Self.issues(line).isEmpty)
    let request = try JSONDecoder().decode(EndpointRequest.self, from: Data(line.utf8))
    #expect(request.apiVersion == OpenJoystickDriverAPI.version)
    let accepted = [request.kind.rawValue]
    #expect(EndpointHeader.refusal(of: Data(line.utf8), accepting: accepted) == nil)
  }

  @Test(arguments: [
    clientLine("Frame"),
    clientLine(
      "Frame",
      #","buttons":["South","East"],"dpad":["DpadLeft"],"#
        + #""axes":{"LeftStickX":-1,"LeftTrigger":1},"holdMilliseconds":8"#
    ),
  ])
  func aFrameLineTheSchemaAcceptsDecodesInSwift(line: String) throws {
    #expect(try Self.issues(line).isEmpty)
    _ = try JSONDecoder().decode(VirtualFeedFrame.self, from: Data(line.utf8))
  }

  @Test(arguments: [
    clientLine("FeedRequest", #","as":"NotAPersona""#),
    clientLine("FeedSession", #","as":"NotAPersona""#),
    clientLine("Hello", #","scopes":[]"#),
    #"{"apiVersion":"unsupported.example/v9","kind":"Hello","scopes":["Read"]}"#,
    clientLine("Status", #","status":"Failure","code":"E1009","message":"m""#),
    clientLine(
      "Status",
      #","status":"Failure","code":"E1003","message":"m","details":"#
        + #"{"supportedAPIVersions":["openjoystickdriver/v1alpha2"]}"#
    ),
  ])
  func aLineOutsideTheSchemaIsRefused(line: String) throws {
    #expect(!(try Self.issues(line).isEmpty), "\(line)")
  }

  @Test(arguments: ["PointerX", "PointerY"])
  func aFrameWithAPointerAxisIsRefusedByTheSchemaAndSwift(axis: String) throws {
    let line = clientLine("Frame", #","axes":{"\#(axis)":0.5}"#)
    #expect(!(try Self.issues(line).isEmpty))
    #expect(throws: DecodingError.self) {
      try JSONDecoder().decode(VirtualFeedFrame.self, from: Data(line.utf8))
    }
  }
}
