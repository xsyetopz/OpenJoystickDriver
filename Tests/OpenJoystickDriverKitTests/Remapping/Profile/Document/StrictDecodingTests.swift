import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct RemappingProfileStrictDecodingTests {
  @Test(arguments: [
    "", "bindings.0", "bindings.0.source", "bindings.0.destination", "stickMappings.0",
    "gyroOutput", "layers.0", "layers.0.activator", "outputPolicy", "device", "applicationScope",
  ])
  func unknownKeyAnywhereRejectsProfile(path: String) throws {
    let components = path.split(separator: ".").map(String.init)
    let document = try inject("unexpected", into: sampleDocument(), at: components[...])
    let data = try JSONSerialization.data(withJSONObject: document)
    #expect(throws: DecodingError.self) {
      try JSONDecoder().decode(RemappingProfile.self, from: data)
    }
  }

  @Test
  func keyBelongingToAnotherKindIsRejected() {
    let decoder = JSONDecoder()
    #expect(throws: DecodingError.self) {
      try decoder.decode(
        RemappingSource.self,
        from: Data(#"{"type":"Axis","axis":"LeftStickX","button":"South"}"#.utf8)
      )
    }
    #expect(throws: DecodingError.self) {
      try decoder.decode(
        RemappingDestination.self,
        from: Data(#"{"type":"GamepadButton","button":"South","axis":"LeftStickX"}"#.utf8)
      )
    }
    #expect(throws: DecodingError.self) {
      try decoder.decode(
        RemappingPhysicalOutput.self,
        from: Data(#"{"type":"Brightness","intensity":0.5,"red":1}"#.utf8)
      )
    }
    #expect(throws: DecodingError.self) {
      try decoder.decode(
        RemappingApplicationScope.self,
        from: Data(#"{"type":"Global","appIDs":["com.example.app"]}"#.utf8)
      )
    }
  }

  @Test
  func applicationScopeWithAppIDRefusedByName() {
    do {
      _ = try JSONDecoder().decode(
        RemappingApplicationScope.self,
        from: Data(#"{"type":"Application","appID":"com.example.app"}"#.utf8)
      )
      Issue.record("appID was accepted")
    } catch DecodingError.dataCorrupted(let context) {
      #expect(context.debugDescription.contains("appID is not a key; use appIDs"))
    } catch {
      Issue.record("\(error)")
    }
  }

  @Test
  func sampleDocumentDecodesWithoutInjectedKeys() throws {
    let data = try JSONSerialization.data(withJSONObject: sampleDocument())
    let decoded = try JSONDecoder().decode(RemappingProfile.self, from: data)
    #expect(decoded.id == sampleProfile().id)
  }

  private func sampleProfile() -> RemappingProfile {
    RemappingProfile(
      id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
      name: "Strict",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .application(appIDs: ["com.example.app"]),
      outputPolicy: RemappingOutputPolicy(virtualGamepad: .mapped),
      gyroOutput: RemappingGyroOutput(mode: .mouse),
      stickMappings: [RemappingStickMapping(source: .right, mode: .flick)],
      bindings: [
        RemappingBinding(source: .button(.south), destination: .keyboard(key: .a, modifiers: []))
      ],
      layers: [
        RemappingLayer(name: "Layer", activationMode: .hold, activator: .button(.leftShoulder))
      ]
    )
  }

  private func sampleDocument() throws -> [String: Any] {
    let data = try JSONEncoder().encode(sampleProfile())
    return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
  }

  /// Adds `key` to the object found by following `path`; numeric components index arrays.
  private func inject(_ key: String, into node: Any, at path: ArraySlice<String>) throws -> Any {
    guard let step = path.first else {
      var object = try #require(node as? [String: Any])
      object[key] = true
      return object
    }
    if let index = Int(step) {
      var array = try #require(node as? [Any])
      array[index] = try inject(key, into: array[index], at: path.dropFirst())
      return array
    }
    var object = try #require(node as? [String: Any])
    object[step] = try inject(key, into: try #require(object[step]), at: path.dropFirst())
    return object
  }
}
