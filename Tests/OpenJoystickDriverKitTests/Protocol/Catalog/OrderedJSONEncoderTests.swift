import Foundation
import Testing

@testable import OpenJoystickDriverKit

/// `OrderedJSONEncoder` writes what `JSONEncoder` with `.sortedKeys` and `.withoutEscapingSlashes`
/// writes for a Swift value, which is the reference here.
struct OrderedJSONEncoderTests {
  private static func reference(_ value: some Encodable) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return try #require(String(bytes: try encoder.encode(value), encoding: .utf8))
  }

  private static func written(_ value: some Encodable) throws -> String {
    try OrderedJSONEncoder().encode(value).compact()
  }

  private struct Integers: Encodable {
    let int8: Int8 = .min
    let int16: Int16 = .max
    let int32: Int32 = .min
    let int64Min: Int64 = .min
    let int64Max: Int64 = .max
    let int: Int = .min
    let uint8: UInt8 = .max
    let uint16: UInt16 = .max
    let uint32: UInt32 = .max
    let uint64: UInt64 = .max
    let uint: UInt = .max
    let zero = 0
  }

  private struct Floats: Encodable {
    let values: [Double] = [
      0, -0.0, 1, -1, 0.1, 0.25, 100.5, 1e3, 1e15, 1e16, 1e21, 1e22, 1.5e300, 1e-5, 1e-7,
      5e-324, .greatestFiniteMagnitude, .leastNormalMagnitude, 9_007_199_254_740_992,
      0.30000000000000004, 123_456_789.123_456_79,
    ]
    let singles: [Float] = [
      0, -0.0, 1, 0.1, 1e-5, 1e7, 16_777_216, 3.4028235e38, .leastNonzeroMagnitude, 0.3,
    ]
  }

  private struct Foundations: Encodable {
    let date = Date(timeIntervalSinceReferenceDate: 12_345.678)
    let data = Data([0, 1, 254, 255])
    let id = UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")
    let url = URL(string: "https://example.com/a/b?c=d")
    let decimal = Decimal(string: "12.5")
  }

  private struct Inner: Encodable {
    let id: Int
    let tags: [String]
  }

  private struct Outer: Encodable {
    let zebra: [[Inner]]
    let apple: [String: Inner]
    let optional: Inner?
    let nothing: [Int]?
    let text: String
    let flag: [Bool]
  }

  private struct Keyed: Encodable {
    enum Key: String, CodingKey { case second, first, `super` }
    func encode(to encoder: any Encoder) throws {
      var container = encoder.container(keyedBy: Key.self)
      try container.encode(2, forKey: .second)
      var nested = container.nestedContainer(keyedBy: Key.self, forKey: .first)
      try nested.encode("x", forKey: .second)
      var list = nested.nestedUnkeyedContainer(forKey: .first)
      try list.encode(1)
      try list.encodeNil()
      var item = list.nestedContainer(keyedBy: Key.self)
      try item.encode(true, forKey: .first)
      try container.encodeNil(forKey: .super)
    }
  }

  private struct Single: Encodable {
    let value: Int64
    func encode(to encoder: any Encoder) throws {
      var container = encoder.singleValueContainer()
      try container.encode(value)
    }
  }

  private struct WithKeyedSuper: Encodable {
    func encode(to encoder: any Encoder) throws {
      var container = encoder.container(keyedBy: Keyed.Key.self)
      try container.encode(1, forKey: .first)
      try Inner(id: 7, tags: ["t"]).encode(to: container.superEncoder())
    }
  }

  private struct WithUnkeyedSuper: Encodable {
    func encode(to encoder: any Encoder) throws {
      var list = encoder.unkeyedContainer()
      try list.encode("a")
      try Inner(id: 7, tags: []).encode(to: list.superEncoder())
      try list.encode(2.5)
    }
  }

  @Test
  func integersAtTheirExtremesAreWrittenAsTheirDigits() throws {
    let written = try Self.written(Integers())
    #expect(written == (try Self.reference(Integers())))
    #expect(written.contains("\"int64Min\":-9223372036854775808"))
    #expect(written.contains("\"uint64\":18446744073709551615"))
  }

  @Test
  func floatingPointNumberIsWrittenAsJSONEncoderWritesIt() throws {
    #expect(try Self.written(Floats()) == (try Self.reference(Floats())))
  }

  @Test
  func foundationValuesAreWrittenAsJSONEncoderWritesThem() throws {
    let written = try Self.written(Foundations())
    let reference = try Self.reference(Foundations())
    #expect(written == reference)
  }

  @Test
  func nestedValuesAndOptionalsAreWrittenAsJSONEncoderWritesThem() throws {
    let inner = Inner(id: 1, tags: ["b", "a/b", "\u{1}\u{7f}\"\\\n\u{2028}é😀"])
    let value = Outer(
      zebra: [[inner], []],
      apple: ["z": inner, "a": Inner(id: 2, tags: [])],
      optional: nil,
      nothing: nil,
      text: "x",
      flag: [true, false]
    )
    #expect(try Self.written(value) == (try Self.reference(value)))
  }

  @Test
  func membersAreSortedAsJSONEncoderSortsThem() throws {
    let value = [
      "b": 1, "a": 2, "B": 3, "é": 4, "\u{FF5E}": 5, "\u{10000}": 6, "10": 7, "9": 8, "": 9,
    ]
    #expect(try Self.written(value) == (try Self.reference(value)))
  }

  @Test
  func keyedAndUnkeyedContainersNestAsJSONEncoderNestsThem() throws {
    #expect(try Self.written(Keyed()) == (try Self.reference(Keyed())))
  }

  @Test
  func singleValueContainerWritesValueItself() throws {
    let value = Single(value: .min)
    #expect(try Self.written(value) == (try Self.reference(value)))
    #expect(try Self.written([value, value]) == (try Self.reference([value, value])))
  }

  @Test
  func superEncoderWritesUnderItsKeyOrAtNextIndex() throws {
    #expect(try Self.written(WithUnkeyedSuper()) == (try Self.reference(WithUnkeyedSuper())))
    let keyed = try OrderedJSONEncoder().encode(WithKeyedSuper())
    #expect(keyed.compact() == #"{"first":1,"super":{"id":7,"tags":["t"]}}"#)
  }

  @Test
  func topLevelFoundationValueAndNonFiniteDecimalAreHandledAsJSONEncoderHandlesThem() throws {
    let data = Data([1, 2, 3])
    #expect(try OrderedJSONEncoder().encode(data) == .string("AQID"))
    #expect(try OrderedJSONEncoder().encode(Decimal(string: "0.08")) == .number("0.08"))
    #expect(throws: EncodingError.self) { try OrderedJSONEncoder().encode([Decimal.nan]) }
    #expect(throws: EncodingError.self) { try OrderedJSONEncoder().encode(["a": Float.nan]) }
  }
}
