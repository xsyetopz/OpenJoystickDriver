import Foundation
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit

@Suite
struct CommandLineNameTests {
  /// `Tests/CommandLineNames/samples.json`: test data that only this suite reads.
  ///
  /// It lists the spellings `CommandLineName.kebab` must produce, and document values whose
  /// spellings must all differ.
  private struct Samples: Decodable {
    let spellings: [String: String]
    let values: [String]
  }

  private enum Sample: String, CaseIterable {
    case hidDescriptor = "HIDDescriptor"
    case xboxGIP = "XboxGIP"
    case vendorPS3 = "VendorPS3ThirdParty"
    case w3c = "W3C"
    case lowFrequency = "LowFrequency"
  }

  private enum Colliding: String, CaseIterable {
    case word = "Ab"
    case acronym = "AB"
  }

  private static func samples() throws -> Samples {
    let file = EquivalenceSnapshotStore.directory.deletingLastPathComponent()
      .appendingPathComponent("CommandLineNames/samples.json")
    return try JSONDecoder().decode(Samples.self, from: Data(contentsOf: file))
  }

  @Test
  func kebabSplitsAcronymRunsAsSamplesSay() throws {
    let samples = try Self.samples()
    #expect(!samples.spellings.isEmpty)
    for (value, expected) in samples.spellings {
      #expect(CommandLineName.kebab(value) == expected, "\(value)")
    }
  }

  @Test
  func kebabSpellingsOfSampleValuesAreDistinct() throws {
    let values = try Self.samples().values
    #expect(Set(values.map(CommandLineName.kebab)).count == values.count)
  }

  @Test
  func argumentSelectsCaseWhoseSpellingItIs() {
    #expect(CommandLineName.collisions(in: Sample.self).isEmpty)
    for sample in Sample.allCases {
      #expect(CommandLineName.value(of: CommandLineName.kebab(sample.rawValue)) == sample)
    }
  }

  @Test
  func argumentThatIsNotKebabSpellingSelectsNothing() {
    #expect(CommandLineName.value(of: "HIDDescriptor", in: Sample.self) == nil)
    #expect(CommandLineName.value(of: "hid_descriptor", in: Sample.self) == nil)
    #expect(CommandLineName.value(of: "", in: Sample.self) == nil)
  }

  @Test
  func valuesThatShareSpellingAreReported() {
    #expect(CommandLineName.collisions(in: Colliding.self) == [["AB", "Ab"]])
  }
}
