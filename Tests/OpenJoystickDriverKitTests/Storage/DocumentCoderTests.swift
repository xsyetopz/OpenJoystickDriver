import Foundation
import Testing

@testable import OpenJoystickDriverKit

@Suite
struct DocumentCoderTests {
  private struct Sample: Codable, Equatable {
    var apiVersion: String
    var kind: String
    var smallest: Int64
    var largest: Int64
    var widest: UInt64
    var whole: Double
    var half: Double
    var names: [String]
  }

  private static let sample = Sample(
    apiVersion: OpenJoystickDriverAPI.version,
    kind: "Sample",
    smallest: .min,
    largest: .max,
    widest: .max,
    whole: 1,
    half: 0.5,
    names: ["a", "b"]
  )

  private func plist(_ body: String) -> Data {
    Data(
      """
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" \
      "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
      <plist version="1.0">
      \(body)
      </plist>

      """.utf8
    )
  }

  private func refusal(_ data: Data, file: String = "Record.plist") -> DocumentCoderError? {
    do { _ = try DocumentCoder.read(data, file: file) } catch let error as DocumentCoderError {
      return error
    } catch { return nil }
    return nil
  }

  @Test
  func anXMLPropertyListIsRead() throws {
    let data = plist("<dict><key>kind</key><string>Sample</string></dict>")
    let tree = try #require(try DocumentCoder.read(data, file: "Record.plist") as? [String: Any])
    #expect(tree["kind"] as? String == "Sample")
  }

  @Test
  func aBinaryPropertyListIsRefusedWithTheFileAndTheForm() throws {
    let data = try PropertyListSerialization.data(
      fromPropertyList: ["kind": "Sample"],
      format: .binary,
      options: 0
    )
    let error = try #require(refusal(data, file: "Profiles/Play.plist"))
    #expect(error.file == "Profiles/Play.plist")
    #expect(error.reason == .binary)
    #expect(error.code == .invalidDocumentForm)
    #expect(error.description.contains("Profiles/Play.plist"))
    #expect(error.description.contains("binary"))
  }

  @Test
  func jsonTextInAPlistFileIsRefusedWithTheFileAndTheForm() throws {
    let error = try #require(refusal(Data(#"{"kind": "Sample"}"#.utf8), file: "Play.plist"))
    #expect(error.file == "Play.plist")
    #expect(error.reason == .json)
    #expect(error.description.contains("JSON"))
  }

  @Test
  func anOldStylePropertyListIsRefused() throws {
    let error = try #require(refusal(Data(#"{ kind = Sample; }"#.utf8)))
    #expect(error.reason == .notXML)
  }

  @Test
  func aDateIsRefusedWithItsKeyPath() throws {
    let data = plist(
      """
      <dict><key>modes</key><array><dict><key>seen</key>\
      <date>2026-01-02T03:04:05Z</date></dict></array></dict>
      """
    )
    let error = try #require(refusal(data))
    #expect(error.reason == .unsupportedValue(keyPath: "modes[0].seen", kind: "date"))
    #expect(error.description.contains("modes[0].seen"))
  }

  @Test
  func aDataValueIsRefusedWithItsKeyPath() throws {
    let data = plist("<dict><key>blob</key><data>AAEC</data></dict>")
    let error = try #require(refusal(data))
    #expect(error.reason == .unsupportedValue(keyPath: "blob", kind: "data"))
  }

  @Test
  func aTypedReadRefusesTheSameForms() throws {
    let encoder = PropertyListEncoder()
    encoder.outputFormat = .binary
    let bytes = try encoder.encode(Self.sample)
    #expect(throws: DocumentCoderError.self) {
      try DocumentCoder.decode(Sample.self, from: bytes, file: "Sample.plist")
    }
    #expect(throws: DocumentCoderError.self) {
      try DocumentCoder.decode(Sample.self, from: Data(#"{"kind": "Sample"}"#.utf8), file: "x")
    }
  }

  @Test
  func theBytesOfACanonicalFileDoNotChangeOnARewrite() throws {
    let canonical = try DocumentCoder.encode(Self.sample)
    let typed = try DocumentCoder.decode(Sample.self, from: canonical, file: "Sample.plist")
    #expect(typed == Self.sample)
    #expect(try DocumentCoder.encode(typed) == canonical)
    let tree = try DocumentCoder.read(canonical, file: "Sample.plist")
    #expect(try DocumentCoder.write(tree) == canonical)
  }

  @Test
  func theCanonicalFormIsXMLWithSortedKeys() throws {
    let text = String(decoding: try DocumentCoder.encode(Self.sample), as: UTF8.self)
    #expect(text.hasPrefix("<?xml version=\"1.0\" encoding=\"UTF-8\"?>"))
    let keys = text.split(separator: "\n").compactMap { line -> String? in
      guard let start = line.range(of: "<key>"), let end = line.range(of: "</key>") else {
        return nil
      }
      return String(line[start.upperBound..<end.lowerBound])
    }
    #expect(keys == keys.sorted())
    #expect(keys.count == 8)
  }

  @Test
  func integersKeepTheirTypeAcrossTheSixtyFourBitRange() throws {
    let data = try DocumentCoder.encode(Self.sample)
    let text = String(decoding: data, as: UTF8.self)
    for value in ["-9223372036854775808", "9223372036854775807", "18446744073709551615"] {
      #expect(text.contains("<integer>\(value)</integer>"), "\(value)")
    }
    let tree = try #require(try DocumentCoder.read(data, file: "Sample.plist") as? [String: Any])
    #expect(tree["smallest"] as? Int64 == .min)
    #expect(tree["largest"] as? Int64 == .max)
    #expect(tree["widest"] as? UInt64 == .max)
  }

  @Test
  func realsStayRealsAndIntegersStayIntegers() throws {
    let data = plist(
      "<dict><key>int</key><integer>1</integer><key>real</key><real>1</real></dict>"
    )
    let tree = try #require(try DocumentCoder.read(data, file: "Sample.plist") as? [String: Any])
    // swiftlint:disable:next legacy_objc_type
    let integer = try #require(tree["int"] as? NSNumber)
    // swiftlint:disable:next legacy_objc_type
    let real = try #require(tree["real"] as? NSNumber)
    #expect(!CFNumberIsFloatType(integer))
    #expect(CFNumberIsFloatType(real))
    let text = String(decoding: try DocumentCoder.write(tree), as: UTF8.self)
    #expect(text.contains("<integer>1</integer>"))
    #expect(text.contains("<real>1</real>"))
    let typed = try DocumentCoder.decode(Sample.self, from: DocumentCoder.encode(Self.sample), file: "")
    #expect(typed.whole == 1 && typed.half == 0.5)
  }
}
