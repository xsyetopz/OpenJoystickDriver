import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct CommandValueParserTests {
  @Test func parsesControllerSourceAndSystemTarget() throws {
    #expect(try RemappingCommandValueParser.source("button:south") == .button(.south))
    #expect(
      try RemappingCommandValueParser.destination("key:a:mods=command,shift")
        == .keyboard(key: .a, modifiers: [.command, .shift])
    )
  }

  @Test func profileFileStoreValidatesAndRoundTrips() throws {
    let profile = RemappingProfile(
      name: "Portable",
      device: RemappingDeviceScope(vendorID: 1118, productID: 654),
      applicationScope: .global,
      bindings: [
        RemappingBinding(
          source: .button(.south),
          destination: .keyboard(key: .space, modifiers: [])
        ),
      ]
    )
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      .appendingPathExtension("json")
    defer { try? FileManager.default.removeItem(at: url) }

    try RemappingProfileFileStore.write(profile, to: url)
    #expect(try RemappingProfileFileStore.load(from: url) == profile)
    #expect(try RemappingProfileFileStore.encodedJSON(profile).contains("Portable"))
  }
}
