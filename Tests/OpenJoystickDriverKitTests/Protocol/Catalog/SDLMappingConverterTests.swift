import Testing

@testable import OpenJoystickDriverKit

struct SDLMappingConverterTests {
  /// Two axes, one hat and sixteen buttons, listed in a different order than SDL sorts them.
  private static let elements: [HIDElementDescription] =
    [
      sdlElement(1, 0x31, order: 0), sdlElement(1, 0x30, order: 1),
      sdlElement(1, 0x39, order: 2, range: 0...7),
    ] + (1...16).map { sdlElement(9, UInt32($0), order: 2 + $0) }

  private static func convert(
    _ fields: [String],
    elements: [HIDElementDescription] = elements
  )
    throws(SDLMappingRejection) -> SDLConvertedMapping
  {
    try SDLMappingConverter.convert(fields: fields, elements: elements)
  }

  private func rejection(_ fields: [String]) -> String? {
    do {
      _ = try Self.convert(fields)
      return nil
    } catch {
      return error.reason
    }
  }

  // MARK: - Fixtures

  @Test
  func everyFixtureLineConvertsToItsUsageMap() throws {
    let fixtures = try SDLMappingFixture.all()
    #expect(fixtures.count >= 3)
    for (name, fixture) in fixtures {
      let converted = try SDLMappingConverter.convert(
        fields: fixture.fields,
        elements: fixture.elements
      )
      #expect(converted.usageMap.rendered.sorted() == fixture.expected.sorted(), "\(name)")
      #expect(converted.unmapped == fixture.expectedUnmapped, "\(name)")
    }
  }

  @Test
  func everyFixtureLineIsLineDatabaseHoldsForItsPad() throws {
    for (name, fixture) in try SDLMappingFixture.all() {
      let guid = try #require(SDLGameControllerDatabase.guid(of: fixture.physicalDevice))
      let match = try #require(SDLGameControllerDatabase.bundled.match(guid), "\(name)")
      #expect(match.tier.rawValue == fixture.expectedTier, "\(name)")
      #expect(fixture.line.hasPrefix(match.guid.description), "\(name)")
      #expect(match.fields == fixture.fields, "\(name)")
    }
  }

  // MARK: - Binding forms

  @Test
  func buttonIndexesSortedButtonList() throws {
    let map = try Self.convert(["a:b0", "b:b15"]).usageMap
    #expect(map.rendered == ["9/1 button South", "9/16 button East"])
  }

  @Test
  func axisIndexesSortedAxisList() throws {
    let map = try Self.convert(["leftx:a0", "lefty:a1"]).usageMap
    #expect(map.rendered == ["1/48 axis LeftStickX", "1/49 axis LeftStickY"])
  }

  @Test
  func tildeInvertsAxis() throws {
    let map = try Self.convert(["lefty:a1~"]).usageMap
    #expect(map.rendered == ["1/49 axis LeftStickY inverted"])
  }

  @Test
  func hatBindsOnceForDirectionBitItHolds() throws {
    let map = try Self.convert(["dpup:h0.1", "dpright:h0.2", "dpdown:h0.4", "dpleft:h0.8"]).usageMap
    #expect(map.rendered == ["1/57 hat"])
  }

  @Test
  func hatBitOfAnotherDirectionIsUnmapped() throws {
    let converted = try Self.convert(["dpup:h0.2", "a:b0"])
    #expect(converted.unmapped == ["dpup"])
  }

  @Test
  func halfAxesPressAtHalfRange() throws {
    let map = try Self.convert(["dpup:-a1", "dpdown:+a1", "x:+a0", "y:a0~"]).usageMap
    #expect(
      map.rendered == [
        "1/49 axisDpad DpadUp Negative 0.5", "1/49 axisDpad DpadDown Positive 0.5",
        "1/48 axisButton West Positive 0.5", "1/48 axisButton North Negative 0.5",
      ]
    )
    #expect(SDLMappingConverter.sdlAxisButtonThreshold == 0.5)
  }

  @Test
  func halfAxisOnTriggerReadsItsHalf() throws {
    let map = try Self.convert(["lefttrigger:+a0", "righttrigger:-a1"]).usageMap
    #expect(
      map.rendered == ["1/48 halfAxis LeftTrigger Positive", "1/49 halfAxis RightTrigger Negative"]
    )
  }

  @Test
  func buttonOnTriggerIsDigitalTrigger() throws {
    let map = try Self.convert(["lefttrigger:b4"]).usageMap
    #expect(map.rendered == ["9/5 buttonTrigger LeftTrigger"])
  }

  // MARK: - Unmapped controls and rejections

  @Test
  func buttonOnStickAxisIsUnmapped() throws {
    let converted = try Self.convert(["a:b0", "leftx:b2"])
    #expect(converted.unmapped == ["leftx"])
    #expect(converted.usageMap.rendered == ["9/1 button South"])
  }

  @Test
  func buttonOnDpadDirectionReadsItsPositiveHalf() throws {
    let map = try Self.convert(["dpup:b1", "dpleft:b4"]).usageMap
    #expect(
      map.rendered == ["9/2 axisDpad DpadUp Positive 0.5", "9/5 axisDpad DpadLeft Positive 0.5"]
    )
  }

  @Test
  func halfAxisOnStickIsUnmapped() throws {
    let converted = try Self.convert(["a:b0", "leftx:+a0"])
    #expect(converted.unmapped == ["leftx"])
  }

  @Test
  func unknownControlNameIsUnmapped() throws {
    let converted = try Self.convert(["a:b0", "unknown:b1", "platform:Mac OS X"])
    #expect(converted.unmapped == ["unknown"])
  }

  @Test
  func indexPastListRejectsLine() {
    #expect(rejection(["a:b16"]) == "the field \"a:b16\" names b16 but the pad lists 16")
    #expect(rejection(["leftx:a2"]) == "the field \"leftx:a2\" names a2 but the pad lists 2")
    #expect(rejection(["dpup:h1.1"]) == "the field \"dpup:h1.1\" names h1 but the pad lists 1")
  }

  @Test
  func hatWithoutEightPositionsRejectsLine() throws {
    let elements = [sdlElement(1, 0x39, order: 0, range: 0...3)]
    #expect(throws: SDLMappingRejection.self) {
      try Self.convert(["dpup:h0.1"], elements: elements)
    }
  }

  @Test
  func unreadableBindingRejectsLine() {
    for field in ["a", "a:", "a:x1", "a:b", "a:h0", "a:h0.3", "a:+b1", "a:b1~", "no-colon"] {
      #expect(rejection([field]) != nil, "\(field)")
    }
  }

  @Test
  func lineThatMapsNothingIsRejected() {
    #expect(rejection(["leftx:b1", "platform:Mac OS X"]) == "no control can be mapped")
  }

  @Test
  func twoControlsOnOneUsageAreRejected() {
    #expect(rejection(["a:b0", "b:b0"]) != nil)
  }

  @Test
  func everyControlNameIsKnownControl() {
    #expect(SDLMappingConverter.controlNames.count == 32)
  }
}
