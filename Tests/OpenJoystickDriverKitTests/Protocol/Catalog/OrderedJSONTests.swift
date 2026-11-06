import Foundation
import Testing

@testable import OpenJoystickDriverKit

/// The record text format: the record, patch and sample files are the reference, byte for byte.
struct OrderedJSONTests {
  private static let repository = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()  // Catalog
    .deletingLastPathComponent()  // Protocol
    .deletingLastPathComponent()  // OpenJoystickDriverKitTests
    .deletingLastPathComponent()  // Tests
    .deletingLastPathComponent()

  private static func recordFiles(under directory: String) throws -> [URL] {
    let root = repository.appendingPathComponent(directory)
    let walker = try #require(
      FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
    )
    return (walker.allObjects as? [URL] ?? []).filter { $0.pathExtension == "json" }
      .sorted { $0.path < $1.path }
  }

  @Test
  func everyRecordFileRoundTripsByteForByte() throws {
    var checked = 0
    for directory in [
      "Resources/Controllers", "Resources/ControllerPatches",
      "Sources/OpenJoystickDriverKit/Resources/Controllers", "docs/sdk/sample/Controllers",
    ] {
      for url in try Self.recordFiles(under: directory) {
        let data = try Data(contentsOf: url)
        let text = try OrderedJSON.parse(data).formatted()
        #expect(text == String(bytes: data, encoding: .utf8), "\(url.path)")
        checked += 1
      }
    }
    #expect(checked > 600)
  }

  @Test
  func everyLoadedBundledRecordDocumentIsItsFileText() throws {
    for url in try Self.recordFiles(under: "Sources/OpenJoystickDriverKit/Resources/Controllers") {
      let document = try OrderedJSON.parse(Data(contentsOf: url))
      guard case .object(let members) = document,
        case .number(let vendor)? = members.first(where: { $0.key == "vendorID" })?.value,
        case .number(let product)? = members.first(where: { $0.key == "productID" })?.value,
        let vendorID = UInt16(vendor), let productID = UInt16(product)
      else {
        Issue.record("\(url.path) has no identity")
        continue
      }
      let record = ControllerRecordSet.bundled.records[
        ControllerModelID(vendorID: vendorID, productID: productID)
      ]
      #expect(record?.document == (try Data(contentsOf: url)), "\(url.path)")
    }
  }

  @Test
  func usesTheFileSpacing() throws {
    let text = try OrderedJSON.parse(Data(#"{"a":1,"b":[true,null],"c":{}}"#.utf8)).formatted()
    #expect(text == "{\n  \"a\": 1,\n  \"b\": [true, null],\n  \"c\": {}\n}\n")
  }

  @Test
  func arrayBreaksWhenItsLineWouldPass80Columns() throws {
    let word = String(repeating: "x", count: 30)
    let value = OrderedJSON.object([
      .init(key: "k", value: .array([.string(word), .string(word)]))
    ])
    // `  "k": ["` + 30 + `", "` + 30 + `"]` is 2 + 5 + 1 + 32 + 2 + 32 + 1 = 75 columns.
    #expect(value.formatted().contains("[\"\(word)\", \"\(word)\"]"))
    let wide = OrderedJSON.object([
      .init(key: "k", value: .array([.string(word + "yyyyyyyyyy"), .string(word)]))
    ])
    #expect(wide.formatted().contains("[\n    \"\(word)yyyyyyyyyy\",\n    \"\(word)\"\n  ]"))
  }

  @Test
  func objectMembersKeepTheOrderOfTheGuideThenSort() throws {
    let object: [String: Any] = ["z": 1, "a": 2, "m": 3, "b": 4]
    let guide = OrderedJSON.object([
      .init(key: "m", value: .null), .init(key: "z", value: .null),
    ])
    let text = try OrderedJSON(foundation: object, order: guide).formatted()
    #expect(text == "{\n  \"m\": 3,\n  \"z\": 1,\n  \"a\": 2,\n  \"b\": 4\n}\n")
  }

  @Test
  func foundationValuesKeepBooleansIntegersAndFractions() throws {
    let object: [String: Any] = ["flag": true, "count": 7, "ratio": 0.02, "none": NSNull()]
    let text = try OrderedJSON(foundation: object).formatted()
    #expect(
      text == "{\n  \"count\": 7,\n  \"flag\": true,\n  \"none\": null,\n  \"ratio\": 0.02\n}\n"
    )
  }

  @Test
  func stringsKeepEscapesAndUnicode() throws {
    let source = #"{"k":"a\"b\\c\/d\n\t\u0001é\ud83d\ude00"}"#
    let value = try OrderedJSON.parse(Data(source.utf8))
    #expect(value.formatted() == "{\n  \"k\": \"a\\\"b\\\\c/d\\n\\t\\u0001é😀\"\n}\n")
  }

  @Test
  func numbersKeepTheirText() throws {
    let value = try OrderedJSON.parse(Data("[-1.5e3, 0, 10E+2]".utf8))
    #expect(value.formatted() == "[-1.5e3, 0, 10E+2]\n")
  }

  @Test(arguments: [
    "", "{", "[1,]", "{\"a\" 1}", "01", "\"\\x\"", "nul", "[1] 2", "\"\\ud800\"", "\"\\u+0FF\"",
  ])
  func malformedTextFails(_ text: String) {
    #expect(throws: OrderedJSON.Problem.self) { try OrderedJSON.parse(Data(text.utf8)) }
  }

  private static func problem(_ bytes: [UInt8]) -> OrderedJSON.Problem? {
    do {
      _ = try OrderedJSON.parse(Data(bytes))
      return nil
    } catch { return error as? OrderedJSON.Problem }
  }

  @Test
  func aMemberNamedTwiceInOneObjectIsRefused() {
    let problem = Self.problem(Array(#"{"a": {"b": 1, "b": 2}}"#.utf8))
    #expect(problem == OrderedJSON.Problem(reason: .duplicateMember("b"), offset: 15))
    #expect(
      problem?.description == #"JSON text, byte 15: the member "b" appears twice in one object"#
    )
    #expect(Self.problem(Array(#"[{"b": 1}, {"b": 2}]"#.utf8)) == nil)
  }

  @Test
  func aByteOrderMarkIsRefusedByName() {
    let problem = Self.problem([0xEF, 0xBB, 0xBF] + Array("{}".utf8))
    #expect(problem?.reason == .byteOrderMark)
    #expect(
      problem?.description
        == "JSON text, byte 0: the text starts with a byte order mark; save the file as UTF-8 "
        + "without one"
    )
  }

  @Test(arguments: [
    [UInt8]([0xFF, 0xFE, 0x7B, 0x00, 0x7D, 0x00]), [0xFE, 0xFF, 0x00, 0x7B, 0x00, 0x7D],
    [0x7B, 0x00, 0x7D, 0x00], [0x00, 0x7B, 0x00, 0x7D],
  ])
  func utf16TextIsRefusedByName(_ bytes: [UInt8]) {
    #expect(Self.problem(bytes)?.reason == .wideEncoding)
    #expect(
      Self.problem(bytes)?.description.hasSuffix(
        "the text is UTF-16 or UTF-32; save the file as UTF-8"
      ) == true
    )
  }

  /// A zero byte past the first four bytes is a grammar problem at its offset, not a wide
  /// encoding; the first problem in the text is the one reported.
  @Test
  func aZeroByteInUTF8TextIsASyntaxProblem() {
    let inString = Self.problem(Array(#"{"name": "a"#.utf8) + [0x00] + Array(#""}"#.utf8))
    let words = "a zero byte, which JSON text cannot carry"
    #expect(inString == OrderedJSON.Problem(reason: .syntax(words), offset: 11))
    #expect(inString?.description == "JSON text, byte 11: \(words)")
    let afterBadByte = Self.problem(Array(#"{"k": "#.utf8) + [0xC3, 0x28, 0x00] + Array("}".utf8))
    #expect(afterBadByte == OrderedJSON.Problem(reason: .notUTF8, offset: 6))
  }

  @Test
  func bytesThatAreNotUTF8AreRefusedWithTheirOffset() {
    let problem = Self.problem(Array(#"{"k": "é"#.utf8) + [0xC3, 0x28] + Array(#""}"#.utf8))
    #expect(problem == OrderedJSON.Problem(reason: .notUTF8, offset: 9))
  }

  /// A guided number keeps its file text when the value is the same; a changed value is written
  /// from the value.
  @Test(arguments: [
    ("1e3", "1e3"), ("1.5e-7", "1.5e-7"), ("100.50", "100.50"), ("-0", "-0"), ("1E+2", "1E+2"),
    ("18446744073709551616", "18446744073709551616"), ("0.10", "0.10"), ("7", "7"),
  ])
  func aGuidedNumberKeepsItsText(_ source: String, _ written: String) throws {
    let data = Data("{\"n\": \(source)}".utf8)
    let value = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    let text = try OrderedJSON(foundation: value, order: OrderedJSON.parse(data)).formatted()
    #expect(text == "{\n  \"n\": \(written)\n}\n")
  }

  @Test
  func aChangedNumberIsWrittenFromItsValue() throws {
    let guide = try OrderedJSON.parse(Data(#"{"n": 1e3, "m": 100.50}"#.utf8))
    let value: [String: Any] = ["n": 1001, "m": 0.25]
    let text = try OrderedJSON(foundation: value, order: guide).formatted()
    #expect(text == "{\n  \"n\": 1001,\n  \"m\": 0.25\n}\n")
  }

  @Test(arguments: [
    ("1.5e-7", "1.5e-7"), ("1e20", "1e20"), ("1e300", "1e300"), ("2.5e-300", "2.5e-300"),
    ("1e3", "1000.0"), ("100.50", "100.5"), ("-0", "0"),
    ("18446744073709551616", "18446744073709551616"),
    ("3.14159265358979323846", "3.14159265358979323846"), ("-5", "-5"),
  ])
  func anUnguidedNumberIsWrittenFromItsValue(_ source: String, _ written: String) throws {
    let data = Data("[\(source)]".utf8)
    let value = try JSONSerialization.jsonObject(with: data)
    #expect(try OrderedJSON(foundation: value).formatted() == "[\(written)]\n")
  }

  @Test
  func columnsCountWideCharactersTwiceAndMarksNever() {
    #expect(OrderedJSON.columns("abc") == 3)
    #expect(OrderedJSON.columns("日本語") == 6)
    #expect(OrderedJSON.columns("한국어") == 6)
    #expect(OrderedJSON.columns("ＡＢ") == 4)
    #expect(OrderedJSON.columns("😀") == 2)
    #expect(OrderedJSON.columns("e\u{301}") == 1)
    #expect(OrderedJSON.columns("a\u{200B}b") == 2)
  }

  /// `biome format` output for `{"k": [s, s]}` with `s` 16 and 17 ideographs: 79 columns stay on
  /// one line, 83 break, while the line is 47 and 49 characters long.
  @Test
  func anArrayOfWideTextBreaksByColumns() throws {
    func formatted(_ count: Int) -> String {
      let word = OrderedJSON.string(String(repeating: "日", count: count))
      return OrderedJSON.object([.init(key: "k", value: .array([word, word]))]).formatted()
    }
    let fits = String(repeating: "日", count: 16)
    #expect(formatted(16) == "{\n  \"k\": [\"\(fits)\", \"\(fits)\"]\n}\n")
    let wide = String(repeating: "日", count: 17)
    #expect(formatted(17) == "{\n  \"k\": [\n    \"\(wide)\",\n    \"\(wide)\"\n  ]\n}\n")
  }

  private static func numbers(_ texts: [String]) -> OrderedJSON {
    .object([.init(key: "x", value: .array(texts.map(OrderedJSON.number)))])
  }

  /// The expected texts are `biome format` output for the same documents.
  @Test
  func aNumberArrayThatDoesNotFitFillsItsLinesAsBiomeDoes() {
    #expect(
      Self.numbers((1...40).map(String.init)).formatted() == """
        {
          "x": [
            1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21,
            22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40
          ]
        }

        """
    )
    #expect(
      Self.numbers(Array(repeating: "1111111", count: 9) + Array(repeating: "9", count: 20))
        .formatted() == """
          {
            "x": [
              1111111, 1111111, 1111111, 1111111, 1111111, 1111111, 1111111, 1111111,
              1111111, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9
            ]
          }

          """
    )
  }

  /// A line holds 80 columns with its comma; the last line has no comma.
  @Test
  func aFilledLineHoldsEightyColumns() {
    let nines = String(repeating: "9, ", count: 25).dropLast()
    let last = String(repeating: "9, ", count: 26).dropLast(2)
    #expect(
      Self.numbers(["111"] + Array(repeating: "9", count: 40)).formatted().split(separator: "\n")
        .map(\.count).max() == 80
    )
    #expect(
      Self.numbers(Array(repeating: "9", count: 51)).formatted() == """
        {
          "x": [
            \(nines)
            \(last)
          ]
        }

        """
    )
  }

  @Test
  func twoNamesThatDifferOnlyByCanonicalEquivalenceAreRefused() {
    let precomposed = "\u{E9}"
    let decomposed = "e\u{301}"
    #expect(precomposed == decomposed)
    let problem = Self.problem(Array(#"{"\#(precomposed)": 1, "\#(decomposed)": 2}"#.utf8))
    #expect(
      problem
        == OrderedJSON.Problem(reason: .equivalentMembers(precomposed, decomposed), offset: 10)
    )
    #expect(problem?.description.contains("different scalars") == true)
    // The same scalars twice stay a duplicate, and distinct names stay apart.
    #expect(
      Self.problem(Array(#"{"\#(decomposed)": 1, "\#(decomposed)": 2}"#.utf8))?.reason
        == .duplicateMember(decomposed)
    )
    #expect(Self.problem(Array(#"{"\#(precomposed)": 1, "e": 2}"#.utf8)) == nil)
  }

  @Test
  func anObjectKeepsTheOrderOfItsGuideAndSortsTheRest() throws {
    let guide = OrderedJSON.object([
      .init(key: "z", value: .number("1")), .init(key: "m", value: .number("2")),
    ])
    let value = try OrderedJSON(foundation: ["a": 1, "m": 2, "z": 3, "b": 4], order: guide)
    #expect(value.formatted() == "{\n  \"z\": 3,\n  \"m\": 2,\n  \"a\": 1,\n  \"b\": 4\n}\n")
  }

  @Test
  func anArrayWithANonNumberPutsOneItemPerLine() {
    let items: [OrderedJSON] = (1...28).map { .number(String($0)) } + [.string("x")]
    let text = OrderedJSON.object([.init(key: "mix", value: .array(items))]).formatted()
    #expect(text.contains("[\n    1,\n    2,\n"))
    #expect(text.hasSuffix("    28,\n    \"x\"\n  ]\n}\n"))
  }

  @Test
  func theEncoderKeepsAnEmbeddedValueAsItIsAndSortsTheRest() throws {
    struct Output: Encodable {
      let zebra: Int
      let apple: [String]
      let record: OrderedJSON
      let ratio: Double
      let whole: Double
      let nothing: Int?
      let flag: Bool
    }
    let record = try OrderedJSON.parse(
      Data(
        #"{"z": 1.0, "a": 1e3, "m": [18446744073709551615, -0, 100.50], "s": "x", "n": null}"#.utf8
      )
    )
    let output = Output(
      zebra: 3,
      apple: ["b", "a/b"],
      record: record,
      ratio: 0.25,
      whole: 5,
      nothing: nil,
      flag: true
    )
    let encoded = try OrderedJSONEncoder().encode(output)
    #expect(
      encoded.compact()
        == #"{"apple":["b","a/b"],"flag":true,"ratio":0.25,"record":"#
        + #"{"z":1.0,"a":1e3,"m":[18446744073709551615,-0,100.50],"s":"x","n":null},"#
        + #""whole":5,"zebra":3}"#
    )
  }

  @Test
  func theEncoderWritesAnArrayOfEmbeddedValuesAndAnEmptyValueAsAnEmptyObject() throws {
    struct Empty: Encodable {}
    let list = try OrderedJSONEncoder().encode([OrderedJSON.number("1e400"), .string("x")])
    #expect(list == .array([.number("1e400"), .string("x")]))
    #expect(try OrderedJSONEncoder().encode(Empty()) == .object([]))
  }

  @Test(arguments: [Double.infinity, -Double.infinity, Double.nan])
  func theEncoderRefusesANumberJSONCannotHold(_ value: Double) {
    #expect(throws: EncodingError.self) { try OrderedJSONEncoder().encode([value]) }
  }

  @Test
  func anotherEncoderRefusesAnOrderedValue() {
    #expect(throws: EncodingError.self) { try JSONEncoder().encode(OrderedJSON.number("1e3")) }
  }

  @Test
  func compactWritesOneLineWithoutSpaces() throws {
    let value = try OrderedJSON.parse(Data(#"{"b": [1, {"c": "d\"e"}], "a": {}, "f": []}"#.utf8))
    #expect(value.compact() == #"{"b":[1,{"c":"d\"e"}],"a":{},"f":[]}"#)
  }

  /// Text `JSONSerialization` refuses, which the single reader of record files must refuse too.
  @Test(arguments: [
    #"{"a":"\ud800"}"#, "{\"a\":\"x\u{01}y\"}", #"{"a":01}"#, #"{"a":NaN}"#,
    String(repeating: "[", count: 600) + String(repeating: "]", count: 600),
  ])
  func textThatJSONSerializationRefusesIsRefused(_ text: String) {
    let data = Data(text.utf8)
    #expect(throws: (any Error).self) { try JSONSerialization.jsonObject(with: data) }
    #expect(throws: OrderedJSON.Problem.self) { try OrderedJSON.parse(data) }
  }

  /// This Foundation reads a trailing comma, so the reader of record files is stricter.
  @Test
  func aTrailingCommaIsRefused() {
    #expect(throws: OrderedJSON.Problem.self) { try OrderedJSON.parse(Data(#"{"a":1,}"#.utf8)) }
    #expect(throws: OrderedJSON.Problem.self) { try OrderedJSON.parse(Data(#"[1,]"#.utf8)) }
  }

  @Test
  func nestingIsAcceptedUpToTheLimit() throws {
    func nested(_ depth: Int) -> Data {
      Data((String(repeating: "[", count: depth) + String(repeating: "]", count: depth)).utf8)
    }
    _ = try OrderedJSON.parse(nested(OrderedJSON.Parser.maxDepth))
    #expect(throws: OrderedJSON.Problem.self) {
      try OrderedJSON.parse(nested(OrderedJSON.Parser.maxDepth + 1))
    }
  }
}
