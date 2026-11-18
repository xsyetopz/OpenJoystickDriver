import Foundation
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit

/// A publication state carries exactly the fields its state allows, as
/// `cli-output.schema.json` says.
struct ApplicationServicePublicationStatusTests {
  private static func decode(_ json: String) -> ApplicationServicePublicationStatus? {
    try? JSONDecoder().decode(ApplicationServicePublicationStatus.self, from: Data(json.utf8))
  }

  @Test(
    arguments: [
      #"{"state":"Published"}"#,
      #"{"state":"Published","target":"Generic","lastAttemptedNanoseconds":1}"#,
      #"{"state":"NotPublished","reason":"NoInputYet"}"#,
      #"{"state":"NotPublished","reason":"SystemGamepad","target":"SDLCompatible"}"#,
      #"{"state":"Failed","failure":"send failed"}"#,
    ]
  )
  func matchingStateAndFieldsDecode(json: String) {
    #expect(Self.decode(json) != nil)
  }

  @Test(
    arguments: [
      #"{"state":"Failed"}"#,
      #"{"state":"Failed","failure":""}"#,
      #"{"state":"Failed","reason":"NoInputYet","failure":"x"}"#,
      #"{"state":"Failed","reason":"NoInputYet"}"#,
      #"{"state":"NotPublished"}"#,
      #"{"state":"NotPublished","failure":"x"}"#,
      #"{"state":"NotPublished","reason":"NoInputYet","failure":"x"}"#,
      #"{"state":"Published","reason":"NoInputYet"}"#,
      #"{"state":"Published","failure":"x"}"#,
    ]
  )
  func mismatchedStateAndFieldsFailToDecode(json: String) {
    #expect(Self.decode(json) == nil)
  }

  @Test
  func eachFactoryRoundTripsWithItsFields() throws {
    let statuses: [ApplicationServicePublicationStatus] = [
      .published(target: .generic, lastAttemptedNanoseconds: 2, lastCompletedNanoseconds: 1),
      .notPublished(.sessionSuspended, target: .sdlCompatible),
      .failed("send failed"),
    ]
    for status in statuses {
      let decoded = try JSONDecoder().decode(
        ApplicationServicePublicationStatus.self,
        from: JSONEncoder().encode(status)
      )
      #expect(decoded == status)
    }
    #expect(statuses[0].state == .published && statuses[0].reason == nil)
    #expect(statuses[1].state == .notPublished && statuses[1].reason == .sessionSuspended)
    #expect(statuses[2].state == .failed && statuses[2].failure == "send failed")
  }

  @Test
  func reasonsAreSchemaEnum() throws {
    let schema = try JSONSchemaFiles.document(named: "cli-output.schema.json")
    let definitions = try #require(schema["$defs"] as? [String: Any])
    var node: Any = try #require(definitions["controllerShow"])
    for key in ["properties", "publication", "properties", "reason"] {
      node = try #require((node as? [String: Any])?[key])
    }
    let values = try #require((node as? [String: Any])?["enum"] as? [String])
    let reasons = ApplicationServicePublicationStatus.NotPublishedReason.allCases.map(\.rawValue)

    #expect(Set(reasons) == Set(values))
    #expect(reasons.count == values.count)
  }
}
