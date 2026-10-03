import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct VirtualHIDProfileOverrideStoreTests {
  private typealias Store = VirtualHIDProfileOverrideStore

  private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
    let suite = "VirtualHIDProfileOverrideStoreTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    try body(defaults)
  }

  private func storeJSON(_ json: String, in defaults: UserDefaults) {
    defaults.set(Data(json.utf8), forKey: Store.defaultsKey)
  }

  @Test
  func anAbsentKeyHasNoOverrides() throws {
    try withDefaults { defaults in
      let store = Store(defaults: defaults)
      #expect(store.override(vendorID: 0x045E, productID: 0x02EA) == nil)
      #expect(store.loadError == nil)
    }
  }

  @Test
  func anOverrideRoundTripsThroughTheDocumentedJSON() throws {
    try withDefaults { defaults in
      try Store(defaults: defaults).set(.generic, vendorID: 0x045E, productID: 0x02EA)

      #expect(Store(defaults: defaults).override(vendorID: 0x045E, productID: 0x02EA) == .generic)
      let data = try #require(defaults.data(forKey: Store.defaultsKey))
      let entries = try #require(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
      #expect(entries.count == 1)
      #expect(entries.first?["vendorID"] as? Int == 0x045E)
      #expect(entries.first?["productID"] as? Int == 0x02EA)
      #expect(entries.first?["profile"] as? String == "hid-generic")
    }
  }

  @Test
  func overridesAreIsolatedPerControllerModel() throws {
    try withDefaults { defaults in
      let store = Store(defaults: defaults)
      try store.set(.generic, vendorID: 0x045E, productID: 0x02EA)
      try store.set(.xboxOneSBluetooth, vendorID: 0x054C, productID: 0x0CE6)

      try store.reset(vendorID: 0x045E, productID: 0x02EA)

      #expect(store.override(vendorID: 0x045E, productID: 0x02EA) == nil)
      #expect(store.override(vendorID: 0x054C, productID: 0x0CE6) == .xboxOneSBluetooth)
      #expect(store.override(vendorID: 0x054C, productID: 0x02EA) == nil)
    }
  }

  @Test
  func aUnitOverrideBeatsItsModelAndResettingItFallsBack() throws {
    try withDefaults { defaults in
      let store = Store(defaults: defaults)
      try store.set(.generic, vendorID: 1, productID: 2)
      try store.set(.xboxOneSBluetooth, vendorID: 1, productID: 2, unit: "U-AbCd_123-xyzW09q")

      let restored = Store(defaults: defaults)
      #expect(
        restored.override(vendorID: 1, productID: 2, unit: "U-AbCd_123-xyzW09q")
          == .xboxOneSBluetooth
      )
      #expect(restored.override(vendorID: 1, productID: 2, unit: "U-0000000000000000") == .generic)
      #expect(restored.override(vendorID: 1, productID: 2) == .generic)
      #expect(restored.storedOverride(vendorID: 1, productID: 2, unit: "U-0000000000000000") == nil)
      let data = try #require(defaults.data(forKey: Store.defaultsKey))
      let entries = try #require(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
      #expect(entries.compactMap { $0["unit"] as? String } == ["U-AbCd_123-xyzW09q"])

      try restored.reset(vendorID: 1, productID: 2, unit: "U-AbCd_123-xyzW09q")
      #expect(restored.override(vendorID: 1, productID: 2, unit: "U-AbCd_123-xyzW09q") == .generic)
    }
  }

  @Test
  func resettingTheLastOverrideRemovesTheKey() throws {
    try withDefaults { defaults in
      let store = Store(defaults: defaults)
      try store.set(.generic, vendorID: 1, productID: 2)
      try store.reset(vendorID: 1, productID: 2)
      #expect(defaults.object(forKey: Store.defaultsKey) == nil)
    }
  }

  @Test
  func anUnknownProfileIsAnErrorSelectsAutomaticallyAndIsNeverRewritten() throws {
    try withDefaults { defaults in
      let json =
        #"[{"vendorID":1118,"productID":746,"profile":"xbox-360"},"#
        + #"{"vendorID":1356,"productID":3302,"profile":"hid-generic"}]"#
      storeJSON(json, in: defaults)
      let store = Store(defaults: defaults)

      #expect(store.loadError == .unsupportedValue("xbox-360"))
      #expect(store.override(vendorID: 1118, productID: 746) == nil)
      #expect(store.override(vendorID: 1356, productID: 3302) == nil)
      #expect(throws: VirtualHIDProfileOverrideError.unsupportedValue("xbox-360")) {
        try store.set(.generic, vendorID: 1, productID: 2)
      }
      #expect(throws: VirtualHIDProfileOverrideError.unsupportedValue("xbox-360")) {
        try store.reset(vendorID: 1118, productID: 746)
      }
      #expect(defaults.data(forKey: Store.defaultsKey) == Data(json.utf8))
    }
  }

  @Test(arguments: [
    #"{"vendorID":1,"productID":2,"profile":"hid-generic"}"#,
    #"[{"vendorID":1,"profile":"hid-generic"}]"#,
    #"[{"vendorID":70000,"productID":2,"profile":"hid-generic"}]"#,
    #"[{"vendorID":1,"productID":2,"profile":"hid-generic"},"#
      + #"{"vendorID":1,"productID":2,"profile":"hid-xbox-one-s-bt"}]"#, "not json",
  ])
  func anUnreadableSchemaIsAnErrorAndIsNeverRewritten(json: String) throws {
    try withDefaults { defaults in
      storeJSON(json, in: defaults)
      let store = Store(defaults: defaults)

      #expect(store.loadError == .unsupportedSchema)
      #expect(store.override(vendorID: 1, productID: 2) == nil)
      #expect(throws: VirtualHIDProfileOverrideError.unsupportedSchema) {
        try store.set(.generic, vendorID: 1, productID: 2)
      }
      #expect(defaults.data(forKey: Store.defaultsKey) == Data(json.utf8))
    }
  }

  @Test
  func aNonDataValueIsAnUnreadableSchema() throws {
    try withDefaults { defaults in
      defaults.set("hid-generic", forKey: Store.defaultsKey)
      #expect(Store(defaults: defaults).loadError == .unsupportedSchema)
    }
  }

  @Test
  func resetAllClearsAnUnreadableValueAndReenablesWrites() throws {
    try withDefaults { defaults in
      storeJSON(#"[{"vendorID":1,"productID":2,"profile":"retired"}]"#, in: defaults)
      let store = Store(defaults: defaults)

      store.resetAll()

      #expect(defaults.object(forKey: Store.defaultsKey) == nil)
      #expect(store.loadError == nil)
      try store.set(.xboxOneSBluetooth, vendorID: 1, productID: 2)
      #expect(store.override(vendorID: 1, productID: 2) == .xboxOneSBluetooth)
    }
  }
}
